import XCTest
@testable import KidsSRSCore

final class SessionPlannerTests: XCTestCase {

    private let planner = SessionPlanner()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(_ id: Int, status: CardStatus, due: Date) -> SessionPlanner.Item<Int> {
        SessionPlanner.Item(id: id, state: SchedulerState(status: status, dueDate: due))
    }

    func testReviewsComeBeforeNewCards() {
        let candidates = [
            item(1, status: .new, due: .distantFuture),
            item(2, status: .review, due: now.addingDays(-1)), // due
        ]
        let plan = planner.plan(
            candidates: candidates,
            limits: .init(dailyReviewLimit: 10, newCardsPerDay: 10),
            now: now
        )
        XCTAssertEqual(plan, [2, 1])
    }

    func testReviewCapIsRespected() {
        let candidates = (0..<20).map { item($0, status: .review, due: now.addingDays(-1)) }
        let plan = planner.plan(
            candidates: candidates,
            limits: .init(dailyReviewLimit: 5, newCardsPerDay: 0),
            now: now
        )
        XCTAssertEqual(plan.count, 5)
    }

    func testNewCardCapIsRespectedIndependently() {
        let reviews = (0..<3).map { item($0, status: .review, due: now.addingDays(-1)) }
        let news = (100..<110).map { item($0, status: .new, due: .distantFuture) }
        let plan = planner.plan(
            candidates: reviews + news,
            limits: .init(dailyReviewLimit: 10, newCardsPerDay: 4),
            now: now
        )
        XCTAssertEqual(plan.count, 3 + 4)
        XCTAssertEqual(Array(plan.suffix(4)), [100, 101, 102, 103])
    }

    func testNotYetDueReviewsAreExcluded() {
        let candidates = [
            item(1, status: .review, due: now.addingDays(2)),   // future, excluded
            item(2, status: .review, due: now.addingDays(-1)),  // due
        ]
        let plan = planner.plan(
            candidates: candidates,
            limits: .init(dailyReviewLimit: 10, newCardsPerDay: 10),
            now: now
        )
        XCTAssertEqual(plan, [2])
    }

    func testDueReviewsOrderedByDueDate() {
        let candidates = [
            item(1, status: .review, due: now.addingDays(-1)),
            item(2, status: .learning, due: now.addingDays(-3)),
            item(3, status: .review, due: now.addingDays(-2)),
        ]
        let plan = planner.plan(
            candidates: candidates,
            limits: .init(dailyReviewLimit: 10, newCardsPerDay: 0),
            now: now
        )
        XCTAssertEqual(plan, [2, 3, 1]) // earliest due first
    }
}
