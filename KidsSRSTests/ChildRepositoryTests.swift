import XCTest
import CoreData
import KidsSRSCore
@testable import KidsSRS

/// Unit tests for `ChildRepository` against a fresh in-memory store.
/// Each test gets its own controller so they're isolated.
final class ChildRepositoryTests: XCTestCase {

    private func makeRepository() -> ChildRepository {
        ChildRepository(persistence: PersistenceController(inMemory: true))
    }

    func testCreateChildPersistsWithSpecDefaults() throws {
        let repo = makeRepository()
        let created = try repo.createChild(name: "Mia")

        let children = try repo.fetchChildren()
        XCTAssertEqual(children.count, 1)
        let child = try XCTUnwrap(children.first)
        XCTAssertEqual(child.id, created.id)
        XCTAssertEqual(child.displayName, "Mia")
        // Spec §7.3 model defaults applied on insert.
        XCTAssertEqual(child.dailyNewCardLimit, 5)
        XCTAssertEqual(child.dailyReviewLimit, 40)
        XCTAssertEqual(child.pacingProfile, .normal)
        XCTAssertFalse(child.dyslexiaMode)
        XCTAssertFalse(child.readAloud)
        XCTAssertFalse(child.reduceMotion)
    }

    func testFetchChildrenSortedByNameCaseInsensitive() throws {
        let repo = makeRepository()
        _ = try repo.createChild(name: "leo")
        _ = try repo.createChild(name: "Ada")
        _ = try repo.createChild(name: "mia")

        XCTAssertEqual(try repo.fetchChildren().map(\.displayName), ["Ada", "leo", "mia"])
    }

    func testRenameChildPreservesIdentity() throws {
        let repo = makeRepository()
        let child = try repo.createChild(name: "Old")

        try repo.renameChild(id: child.id, name: "New")

        let children = try repo.fetchChildren()
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children.first?.id, child.id, "Rename must not reassign the child id")
        XCTAssertEqual(children.first?.displayName, "New")
    }

    func testUpdateChildPersistsAllSettingsAndKeepsId() throws {
        let repo = makeRepository()
        var child = try repo.createChild(name: "Mia")

        child.displayName = "Mia B."
        child.dailyNewCardLimit = 8
        child.dailyReviewLimit = 60
        child.pacingProfile = .fast
        child.dyslexiaMode = true
        child.readAloud = true
        child.reduceMotion = true
        child.reminderEnabled = true
        child.reminderHour = 17
        child.reminderMinute = 30
        try repo.updateChild(child)

        let stored = try XCTUnwrap(try repo.fetchChildren().first)
        XCTAssertEqual(stored.id, child.id, "Editing settings must not reassign the id")
        XCTAssertEqual(stored.displayName, "Mia B.")
        XCTAssertEqual(stored.dailyNewCardLimit, 8)
        XCTAssertEqual(stored.dailyReviewLimit, 60)
        XCTAssertEqual(stored.pacingProfile, .fast)
        XCTAssertTrue(stored.dyslexiaMode)
        XCTAssertTrue(stored.readAloud)
        XCTAssertTrue(stored.reduceMotion)
        XCTAssertTrue(stored.reminderEnabled)
        XCTAssertEqual(stored.reminderHour, 17)
        XCTAssertEqual(stored.reminderMinute, 30)
    }

    func testCreateChildDefaultsReminderOff() throws {
        let repo = makeRepository()
        let child = try repo.createChild(name: "Mia")
        XCTAssertFalse(child.reminderEnabled, "Reminders are off by default (Spec §10.4)")
        XCTAssertEqual(child.reminderHour, 16)
        XCTAssertEqual(child.reminderMinute, 0)
    }

    func testDeleteChild() throws {
        let repo = makeRepository()
        let a = try repo.createChild(name: "A")
        _ = try repo.createChild(name: "B")

        try repo.deleteChild(id: a.id)

        XCTAssertEqual(try repo.fetchChildren().map(\.displayName), ["B"])
    }

    func testMutatingMethodsThrowForMissingChild() {
        let repo = makeRepository()
        let missing = ChildSummary(id: UUID(), displayName: "x",
                                   dailyNewCardLimit: 5, dailyReviewLimit: 40,
                                   pacingProfile: .normal,
                                   dyslexiaMode: false, readAloud: false, reduceMotion: false)
        XCTAssertThrowsError(try repo.renameChild(id: missing.id, name: "y"))
        XCTAssertThrowsError(try repo.updateChild(missing))
        XCTAssertThrowsError(try repo.deleteChild(id: missing.id))
    }

    func testEquipRewardRoundTrips() throws {
        let repo = makeRepository()
        let child = try repo.createChild(name: "Mia")
        XCTAssertNil(child.equippedItemID)

        let itemID = RewardCatalog.milestones[0].item.id
        try repo.setEquippedReward(itemID: itemID, forChild: child.id)
        XCTAssertEqual(try repo.equippedReward(forChild: child.id), itemID)
        XCTAssertEqual(try repo.fetchChildren().first?.equippedItemID, itemID, "surfaces on ChildSummary")

        // Clearing returns to the default face.
        try repo.setEquippedReward(itemID: nil, forChild: child.id)
        XCTAssertNil(try repo.equippedReward(forChild: child.id))
        XCTAssertNil(try repo.fetchChildren().first?.equippedItemID)
    }
}
