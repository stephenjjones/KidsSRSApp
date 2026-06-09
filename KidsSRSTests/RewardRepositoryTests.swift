import XCTest
import CoreData
import KidsSRSCore
@testable import KidsSRS

/// Tests for `RewardRepository` (Spec §9.3): deterministic unlocks persisted per
/// child, no double-unlock, and survival across reload.
final class RewardRepositoryTests: XCTestCase {

    /// A small deterministic ladder (1 / 2 sessions) for predictable assertions.
    private let star = RewardItem(id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!,
                                  name: "Star", symbol: "star.fill")
    private let fox = RewardItem(id: UUID(uuidString: "AAAA0000-0000-0000-0000-000000000002")!,
                                 name: "Fox", symbol: "pawprint.fill")
    private lazy var engine = RewardEngine(milestones: [
        RewardMilestone(id: UUID(uuidString: "BBBB0000-0000-0000-0000-000000000001")!,
                        requiredSessions: 1, item: star),
        RewardMilestone(id: UUID(uuidString: "BBBB0000-0000-0000-0000-000000000002")!,
                        requiredSessions: 2, item: fox),
    ])

    private func makeRepositories()
        -> (rewards: RewardRepository, children: ChildRepository, context: NSManagedObjectContext) {
        let context = PersistenceController(inMemory: true).container.viewContext
        return (RewardRepository(context: context, engine: engine),
                ChildRepository(context: context),
                context)
    }

    func testNoProgressForUnstudiedChild() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")

        let summary = try r.rewards.summary(forChild: child.id)
        XCTAssertEqual(summary.sessionsCompleted, 0)
        XCTAssertTrue(summary.unlockedItems.isEmpty)
        XCTAssertEqual(summary.nextMilestone?.item, star)
        XCTAssertEqual(summary.sessionsUntilNext, 1)
    }

    func testFirstSessionUnlocksFirstMilestone() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")

        let summary = try r.rewards.recordCompletedSession(forChild: child.id)
        XCTAssertEqual(summary.sessionsCompleted, 1)
        XCTAssertEqual(summary.newlyUnlocked, [star])
        XCTAssertEqual(summary.unlockedItems, [star])
        XCTAssertEqual(summary.nextMilestone?.item, fox)
    }

    func testSecondSessionUnlocksSecondAndThenNothingNew() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")

        _ = try r.rewards.recordCompletedSession(forChild: child.id) // → star
        let second = try r.rewards.recordCompletedSession(forChild: child.id) // → fox
        XCTAssertEqual(second.newlyUnlocked, [fox])
        XCTAssertEqual(second.unlockedItems, [star, fox])
        XCTAssertNil(second.nextMilestone, "All milestones unlocked")
        XCTAssertEqual(second.progressToNext, 1, accuracy: 0.0001)

        // A further session unlocks nothing new (idempotent past the ladder).
        let third = try r.rewards.recordCompletedSession(forChild: child.id)
        XCTAssertEqual(third.sessionsCompleted, 3)
        XCTAssertTrue(third.newlyUnlocked.isEmpty)
        XCTAssertEqual(third.unlockedItems, [star, fox])
    }

    func testProgressPersistsAcrossReload() throws {
        let r = makeRepositories()
        let child = try r.children.createChild(name: "Mia")
        _ = try r.rewards.recordCompletedSession(forChild: child.id)

        // A fresh repository on the same store sees the persisted progress.
        let reloaded = RewardRepository(context: r.context, engine: engine)
        let summary = try reloaded.summary(forChild: child.id)
        XCTAssertEqual(summary.sessionsCompleted, 1)
        XCTAssertEqual(summary.unlockedItems, [star])
        XCTAssertTrue(summary.newlyUnlocked.isEmpty, "Read-only summary never reports new unlocks")
    }

    func testRecordThrowsForMissingChild() {
        let r = makeRepositories()
        XCTAssertThrowsError(try r.rewards.recordCompletedSession(forChild: UUID()))
    }
}
