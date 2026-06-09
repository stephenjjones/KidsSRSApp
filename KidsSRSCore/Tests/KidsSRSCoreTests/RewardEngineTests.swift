import XCTest
@testable import KidsSRSCore

final class RewardEngineTests: XCTestCase {

    private func item(_ n: Int) -> RewardItem {
        RewardItem(id: UUID(), name: "Item \(n)", symbol: "star")
    }

    /// A small ladder at 1 / 3 / 7, deliberately constructed out of order to
    /// prove the engine sorts.
    private lazy var engine: RewardEngine = {
        RewardEngine(milestones: [
            RewardMilestone(id: UUID(), requiredSessions: 7, item: item(7)),
            RewardMilestone(id: UUID(), requiredSessions: 1, item: item(1)),
            RewardMilestone(id: UUID(), requiredSessions: 3, item: item(3)),
        ])
    }()

    func testNextMilestone() {
        XCTAssertEqual(engine.nextMilestone(completedSessions: 0)?.requiredSessions, 1)
        XCTAssertEqual(engine.nextMilestone(completedSessions: 1)?.requiredSessions, 3)
        XCTAssertEqual(engine.nextMilestone(completedSessions: 2)?.requiredSessions, 3)
        XCTAssertEqual(engine.nextMilestone(completedSessions: 3)?.requiredSessions, 7)
        XCTAssertNil(engine.nextMilestone(completedSessions: 7))
        XCTAssertNil(engine.nextMilestone(completedSessions: 99))
    }

    func testNewlyUnlockedCrossingThresholds() {
        XCTAssertEqual(engine.newlyUnlocked(previous: 0, now: 1).map(\.requiredSessions), [1])
        // Jumping 0 → 3 unlocks both the 1 and 3 milestones, in order.
        XCTAssertEqual(engine.newlyUnlocked(previous: 0, now: 3).map(\.requiredSessions), [1, 3])
        // No threshold crossed → nothing new (idempotent past a milestone).
        XCTAssertTrue(engine.newlyUnlocked(previous: 3, now: 4).isEmpty)
        XCTAssertTrue(engine.newlyUnlocked(previous: 7, now: 8).isEmpty)
    }

    func testUnlockedMilestones() {
        XCTAssertTrue(engine.unlockedMilestones(completedSessions: 0).isEmpty)
        XCTAssertEqual(engine.unlockedMilestones(completedSessions: 3).map(\.requiredSessions), [1, 3])
        XCTAssertEqual(engine.unlockedMilestones(completedSessions: 99).count, 3)
    }

    func testProgressToNext() {
        XCTAssertEqual(engine.progressToNext(completedSessions: 0), 0, accuracy: 0.0001) // 0→1
        XCTAssertEqual(engine.progressToNext(completedSessions: 1), 0, accuracy: 0.0001) // 1→3, just started
        XCTAssertEqual(engine.progressToNext(completedSessions: 2), 0.5, accuracy: 0.0001) // halfway 1→3
        XCTAssertEqual(engine.progressToNext(completedSessions: 7), 1, accuracy: 0.0001) // all unlocked
    }

    func testEvaluationIsDeterministic() {
        // Same inputs always produce the same outputs — no randomness (§9.3).
        for sessions in 0...10 {
            XCTAssertEqual(engine.unlockedMilestones(completedSessions: sessions).map(\.id),
                           engine.unlockedMilestones(completedSessions: sessions).map(\.id))
            XCTAssertEqual(engine.nextMilestone(completedSessions: sessions)?.id,
                           engine.nextMilestone(completedSessions: sessions)?.id)
        }
    }

    func testBundledCatalogIsAscendingWithStableIDs() {
        let requirements = RewardCatalog.milestones.map(\.requiredSessions)
        XCTAssertEqual(requirements, requirements.sorted())
        // All milestone and item IDs are unique (no accidental collisions).
        XCTAssertEqual(Set(RewardCatalog.milestones.map(\.id)).count, RewardCatalog.milestones.count)
        XCTAssertEqual(Set(RewardCatalog.milestones.map(\.item.id)).count, RewardCatalog.milestones.count)
    }

    func testCatalogItemLookupByID() {
        let item = RewardCatalog.milestones[0].item
        XCTAssertEqual(RewardCatalog.item(id: item.id), item)
        XCTAssertNil(RewardCatalog.item(id: UUID()))
    }
}
