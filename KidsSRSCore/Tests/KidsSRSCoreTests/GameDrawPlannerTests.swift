import XCTest
@testable import KidsSRSCore

final class GameDrawPlannerTests: XCTestCase {

    private let planner = GameDrawPlanner()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(_ id: Int, _ status: CardStatus,
                      due: Date, lapses: Int = 0) -> SessionPlanner.Item<Int> {
        SessionPlanner.Item(id: id,
                            state: SchedulerState(status: status, lapses: lapses, dueDate: due))
    }

    func testDueOutranksNewWhichOutranksNotYetDue() {
        let candidates = [
            item(1, .review, due: now.addingDays(5)),   // not yet due → lowest tier
            item(2, .new,    due: .distantFuture),       // new → middle tier
            item(3, .review, due: now.addingDays(-1)),   // due → highest tier
        ]
        XCTAssertEqual(planner.ranked(candidates: candidates, now: now), [3, 2, 1])
    }

    func testRetiredCardsAreNeverDrawn() {
        let candidates = [
            item(1, .retired, due: now.addingDays(-10)),
            item(2, .new,     due: .distantFuture),
        ]
        XCTAssertEqual(planner.ranked(candidates: candidates, now: now), [2])
    }

    func testWithinTierMoreLapsesComeFirst() {
        let candidates = [
            item(1, .review, due: now.addingDays(-1), lapses: 1),
            item(2, .review, due: now.addingDays(-1), lapses: 4),
            item(3, .review, due: now.addingDays(-1), lapses: 0),
        ]
        XCTAssertEqual(planner.ranked(candidates: candidates, now: now), [2, 1, 3])
    }

    func testEarliestDueBreaksLapseTies() {
        let candidates = [
            item(1, .learning, due: now.addingDays(-1)),
            item(2, .learning, due: now.addingDays(-3)),
            item(3, .learning, due: now.addingDays(-2)),
        ]
        XCTAssertEqual(planner.ranked(candidates: candidates, now: now), [2, 3, 1])
    }

    func testEmptyCandidatesYieldEmpty() {
        XCTAssertTrue(planner.ranked(candidates: [SessionPlanner.Item<Int>](), now: now).isEmpty)
    }
}
