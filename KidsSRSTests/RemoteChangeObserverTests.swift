import XCTest
import CoreData
@testable import KidsSRS

/// Tests for `RemoteChangeObserver` (Spec §10.1): a store remote-change
/// notification (CloudKit sync) triggers the view model's reload.
@MainActor
final class RemoteChangeObserverTests: XCTestCase {

    func testRemoteChangeNotificationTriggersOnChange() {
        let center = NotificationCenter()
        let fired = expectation(description: "onChange called")
        var count = 0

        let observer = RemoteChangeObserver(center: center) {
            count += 1
            fired.fulfill()
        }

        center.post(name: .NSPersistentStoreRemoteChange, object: nil)

        wait(for: [fired], timeout: 2)
        XCTAssertEqual(count, 1)
        withExtendedLifetime(observer) {}
    }

    func testBurstOfNotificationsIsDebouncedToOneReload() {
        let center = NotificationCenter()
        let fired = expectation(description: "onChange called once")
        var count = 0

        let observer = RemoteChangeObserver(center: center) {
            count += 1
            fired.fulfill()
        }

        // A sync batch posts several notifications in quick succession.
        for _ in 0..<5 { center.post(name: .NSPersistentStoreRemoteChange, object: nil) }

        wait(for: [fired], timeout: 2)
        XCTAssertEqual(count, 1, "Debounced to a single reload")
        withExtendedLifetime(observer) {}
    }
}
