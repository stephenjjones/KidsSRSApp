import XCTest
@testable import KidsSRSCore

final class SchedulerTests: XCTestCase {

    private let scheduler = Scheduler(profile: .normal)
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func review(_ grade: Grade, _ prediction: Prediction = .knowIt, at date: Date) -> ReviewInput {
        ReviewInput(grade: grade, prediction: prediction, reviewedAt: date)
    }

    // MARK: - Learning steps (§7.2)

    func testNewCardEntersLearningStep0OnGotIt() {
        let s0 = SchedulerState.makeNew()
        let s1 = scheduler.apply(review(.gotIt, at: t0), to: s0)

        XCTAssertEqual(s1.status, .learning)
        // [1, 10] minutes → after first "Got it" we advance to step 1 (10 min).
        XCTAssertEqual(s1.learningStepIndex, 1)
        XCTAssertEqual(s1.dueDate, t0.addingMinutes(10))
        XCTAssertEqual(s1.lastReviewedAt, t0)
    }

    func testNewCardMissedStaysAtStep0() {
        let s0 = SchedulerState.makeNew()
        let s1 = scheduler.apply(review(.missedIt, .notSure, at: t0), to: s0)

        XCTAssertEqual(s1.status, .learning)
        XCTAssertEqual(s1.learningStepIndex, 0)
        XCTAssertEqual(s1.dueDate, t0.addingMinutes(1))
    }

    func testGraduatesAfterLastLearningStep() {
        var s = SchedulerState.makeNew()
        s = scheduler.apply(review(.gotIt, at: t0), to: s)                 // → step 1
        s = scheduler.apply(review(.gotIt, at: t0.addingMinutes(10)), to: s) // → graduate

        XCTAssertEqual(s.status, .review)
        XCTAssertNil(s.learningStepIndex)
        XCTAssertEqual(s.repetitions, 1)
        XCTAssertEqual(s.intervalDays, 1, accuracy: 0.0001)            // graduating interval
        XCTAssertEqual(s.dueDate, t0.addingMinutes(10).addingDays(1))
    }

    func testLapseInLearningResetsToStep0() {
        var s = SchedulerState.makeNew()
        s = scheduler.apply(review(.gotIt, at: t0), to: s)              // step 1
        s = scheduler.apply(review(.missedIt, .knowIt, at: t0.addingMinutes(5)), to: s)

        XCTAssertEqual(s.status, .learning)
        XCTAssertEqual(s.learningStepIndex, 0)
    }

    // MARK: - Spaced review intervals (§7.1 / §7.3)

    private func graduatedCard() -> SchedulerState {
        var s = SchedulerState.makeNew()
        s = scheduler.apply(review(.gotIt, at: t0), to: s)
        s = scheduler.apply(review(.gotIt, at: t0.addingMinutes(10)), to: s)
        return s
    }

    func testSecondReviewUsesSecondInterval() {
        var s = graduatedCard() // rep 1, interval 1d
        let reviewDay = s.dueDate
        s = scheduler.apply(review(.gotIt, at: reviewDay), to: s)

        XCTAssertEqual(s.repetitions, 2)
        XCTAssertEqual(s.intervalDays, 6, accuracy: 0.0001)  // second interval
    }

    func testThirdReviewMultipliesByEase() {
        var s = graduatedCard()
        s = scheduler.apply(review(.gotIt, at: s.dueDate), to: s)  // interval 6
        let easeBefore = s.easeFactor
        s = scheduler.apply(review(.gotIt, at: s.dueDate), to: s)  // 6 * ease

        XCTAssertEqual(s.repetitions, 3)
        XCTAssertEqual(s.intervalDays, 6 * easeBefore, accuracy: 0.0001)
    }

