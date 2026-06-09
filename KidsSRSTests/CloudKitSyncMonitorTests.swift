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
}
