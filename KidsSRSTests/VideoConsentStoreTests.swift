import XCTest
@testable import KidsSRS

/// Tests for `VideoConsentStore` (Spec §14.1): the consent state machine that
/// the video chokepoint relies on. Isolated `UserDefaults` suite per test.
final class VideoConsentStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "VideoConsentStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartsNotRequestedAndBlocked() {
        let store = VideoConsentStore(defaults: defaults)
        XCTAssertEqual(store.status, .notRequested)
        XCTAssertFalse(store.isGranted, "Video is blocked until consent (Spec §14.1)")
        XCTAssertNil(store.grantedAt)
    }

    func testGrantAllowsAndRecordsTimestamp() {
        let store = VideoConsentStore(defaults: defaults)
        store.grant()

        XCTAssertTrue(store.isGranted)
        XCTAssertNotNil(store.grantedAt)
        if case .granted = store.status {} else { XCTFail("Expected .granted") }
    }

    func testRevokeBlocksAgain() {
        let store = VideoConsentStore(defaults: defaults)
        store.grant()
        store.revoke()

        XCTAssertEqual(store.status, .revoked)
        XCTAssertFalse(store.isGranted, "Revoked consent must block video again")
        XCTAssertNil(store.grantedAt)
    }

    func testCanReGrantAfterRevoke() {
        let store = VideoConsentStore(defaults: defaults)
        store.grant()
        store.revoke()
        store.grant()

        XCTAssertTrue(store.isGranted)
        XCTAssertNotNil(store.grantedAt)
    }

    func testDecisionPersistsAcrossInstances() {
        VideoConsentStore(defaults: defaults).grant()
        XCTAssertTrue(VideoConsentStore(defaults: defaults).isGranted)

        VideoConsentStore(defaults: defaults).revoke()
        let reloaded = VideoConsentStore(defaults: defaults)
        XCTAssertEqual(reloaded.status, .revoked)
        XCTAssertFalse(reloaded.isGranted)
    }
}
