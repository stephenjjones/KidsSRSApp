import XCTest
import CoreData
@testable import KidsSRS

/// Tests for `CloudKitSyncMonitor` (Spec §10.1). A real
/// `NSPersistentCloudKitContainer.Event` has no public initializer, so these
/// drive the testable `ingest(_:)` seam directly with synthetic snapshots.
final class CloudKitSyncMonitorTests: XCTestCase {
    typealias Event = CloudKitSyncMonitor.SyncEvent

    func testFailedExportRecordsError() {
        let monitor = CloudKitSyncMonitor(center: NotificationCenter())
        monitor.ingest(Event(kind: .export, finished: true, succeeded: false,
                             endDate: Date(), error: "CKError: quota exceeded"))
        XCTAssertEqual(monitor.lastExport?.succeeded, false)
        XCTAssertEqual(monitor.lastError, "export: CKError: quota exceeded")
    }

    func testSuccessfulExportClearsError() {
        let monitor = CloudKitSyncMonitor(center: NotificationCenter())
        monitor.ingest(Event(kind: .export, finished: true, succeeded: false,
                             endDate: Date(), error: "boom"))
        XCTAssertNotNil(monitor.lastError)
        monitor.ingest(Event(kind: .export, finished: true, succeeded: true,
                             endDate: Date(), error: nil))
        XCTAssertNil(monitor.lastError, "a successful export means local changes reached CloudKit")
        XCTAssertEqual(monitor.lastExport?.succeeded, true)
    }

    func testSuccessfulImportDoesNotMaskExportFailure() {
        let monitor = CloudKitSyncMonitor(center: NotificationCenter())
        monitor.ingest(Event(kind: .export, finished: true, succeeded: false,
                             endDate: Date(), error: "boom"))
        monitor.ingest(Event(kind: .import, finished: true, succeeded: true,
                             endDate: Date(), error: nil))
        XCTAssertEqual(monitor.lastError, "export: boom",
                       "import success must not clear a pending export failure")
        XCTAssertEqual(monitor.lastImport?.succeeded, true)
    }

    func testInProgressEventDoesNotSetError() {
        let monitor = CloudKitSyncMonitor(center: NotificationCenter())
        monitor.ingest(Event(kind: .import, finished: false, succeeded: false,
                             endDate: nil, error: nil))
        XCTAssertNil(monitor.lastError)
        XCTAssertEqual(monitor.lastImport?.finished, false)
    }

    // MARK: Summary roll-up (drives the parent-zone status row)

    func testSummaryIsIdleBeforeAnyEvent() {
        let monitor = CloudKitSyncMonitor(center: NotificationCenter())
        XCTAssertEqual(monitor.summary.state, .idle)
        XCTAssertNil(monitor.summary.lastSyncedAt)
    }

    func testSummaryIsHealthyWithSyncTimeAfterExport() {
        let monitor = CloudKitSyncMonitor(center: NotificationCenter())
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        monitor.ingest(Event(kind: .export, finished: true, succeeded: true,
                             endDate: end, error: nil))
        XCTAssertEqual(monitor.summary.state, .healthy)
        XCTAssertEqual(monitor.summary.lastSyncedAt, end)
        XCTAssertNil(monitor.summary.errorDetail)
    }

    func testSummaryIsFailingWhenAPhaseErrors() {
        let monitor = CloudKitSyncMonitor(center: NotificationCenter())
        monitor.ingest(Event(kind: .export, finished: true, succeeded: false,
                             endDate: Date(), error: "quota exceeded"))
        XCTAssertEqual(monitor.summary.state, .failing)
        XCTAssertEqual(monitor.summary.errorDetail, "export: quota exceeded")
    }

    func testSummaryIsSyncingAfterSetupBeforeExport() {
        let monitor = CloudKitSyncMonitor(center: NotificationCenter())
        monitor.ingest(Event(kind: .setup, finished: true, succeeded: true,
                             endDate: Date(), error: nil))
        XCTAssertEqual(monitor.summary.state, .syncing)
    }
}