    func testIntervalIsCappedAtMax() {
        let scheduler = Scheduler(parameters: .defaults(for: .normal)) // max 60
        var s = SchedulerState(
            status: .review, easeFactor: 2.3, intervalDays: 40,
            repetitions: 5, dueDate: t0
        )
        s = scheduler.apply(review(.gotIt, at: t0), to: s) // 40 * 2.3 = 92 → cap 60
        XCTAssertEqual(s.intervalDays, 60, accuracy: 0.0001)
    }

    // MARK: - Lapse behavior in review (§7.1)

    func testLapseInReviewSendsBackToLearningAndDropsEase() {
        var s = graduatedCard()
        s = scheduler.apply(review(.gotIt, at: s.dueDate), to: s) // build up a bit
        let easeBefore = s.easeFactor

        s = scheduler.apply(review(.missedIt, .knowIt, at: s.dueDate), to: s)

        XCTAssertEqual(s.status, .learning, "lapse must re-enter learning steps")
        XCTAssertEqual(s.learningStepIndex, 0)
        XCTAssertEqual(s.lapses, 1)
        XCTAssertEqual(s.repetitions, 0)
        XCTAssertEqual(s.easeFactor, easeBefore - 0.12, accuracy: 0.0001) // normal penalty
    }

    func testEaseNeverDropsBelowFloor() {
        let scheduler = Scheduler(parameters: .defaults(for: .normal)) // floor 1.6
        var s = SchedulerState(status: .review, easeFactor: 1.65, intervalDays: 10,
                               repetitions: 3, dueDate: t0)
        // Two lapses of 0.12 would mathematically reach 1.41; floor must hold at 1.6.
        s = scheduler.apply(review(.missedIt, at: t0), to: s)
        s.status = .review // force back to review to lapse again for the test
        s = scheduler.apply(review(.missedIt, at: t0), to: s)
        XCTAssertGreaterThanOrEqual(s.easeFactor, 1.6)
    }

    // MARK: - Metacognition flag is flag-only (§6.4)

    func testConfidenceFlagRecordedButDoesNotChangeSchedule() {
        let s0 = graduatedCard()

        let overConfident = scheduler.apply(review(.missedIt, .knowIt, at: s0.dueDate), to: s0)
        XCTAssertEqual(overConfident.lastConfidenceFlag, .overConfident)

        // Same review with a different *prediction* must yield identical scheduling.
        let alsoMissed = scheduler.apply(review(.missedIt, .notSure, at: s0.dueDate), to: s0)
        XCTAssertEqual(alsoMissed.lastConfidenceFlag, .calibrated)

        XCTAssertEqual(overConfident.intervalDays, alsoMissed.intervalDays)
        XCTAssertEqual(overConfident.dueDate, alsoMissed.dueDate)
        XCTAssertEqual(overConfident.easeFactor, alsoMissed.easeFactor)
        XCTAssertEqual(overConfident.status, alsoMissed.status)
    }

    func testUnderConfidentFlag() {
        let s0 = graduatedCard()
        let s1 = scheduler.apply(review(.gotIt, .notSure, at: s0.dueDate), to: s0)
        XCTAssertEqual(s1.lastConfidenceFlag, .underConfident)
    }

    // MARK: - Parameter presets (§7.3)

    func testPacingProfileDefaults() {
        XCTAssertEqual(SchedulerParameters.defaults(for: .gentle).newCardsPerDay, 3)
        XCTAssertEqual(SchedulerParameters.defaults(for: .normal).newCardsPerDay, 5)
        XCTAssertEqual(SchedulerParameters.defaults(for: .fast).newCardsPerDay, 8)
        XCTAssertEqual(SchedulerParameters.defaults(for: .gentle).maxIntervalDays, 30)
        XCTAssertEqual(SchedulerParameters.defaults(for: .normal).maxIntervalDays, 60)
    }

    // MARK: - Parent 3-level grade (§14.4)

    private func parent(_ grade: ParentGrade, at date: Date) -> ParentReviewInput {
        ParentReviewInput(grade: grade, reviewedAt: date)
    }

