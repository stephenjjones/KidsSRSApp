import CoreData

/// Wraps `NSPersistentCloudKitContainer`. Spec §4.1 / §10.2 / §10.3.
///
/// - Offline-first: the store works fully offline; CloudKit syncs
///   opportunistically (Spec §10.1).
/// - Private-database sync (Spec §10.2): enabled by setting
///   `cloudKitContainerIdentifier`. Until a CloudKit container is provisioned it
///   stays `nil` and the app runs as a purely local store — so it builds, runs
///   and tests with no iCloud entitlement.
/// - Cross-device conflict safety (Spec §10.3): a custom `CardStateMergePolicy`
///   keeps the review with the newest `lastReviewedAt`, so a completed review is
///   never lost when two family devices sync.
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    /// In-memory variant for previews/tests.
    static var preview: PersistenceController = {
        PersistenceController(inMemory: true)
    }()

    /// CloudKit container identifier for private-database sync (Spec §10.2).
    ///
    /// Set ⇒ the on-disk store mirrors to the family's **private** CloudKit
    /// database, so data syncs across the family's devices (one Apple ID). Set to
    /// `nil` for purely local/offline operation (e.g. without the iCloud
    /// entitlement). History tracking, remote-change notifications and the
    /// `CardState` merge policy (§10.3) are already wired, so this identifier is
    /// the only switch.
    ///
    /// v1 uses `NSPersistentCloudKitContainer`'s single managed private zone.
    /// Per-child zones (§10.2) are **deliberately deferred to v2 sharing**: a
    /// single family Apple ID needs no per-child *isolation* (children are
    /// already separated logically by `childID`), and named private zones would
    /// require one persistent store per child — complexity with no v1 payoff.
    static let cloudKitContainerIdentifier: String? = "iCloud.com.kidssrs.app"

    let container: NSPersistentCloudKitContainer

    /// Non-nil if the persistent store failed to load (e.g. a migration that
    /// can't be inferred, or a corrupt/unreadable store). The app shows a
    /// graceful error screen instead of crashing (Spec §4 — production must
    /// handle failure, not `assertionFailure`).
    @Published private(set) var loadError: Error? = nil

    /// Observes CloudKit sync events and logs each setup/import/export outcome
    /// (Spec §10.1). Non-nil only when CloudKit mirroring is active. Its `.error`
    /// logging is what surfaces an export/import failure that is otherwise silent.
    private(set) var syncMonitor: CloudKitSyncMonitor?

    /// The Core Data model, loaded exactly once and shared across every
    /// container. Without this, each additional container (e.g. the in-memory
    /// `.preview` store plus any per-preview/per-test store) reloads "Model",
    /// producing multiple `NSManagedObjectModel` instances for the same entity
    /// classes — Core Data then logs "Failed to find a unique match for an
    /// NSEntityDescription to a managed object subclass" and `DeckMO`/`CardMO`
    /// can resolve to the wrong entity. One shared model keeps `+entity` unique.
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle(for: PersistenceController.self)
                .url(forResource: "Model", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            // Build invariant: the compiled model is always bundled. If it's
            // missing the app fundamentally cannot run (corrupt build), so this
            // is a precondition, not a recoverable runtime failure.
            preconditionFailure("Failed to load Core Data model 'Model' from the app bundle.")
        }
        return model
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Model",
                                                  managedObjectModel: Self.managedObjectModel)

        if inMemory {
            container.persistentStoreDescriptions.first?.url =
                URL(fileURLWithPath: "/dev/null")
        }

        // Enable history tracking + remote change notifications, both required
        // for CloudKit sync and our cross-device merge handling (Spec §10.3).
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber,
                                  forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber,
                                  forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // Private-database sync (Spec §10.2) — only when a container is
            // provisioned. While `cloudKitContainerIdentifier` is nil the store
            // stays local, so the app needs no iCloud entitlement to run/test.
            if !inMemory, let containerID = Self.cloudKitContainerIdentifier {
                description.cloudKitContainerOptions =
                    NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
            }
        }

        container.loadPersistentStores { _, error in
            self.applyStoreLoadResult(error)
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        // Spec §10.3: keep the review with the newest `lastReviewedAt` for
        // CardState; property-trump for everything else.
        container.viewContext.mergePolicy = CardStateMergePolicy()

        // Watch the CloudKit pipeline so a failing export/import is logged with
        // its error instead of stalling silently (Spec §10.1). Only meaningful
        // when mirroring is active.
        if !inMemory, Self.cloudKitContainerIdentifier != nil {
            syncMonitor = CloudKitSyncMonitor()
        }

        configureZones()
    }

    /// Per-child CloudKit record zones (Spec §10.2) — documented follow-up.
    ///
    /// `NSPersistentCloudKitContainer` mirrors each store into a single private
    /// zone it manages itself; true *one-zone-per-child* isolation requires a
    /// separate persistent store (and `NSPersistentCloudKitContainerOptions`)
    /// per child, routed by the active profile. That is a substantial change
    /// that only matters once a CloudKit container is provisioned, so it is left
    /// as a deliberate follow-up rather than stubbed in prematurely.
    private func configureZones() {
        // No-op until `cloudKitContainerIdentifier` is set and per-child stores
        // are introduced. The single-zone private-DB sync above is correct in
        // the meantime.
    }

    /// Record the outcome of loading the persistent store. Surfacing the error
    /// (rather than crashing) lets the app present a recovery screen (Spec §4).
    /// `internal` so it can be unit-tested. A future enhancement could attempt
    /// migration recovery here before giving up.
    func applyStoreLoadResult(_ error: Error?) {
        loadError = error
        if let error {
            NSLog("KidsSRS: Core Data store failed to load: %@", String(describing: error))
        }
    }
}
