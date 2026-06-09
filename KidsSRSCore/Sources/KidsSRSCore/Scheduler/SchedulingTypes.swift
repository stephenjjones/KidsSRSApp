import Foundation

// MARK: - Grading

/// The child's self-rating after the answer is revealed.
/// Spec §6.3: Anki's 4-grade scale is reduced to two kid-friendly buttons.
public enum Grade: String, Codable, Sendable, CaseIterable {
    case gotIt
    case missedIt
}

/// The child's confidence prediction committed *before* the reveal.
/// Spec §6.3 "predict-then-verify".
public enum Prediction: String, Codable, Sendable, CaseIterable {
    case knowIt   // "I think I know it"
    case notSure  // "Not sure"
}

/// The parent's 3-level mastery rating for a child on a card.
///
/// Spec §14.4: used in the **parent-led Song Review and Game modes**, where an
/// adult judges the child rather than the child self-grading. It maps to the
/// same SM-2 state machine as `Grade` (see `Scheduler.apply(_:to:)` for a
/// `ParentReviewInput`): `knowsIt` advances like "Got it", `doesntKnowIt` lapses
/// like "Missed it", and `gettingThere` is a *soft repeat* that re-shows the
/// card soon while preserving the child's accumulated progress.
public enum ParentGrade: String, Codable, Sendable, CaseIterable {
    case doesntKnowIt
    case gettingThere
    case knowsIt
}

/// Calibration of a prediction against the eventual self-rating.
/// Spec §6.4: this is **flag-only** — it never alters the schedule.
public enum ConfidenceFlag: String, Codable, Sendable {
    case calibrated      // knowIt+gotIt  OR  notSure+missedIt
    case overConfident   // knowIt + missedIt  → coach gently, surface to parent
    case underConfident  // notSure + gotIt    → "you knew more than you thought!"

    public init(prediction: Prediction, grade: Grade) {
        switch (prediction, grade) {
        case (.knowIt, .gotIt), (.notSure, .missedIt): self = .calibrated
        case (.knowIt, .missedIt): self = .overConfident
        case (.notSure, .gotIt): self = .underConfident
        }
    }
}

// MARK: - Card lifecycle

/// Where a card sits in its lifecycle. Spec §5 `CardState.status`.
public enum CardStatus: String, Codable, Sendable {
    case new       // never studied
    case learning  // inside same-session learning steps (§7.2)
    case review    // graduated to spaced SM-2 review
    case retired   // removed from a catalog deck; kept for history, not scheduled
}

// MARK: - Parameters

/// Parent-facing pacing preset that expands to a coherent parameter set.
/// Spec §7.3.
public enum PacingProfile: String, Codable, Sendable, CaseIterable {
    case gentle
    case normal
    case fast
}

/// The full kid-tuned SM-2 parameter set. Spec §7.3 table.
///
/// These intentionally deviate from adult Anki defaults to bias toward frequent
/// success: lower starting ease, a *higher* ease floor (no "ease hell"), a
/// gentler lapse penalty, and a capped maximum interval.
public struct SchedulerParameters: Codable, Sendable, Equatable {
    /// Ease factor assigned when a card first graduates to review.
    public var startingEase: Double
    /// Hard floor for ease — protects against a single bad week trapping a card.
    public var minEaseFloor: Double
    /// Amount ease is reduced on a lapse ("Missed it" in review).
    public var easePenaltyOnLapse: Double
    /// Small bonus added to ease on "Got it" (kept tiny to avoid runaway gaps).
    public var easeBonusOnSuccess: Double
    /// Interval (days) granted the first time a card graduates from learning.
    public var graduatingIntervalDays: Double
    /// Interval (days) granted on the *second* successful review.
    public var secondIntervalDays: Double
    /// Ceiling on any computed interval (days). Spec: keeps content familiar.
    public var maxIntervalDays: Double
    /// Same-session learning steps, in minutes, before a card enters SM-2.
    public var learningStepsMinutes: [Double]
    /// Cap on brand-new cards introduced per day (parent-adjustable).
    public var newCardsPerDay: Int

