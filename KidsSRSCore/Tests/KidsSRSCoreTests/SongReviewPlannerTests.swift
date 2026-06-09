import XCTest
@testable import KidsSRSCore

final class SongReviewPlannerTests: XCTestCase {

    private let planner = SongReviewPlanner()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(_ status: CardStatus, due: Date) -> SchedulerState {
        SchedulerState(status: status, dueDate: due)
    }

    func testIncludesDueAndNewButExcludesKnown() {
        let candidates = [
            // Due for one child (review, past due); new for the other.
            SongReviewPlanner.Candidate(id: 1, childStates: [state(.review, due: now.addingDays(-1)), nil]),
            // Known by the only selected child (scheduled far out).
            SongReviewPlanner.Candidate(id: 2, childStates: [state(.review, due: now.addingDays(5))]),
            // Never scored by anyone → new.
            SongReviewPlanner.Candidate(id: 3, childStates: [nil, nil]),
        ]
        XCTAssertEqual(planner.plan(candidates: candidates, now: now), [1, 3])
    }

    func testDueOrderedByEarliestThenNeedyCount() {
        let candidates = [
            SongReviewPlanner.Candidate(id: 1, childStates: [state(.review, due: now.addingDays(-1))]),
            SongReviewPlanner.Candidate(id: 2, childStates: [state(.learning, due: now.addingDays(-3))]),
            SongReviewPlanner.Candidate(id: 3, childStates: [state(.review, due: now.addingDays(-3)),
                                                             state(.review, due: now.addingDays(-3))]),
        ]
        // earliest (-3) first; among the two, id 3 has 2 needy kids → before id 2.
        XCTAssertEqual(planner.plan(candidates: candidates, now: now), [3, 2, 1])
    }

    func testNewSongsCappedByLimit() {
        let candidates = (0..<20).map { SongReviewPlanner.Candidate(id: $0, childStates: [nil]) }
        XCTAssertEqual(planner.plan(candidates: candidates, now: now, newLimit: 5).count, 5)
    }

    func testEmptyWhenNothingNeeded() {
        let candidates = [
            SongReviewPlanner.Candidate(id: 1, childStates: [state(.review, due: now.addingDays(10))]),
        ]
        XCTAssertTrue(planner.plan(candidates: candidates, now: now).isEmpty)
    }
}
