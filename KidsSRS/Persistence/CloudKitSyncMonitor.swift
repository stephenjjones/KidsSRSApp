import Foundation
import CoreData
import Combine
import os

/// Observes `NSPersistentCloudKitContainer` sync activity and records the outcome
/// of every setup / import / export phase — including the underlying error when a
/// phase fails (Spec §10.1).
///
/// Why this exists: diagnosing a sync stall from *outside* the app is unreliable —
/// the unified log doesn't retain `info`/`debug` entries, and `NSPersistentCloud
/// KitContainer`'s detail is logged at those levels. So the app reports its own
/// pipeline health: each finished phase is logged at `.notice` (success) or
/// `.error` (failure) — both of which the unified log **does** persist — so a
/// failing export/import names its `CKError` in `log show` after the fact. The
/// latest per-phase result is also published for optional in-app surfacing
/// (e.g. a parent-zone "Sync status" row).
///
/// Not `@MainActor`: the notification fires on an internal Core Data queue. The
/// pipeline extracts a `Sendable` value on that queue, hops to main, and only
/// then mutates `@Published` state — so SwiftUI sees changes on the main thread.
final class CloudKitSyncMonitor: ObservableObject {

    /// A thread-safe snapshot of one `NSPersistentCloudKitContainer.Event`.
    struct SyncEvent: Sendable, Equatable {
        enum Kind: String, Sendable { case setup, `import`, export, unknown }
        let kind: Kind
        /// `true` once the phase has an end date (it ran to completion or failure).
        let finished: Bool
        let succeeded: Bool
        let endDate: Date?
        let error: String?
    }

    @Published private(set) var lastSetup: SyncEvent?
    @Published private(set) var lastImport: SyncEvent?
    @Published private(set) var lastExport: SyncEvent?
    /// Most recent failing phase, as `"export: <error>"`. Cleared once an export
    /// succeeds (the signal that local changes are reaching CloudKit). A non-nil
    /// value is the quick "sync is unhealthy" check.
    @Published private(set) var lastError: String?

    private let log = Logger(subsystem: "com.kidssrs.app", category: "CloudKitSync")
    private var cancellable: AnyCancellable?

    /// - Parameter center: injectable for tests; defaults to where
    ///   `NSPersistentCloudKitContainer` posts its events.
    init(center: NotificationCenter = .default) {
        cancellable = center
            .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .compactMap(Self.syncEvent(from:))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.ingest(event) }
    }

    /// Apply one event to the published state and log its outcome. Separated from
    /// notification parsing so it can be unit-tested directly (a real
    /// `NSPersistentCloudKitContainer.Event` cannot be constructed in a test).
    func ingest(_ event: SyncEvent) {
        switch event.kind {
        case .setup:  lastSetup = event
        case .import: lastImport = event
        case .export: lastExport = event
        case .unknown: break
        }

        guard event.finished else {
            log.debug("CloudKit \(event.kind.rawValue, privacy: .public) started")
            return
        }

        if event.succeeded {
            log.notice("CloudKit \(event.kind.rawValue, privacy: .public) finished OK")
            if event.kind == .export { lastError = nil }
        } else {
            let detail = event.error ?? "unknown error"
            log.error("CloudKit \(event.kind.rawValue, privacy: .public) FAILED: \(detail, privacy: .public)")
            lastError = "\(event.kind.rawValue): \(detail)"
        }
    }

    /// Extract a `Sendable` snapshot from the notification. Runs on the posting
    /// (non-main) queue, so it must not touch `@Published` state.
    private static func syncEvent(from notification: Notification) -> SyncEvent? {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else { return nil }

        let kind: SyncEvent.Kind
        switch event.type {
        case .setup:  kind = .setup
        case .import: kind = .import
        case .export: kind = .export
        @unknown default: kind = .unknown
        }

        return SyncEvent(kind: kind,
                         finished: event.endDate != nil,
                         succeeded: event.succeeded,
                         endDate: event.endDate,
                         error: event.error.map { String(describing: $0) })
    }
}
