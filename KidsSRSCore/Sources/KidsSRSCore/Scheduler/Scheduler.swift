import Foundation

/// Kid-tuned SM-2 scheduler with same-session learning steps.
///
/// Spec §7. This is a **pure value type**: `apply(_:to:)` takes the current
/// `SchedulerState` plus a `ReviewInput` and returns the next state. It has no
/// side effects, no clock of its own (the review time is passed in), and no
/// persistence — which is exactly what makes the riskiest correctness surface
/// in the product fully unit-testable.
///
/// Key kid-specific behaviors (Spec §7.1–§7.3):
///  - New cards pass through short learning steps (1m → 10m) before SM-2.
///  - A lapse in review does **not** merely shrink the interval; it sends the
///    card *back into learning steps* to re-solidify.
///  - Intervals are capped (`maxIntervalDays`) so kids revisit familiar content.
///  - Ease has a high floor and a gentle lapse penalty (no "ease hell").
///  - The confidence prediction is recorded as a flag but **never** alters the
///    schedule (Spec §6.4).
public struct Scheduler: Sendable {

    public let parameters: SchedulerParameters

    public init(parameters: SchedulerParameters) {
        self.parameters = parameters
    }

    public init(profile: PacingProfile) {
        self.parameters = .defaults(for: profile)
    }

    // MARK: - Public API

    /// Apply a child self-graded review to a card's state, returning the new state.
    public func apply(_ review: ReviewInput, to state: SchedulerState) -> SchedulerState {
        var next = state
        next.lastReviewedAt = review.reviewedAt
        next.lastConfidenceFlag = ConfidenceFlag(prediction: review.prediction, grade: review.grade)
        applyGrade(review.grade, now: review.reviewedAt, to: &next)
        return next
    }

    /// Apply a **parent** 3-level rating (Spec §14.4). This is a separate grading
    /// path: an adult judges the child, so there is no confidence prediction and
    /// **no metacognition flag is recorded or cleared**. "Knows it" / "Doesn't
    /// know it" reuse the same machinery as the two-button grade; "Getting there"
    /// is a *soft repeat* that re-shows the card soon while preserving the child's
    /// accumulated progress (no lapse, no ease penalty, no reset).
    public func apply(_ review: ParentReviewInput, to state: SchedulerState) -> SchedulerState {
        var next = state
        next.lastReviewedAt = review.reviewedAt
        switch review.grade {
        case .knowsIt:
            applyGrade(.gotIt, now: review.reviewedAt, to: &next)
        case .doesntKnowIt:
            applyGrade(.missedIt, now: review.reviewedAt, to: &next)
        case .gettingThere:
            applySoftRepeat(now: review.reviewedAt, to: &next)
        }
        return next
    }

    // MARK: - Grade routing

    /// Route a two-button grade through the card-lifecycle state machine.
    private func applyGrade(_ grade: Grade, now: Date, to next: inout SchedulerState) {
        switch next.status {
        case .new:
            // First-ever exposure: enter learning at step 0, then grade it.
            next.status = .learning
            next.learningStepIndex = 0
            applyLearning(grade: grade, now: now, to: &next)
        case .learning:
            applyLearning(grade: grade, now: now, to: &next)
        case .review:
            applyReview(grade: grade, now: now, to: &next)
        case .retired:
            // Retired cards are not scheduled; reviewing one is a no-op.
            break
        }
    }

    // MARK: - Learning steps (§7.2)

    private func applyLearning(grade: Grade, now: Date, to state: inout SchedulerState) {
        let steps = parameters.learningStepsMinutes
        let currentStep = state.learningStepIndex ?? 0

        switch grade {
        case .missedIt:
            // Back to the first step; re-solidify.
            state.learningStepIndex = 0
            state.dueDate = now.addingMinutes(steps.first ?? 1)
        case .gotIt:
            let nextStep = currentStep + 1
            if nextStep >= steps.count {
                graduate(now: now, to: &state)
            } else {
                state.learningStepIndex = nextStep
                state.dueDate = now.addingMinutes(steps[nextStep])
            }
        }
    }

    /// Leave learning and enter spaced review with the graduating interval.
    private func graduate(now: Date, to state: inout SchedulerState) {
        state.status = .review
        state.learningStepIndex = nil
        state.repetitions = 1
        state.intervalDays = cappedInterval(parameters.graduatingIntervalDays)
        state.dueDate = now.addingDays(state.intervalDays)
        if state.easeFactor == 0 { state.easeFactor = parameters.startingEase }
    }

    // MARK: - Spaced review (SM-2, §7.1 / §7.3)

    private func applyReview(grade: Grade, now: Date, to state: inout SchedulerState) {
        switch grade {
        case .missedIt:
            // Lapse: count it, gently drop ease (with floor), and send the card
            // BACK to learning steps rather than merely shrinking the interval.
            state.lapses += 1
            state.easeFactor = max(
                parameters.minEaseFloor,
                state.easeFactor - parameters.easePenaltyOnLapse
            )
            state.repetitions = 0
            state.status = .learning
            state.learningStepIndex = 0
            state.intervalDays = 0
            state.dueDate = now.addingMinutes(parameters.learningStepsMinutes.first ?? 1)

        case .gotIt:
            // Small ease bonus (kept tiny to avoid runaway intervals).
            state.easeFactor = min(
                3.0,
                state.easeFactor + parameters.easeBonusOnSuccess
            )

            let newInterval: Double
            switch state.repetitions {
            case 0:
                // Shouldn't normally happen in review, but be safe.
                newInterval = parameters.graduatingIntervalDays
            case 1:
                newInterval = parameters.secondIntervalDays
            default:
                newInterval = state.intervalDays * state.easeFactor
            }

            state.repetitions += 1
            state.intervalDays = cappedInterval(newInterval)
            state.dueDate = now.addingDays(state.intervalDays)
        }
    }

    // MARK: - Soft repeat (parent "Getting there", §14.4)

    /// Re-show the card soon without advancing or penalizing it: the child is
    /// partway, so ease, repetitions and the lapse count are all kept intact.
    private func applySoftRepeat(now: Date, to state: inout SchedulerState) {
        switch state.status {
        case .new:
            // A first exposure that's only partial: hold at the first learning step.
            state.status = .learning
            state.learningStepIndex = 0
            state.dueDate = now.addingMinutes(parameters.learningStepsMinutes.first ?? 1)
        case .learning:
            // Re-show at the *current* step — neither advance nor reset it.
            let steps = parameters.learningStepsMinutes
            let step = state.learningStepIndex ?? 0
            let minutes = step < steps.count ? steps[step] : (steps.last ?? 1)
            state.dueDate = now.addingMinutes(minutes)
        case .review:
            // Keep accumulated progress; just bring it back for a re-check soon.
            state.intervalDays = cappedInterval(parameters.graduatingIntervalDays)
            state.dueDate = now.addingDays(state.intervalDays)
        case .retired:
            break
        }
    }

    // MARK: - Helpers

    private func cappedInterval(_ days: Double) -> Double {
        min(days, parameters.maxIntervalDays)
    }
}

// MARK: - Date math (calendar-free, deterministic for tests)

extension Date {
    func addingMinutes(_ minutes: Double) -> Date {
        addingTimeInterval(minutes * 60)
    }
    func addingDays(_ days: Double) -> Date {
        addingTimeInterval(days * 24 * 60 * 60)
    }
}
