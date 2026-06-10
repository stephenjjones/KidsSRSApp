import XCTest
import CoreData
@testable import KidsSRS

/// Tests for `CardStateMergePolicy` (Spec §10.3): the newest-`lastReviewedAt`
/// review must win a conflict, so a completed review is never lost across
/// devices. Covers the pure decision plus real cross-context save conflicts on a
/// file-backed store (the `/dev/null` in-memory store can't model two contexts
/// racing on the same persisted row).
final class CardStateMergePolicyTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var t1: Date { t0.addingTimeInterval(10) }
    private var t2: Date { t0.addingTimeInterval(20) }

    // MARK: Pure decision

    func testPrefersPersistedOnlyWhenStrictlyNewer() {
        // Store newer → keep store.
        XCTAssertTrue(CardStateMergePolicy.prefersPersisted(
            sourceLastReviewedAt: t1, persistedLastReviewedAt: t2))
        // Source newer → keep source.
        XCTAssertFalse(CardStateMergePolicy.prefersPersisted(
            sourceLastReviewedAt: t2, persistedLastReviewedAt: t1))
        // Equal → keep source (not strictly newer).
        XCTAssertFalse(CardStateMergePolicy.prefersPersisted(
            sourceLastReviewedAt: t1, persistedLastReviewedAt: t1))
        // A real review beats a missing timestamp.
        XCTAssertTrue(CardStateMergePolicy.prefersPersisted(
            sourceLastReviewedAt: nil, persistedLastReviewedAt: t0))
        XCTAssertFalse(CardStateMergePolicy.prefersPersisted(
            sourceLastReviewedAt: t0, persistedLastReviewedAt: nil))
    }

    // MARK: Integration — real save conflict

    func testOlderReviewDoesNotClobberNewer() throws {
        let h = try Harness()
        let id = try h.insertCardState(lastReviewedAt: t0, dueDate: h.date(0), status: "review")

        // c2 reads the t0 snapshot, then c1 writes a NEWER review (t2).
        let obj2 = try h.c2.existingObject(with: id)
        try h.edit(h.c1, id: id, lastReviewedAt: t2, dueDate: h.date(2))

        // c2 now saves an OLDER review (t1) from its stale snapshot → conflict.
        obj2.setValue(t1, forKey: "lastReviewedAt")
        obj2.setValue(h.date(1), forKey: "dueDate")
        try h.c2.save()

        // The newer review (t2) and its due date survive.
        let stored = try h.readFresh(id: id)
        XCTAssertEqual(stored.lastReviewedAt, t2)
        XCTAssertEqual(stored.dueDate, h.date(2))
    }

    func testNewerReviewWinsConflict() throws {
        let h = try Harness()
        let id = try h.insertCardState(lastReviewedAt: t0, dueDate: h.date(0), status: "review")

        let obj2 = try h.c2.existingObject(with: id)
        // c1 writes an OLDER review (t1); c2 then saves a NEWER one (t2).
        try h.edit(h.c1, id: id, lastReviewedAt: t1, dueDate: h.date(1))

        obj2.setValue(t2, forKey: "lastReviewedAt")
        obj2.setValue(h.date(2), forKey: "dueDate")
        try h.c2.save()

        let stored = try h.readFresh(id: id)
        XCTAssertEqual(stored.lastReviewedAt, t2)
        XCTAssertEqual(stored.dueDate, h.date(2))
    }

    func testNonCardStateEntityFallsBackToPropertyTrump() throws {
        let h = try Harness()
        let id = try h.insertTag(name: "A")

        let obj2 = try h.c2.existingObject(with: id)
        // c1 writes "B" to the store; c2 then saves "C" from its stale snapshot.
        let obj1 = try h.c1.existingObject(with: id)
        obj1.setValue("B", forKey: "name"); try h.c1.save()
        obj2.setValue("C", forKey: "name"); try h.c2.save()

        // Tag isn't CardState → the base property-object-trump policy applies and
        // the in-memory writer (c2) wins. The custom CardState rule must not leak
        // its newest-`lastReviewedAt` logic onto other entities.
        XCTAssertEqual(try h.readName(id: id), "C")
    }

    // MARK: - Harness: two contexts over one file-backed store

    private struct StoredState {
        var lastReviewedAt: Date?
        var dueDate: Date?
    }

    private final class Harness {
        let coordinator: NSPersistentStoreCoordinator
        let storeURL: URL
        let c1: NSManagedObjectContext
        let c2: NSManagedObjectContext
        private let base = Date(timeIntervalSince1970: 1_700_000_000)

        init() throws {
            // Reuse the app's shared model (avoids re-loading "Model").
            let model = PersistenceController(inMemory: true).container.managedObjectModel
            coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("\(UUID().uuidString).sqlite")
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                                               configurationName: nil,
                                               at: storeURL, options: nil)
            c1 = Harness.makeContext(coordinator)
            c2 = Harness.makeContext(coordinator)
        }

        deinit {
            if let store = coordinator.persistentStores.first {
                try? coordinator.remove(store)
            }
            try? FileManager.default.removeItem(at: storeURL)
        }

        private static func makeContext(_ coordinator: NSPersistentStoreCoordinator)
            -> NSManagedObjectContext {
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            context.mergePolicy = CardStateMergePolicy()
            return context
        }

        func date(_ offset: TimeInterval) -> Date { base.addingTimeInterval(offset * 100) }

        /// Insert a CardState in c1, save, and return its permanent object id.
        func insertCardState(lastReviewedAt: Date, dueDate: Date, status: String) throws
            -> NSManagedObjectID {
            let state = NSEntityDescription.insertNewObject(forEntityName: "CardState", into: c1)
            state.setValue(lastReviewedAt, forKey: "lastReviewedAt")
            state.setValue(dueDate, forKey: "dueDate")
            state.setValue(status, forKey: "status")
            try c1.save()
            return state.objectID
        }

        func edit(_ context: NSManagedObjectContext, id: NSManagedObjectID,
                  lastReviewedAt: Date, dueDate: Date) throws {
            let obj = try context.existingObject(with: id)
            obj.setValue(lastReviewedAt, forKey: "lastReviewedAt")
            obj.setValue(dueDate, forKey: "dueDate")
            try context.save()
        }

        /// Insert a non-CardState entity (Tag) in c1, save, return its object id.
        func insertTag(name: String) throws -> NSManagedObjectID {
            let tag = NSEntityDescription.insertNewObject(forEntityName: "Tag", into: c1)
            tag.setValue(UUID(), forKey: "id")
            tag.setValue(name, forKey: "name")
            try c1.save()
            return tag.objectID
        }

        func readName(id: NSManagedObjectID) throws -> String? {
            let fresh = Harness.makeContext(coordinator)
            fresh.refreshAllObjects()
            let obj = try fresh.existingObject(with: id)
            fresh.refresh(obj, mergeChanges: false)
            return obj.value(forKey: "name") as? String
        }

        /// Read the row from a brand-new context so nothing is served from cache.
        func readFresh(id: NSManagedObjectID) throws -> StoredState {
            let fresh = Harness.makeContext(coordinator)
            fresh.refreshAllObjects()
            let obj = try fresh.existingObject(with: id)
            fresh.refresh(obj, mergeChanges: false)
            return StoredState(lastReviewedAt: obj.value(forKey: "lastReviewedAt") as? Date,
                               dueDate: obj.value(forKey: "dueDate") as? Date)
        }
    }
}