    public init(
        startingEase: Double,
        minEaseFloor: Double,
        easePenaltyOnLapse: Double,
        easeBonusOnSuccess: Double,
        graduatingIntervalDays: Double,
        secondIntervalDays: Double,
        maxIntervalDays: Double,
        learningStepsMinutes: [Double],
        newCardsPerDay: Int
    ) {
        self.startingEase = startingEase
        self.minEaseFloor = minEaseFloor
        self.easePenaltyOnLapse = easePenaltyOnLapse
        self.easeBonusOnSuccess = easeBonusOnSuccess
        self.graduatingIntervalDays = graduatingIntervalDays
        self.secondIntervalDays = secondIntervalDays
        self.maxIntervalDays = maxIntervalDays
        self.learningStepsMinutes = learningStepsMinutes
        self.newCardsPerDay = newCardsPerDay
    }

    /// The recommended defaults from Spec §7.3, expanded per pacing preset.
    public static func defaults(for profile: PacingProfile) -> SchedulerParameters {
        switch profile {
        case .gentle:
            return SchedulerParameters(
                startingEase: 2.3,
                minEaseFloor: 1.6,
                easePenaltyOnLapse: 0.10,   // gentlest
                easeBonusOnSuccess: 0.0,
                graduatingIntervalDays: 1,
                secondIntervalDays: 6,
                maxIntervalDays: 30,
                learningStepsMinutes: [1, 10],
                newCardsPerDay: 3
            )
        case .normal:
            return SchedulerParameters(
                startingEase: 2.3,
                minEaseFloor: 1.6,
                easePenaltyOnLapse: 0.12,   // spec table
                easeBonusOnSuccess: 0.0,
                graduatingIntervalDays: 1,
                secondIntervalDays: 6,
                maxIntervalDays: 60,
                learningStepsMinutes: [1, 10],
                newCardsPerDay: 5
            )
        case .fast:
            return SchedulerParameters(
                startingEase: 2.3,
                minEaseFloor: 1.6,
                easePenaltyOnLapse: 0.20,   // standard
                easeBonusOnSuccess: 0.0,
                graduatingIntervalDays: 1,
                secondIntervalDays: 6,
                maxIntervalDays: 60,
                learningStepsMinutes: [1, 10],
                newCardsPerDay: 8
            )
        }
    }
}

// MARK: - Scheduling state

/// The pure, persistence-agnostic scheduling state for a single (child × card).
///
/// This mirrors the storable fields of `CardState` (Spec §5) but carries **no**
/// CoreData / CloudKit dependency, so the scheduler can be unit-tested in
/// isolation. The app layer maps this to/from its `NSManagedObject`.
public struct SchedulerState: Codable, Sendable, Equatable {
    public var status: CardStatus
    public var easeFactor: Double
    public var intervalDays: Double
    public var repetitions: Int
    public var lapses: Int
    /// Index into `SchedulerParameters.learningStepsMinutes`; nil once graduated.
    public var learningStepIndex: Int?
    public var dueDate: Date
    public var lastReviewedAt: Date?
    /// Metacognition flag from the most recent review (Spec §6.4). Flag-only.
    public var lastConfidenceFlag: ConfidenceFlag?

    public init(
        status: CardStatus = .new,
        easeFactor: Double = 2.3,
        intervalDays: Double = 0,
        repetitions: Int = 0,
        lapses: Int = 0,
        learningStepIndex: Int? = nil,
        dueDate: Date = .distantPast,
        lastReviewedAt: Date? = nil,
        lastConfidenceFlag: ConfidenceFlag? = nil
    ) {
        self.status = status
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.learningStepIndex = learningStepIndex
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
        self.lastConfidenceFlag = lastConfidenceFlag
    }

    /// A fresh, never-studied card.
    public static func makeNew(easeFactor: Double = 2.3) -> SchedulerState {
        SchedulerState(status: .new, easeFactor: easeFactor)
    }
}

/// A single review event handed to the scheduler.
public struct ReviewInput: Sendable, Equatable {
    public var grade: Grade
    public var prediction: Prediction
    /// The instant the review happened (injected for deterministic testing).
    public var reviewedAt: Date

    public init(grade: Grade, prediction: Prediction, reviewedAt: Date) {
        self.grade = grade
        self.prediction = prediction
        self.reviewedAt = reviewedAt
    }
}

/// A **parent-graded** review event (Spec §14.3). Unlike `ReviewInput` it carries
/// no confidence `Prediction` — the adult is rating the child, not running
/// predict-then-verify — so applying it never sets a metacognition flag.
public struct ParentReviewInput: Sendable, Equatable {
    public var grade: ParentGrade
    /// The instant the review happened (injected for deterministic testing).
    public var reviewedAt: Date

    public init(grade: ParentGrade, reviewedAt: Date) {
        self.grade = grade
        self.reviewedAt = reviewedAt
    }
}