    func testParentKnowsItMatchesGotItScheduling() {
        let s0 = SchedulerState.makeNew()
        let viaParent = scheduler.apply(parent(.knowsIt, at: t0), to: s0)
        let viaKid = scheduler.apply(review(.gotIt, at: t0), to: s0)

        XCTAssertEqual(viaParent.status, viaKid.status)
        XCTAssertEqual(viaParent.learningStepIndex, viaKid.learningStepIndex)
        XCTAssertEqual(viaParent.dueDate, viaKid.dueDate)
    }

    func testParentDoesntKnowItLapsesLikeMissedItInReview() {
        let s0 = graduatedCard() // review, ease 2.3, lapses 0
        let s1 = scheduler.apply(parent(.doesntKnowIt, at: s0.dueDate), to: s0)

        XCTAssertEqual(s1.status, .learning)
        XCTAssertEqual(s1.learningStepIndex, 0)
        XCTAssertEqual(s1.lapses, 1)
        XCTAssertEqual(s1.easeFactor, s0.easeFactor - 0.12, accuracy: 0.0001) // normal penalty
    }

    func testParentGettingThereOnNewEntersLearningWithoutLapse() {
        let s0 = SchedulerState.makeNew()
        let s1 = scheduler.apply(parent(.gettingThere, at: t0), to: s0)

        XCTAssertEqual(s1.status, .learning)
        XCTAssertEqual(s1.learningStepIndex, 0)
        XCTAssertEqual(s1.dueDate, t0.addingMinutes(1)) // first learning step
        XCTAssertEqual(s1.lapses, 0, "getting there is not a lapse")
    }

    func testParentGettingThereHoldsCurrentLearningStep() {
        var s = SchedulerState.makeNew()
        s = scheduler.apply(review(.gotIt, at: t0), to: s) // → learning step 1 (10 min)
        XCTAssertEqual(s.learningStepIndex, 1)

        let held = scheduler.apply(parent(.gettingThere, at: t0.addingMinutes(10)), to: s)

        XCTAssertEqual(held.status, .learning)
        XCTAssertEqual(held.learningStepIndex, 1, "soft repeat must neither advance nor reset the step")
        XCTAssertEqual(held.dueDate, t0.addingMinutes(10).addingMinutes(10))
    }

    func testParentGettingThereInReviewKeepsProgressButReshowsSoon() {
        var s = graduatedCard()
        s = scheduler.apply(review(.gotIt, at: s.dueDate), to: s) // rep 2, interval 6
        let easeBefore = s.easeFactor
        let repsBefore = s.repetitions
        let lapsesBefore = s.lapses

        let now = s.dueDate
        let soft = scheduler.apply(parent(.gettingThere, at: now), to: s)

        XCTAssertEqual(soft.status, .review, "getting there must not lapse a review card")
        XCTAssertEqual(soft.easeFactor, easeBefore, accuracy: 0.0001)
        XCTAssertEqual(soft.repetitions, repsBefore)
        XCTAssertEqual(soft.lapses, lapsesBefore)
        XCTAssertEqual(soft.intervalDays, 1, accuracy: 0.0001) // graduating interval → re-check soon
        XCTAssertEqual(soft.dueDate, now.addingDays(1))
    }

    func testParentGradeLeavesConfidenceFlagUntouched() {
        let s0 = graduatedCard() // carries a .calibrated flag from the kid's gotIt reviews
        XCTAssertEqual(s0.lastConfidenceFlag, .calibrated)

        let s1 = scheduler.apply(parent(.gettingThere, at: s0.dueDate), to: s0)

        XCTAssertEqual(s1.lastConfidenceFlag, s0.lastConfidenceFlag,
                       "parent grading has no prediction and must not invent or clear the metacognition flag")
        XCTAssertEqual(s1.lastReviewedAt, s0.dueDate)
    }
}
