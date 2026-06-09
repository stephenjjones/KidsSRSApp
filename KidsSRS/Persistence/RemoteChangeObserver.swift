import Foundation
import Combine
import CoreData

/// Reloads a view model when the persistent store imports remote (CloudKit)
/// changes (Spec §10.1/§10.2).
///
/// The §4.1 repositories hand the UI plain value types loaded once (via `.task`),
/// not live `@FetchRequest`s — so a card/child synced in from another device
/// lands in Core Data but doesn't refresh an already-open screen on its own. A
/// view model holds one of these wired to its `load()`. Sync arrives in bursts,
/// so notifications are debounced and delivered on the main actor.
@MainActor
final class RemoteChangeObserver {
    private var cancellable: AnyCancellable?

    init(center: NotificationCenter = .default,
         debounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(250),
         onChange: @escaping @MainActor () -> Void) {
        cancellable = center
            .publisher(for: .NSPersistentStoreRemoteChange)
            .debounce(for: debounce, scheduler: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated(onChange) }
    }
}
