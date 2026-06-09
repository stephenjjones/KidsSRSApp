import XCTest
@testable import KidsSRS

/// Tests for `AdultGateStore` (Spec §8.1): passcode set/verify/remove and the
/// math/passcode method switch. Uses an isolated `UserDefaults` suite per test.
final class AdultGateStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AdultGateStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToMathWithNoPasscode() {
        let store = AdultGateStore(defaults: defaults)
        XCTAssertEqual(store.method, .math)
        XCTAssertFalse(store.hasPasscode)
        XCTAssertFalse(store.biometricEnabled)
    }

    func testSetPasscodeSwitchesMethodAndVerifies() {
        let store = AdultGateStore(defaults: defaults)
        store.setPasscode("2468")

        XCTAssertEqual(store.method, .passcode)
        XCTAssertTrue(store.hasPasscode)
        XCTAssertTrue(store.verifyPasscode("2468"))
        XCTAssertFalse(store.verifyPasscode("1357"))
        XCTAssertFalse(store.verifyPasscode(""))
    }

    func testPasscodeIsNotStoredInPlaintext() {
        let store = AdultGateStore(defaults: defaults)
        store.setPasscode("2468")
        // Nothing in the suite should equal the raw passcode.
        for (_, value) in defaults.dictionaryRepresentation() {
            XCTAssertNotEqual(value as? String, "2468")
        }
    }

    func testRemovePasscodeFallsBackToMath() {
        let store = AdultGateStore(defaults: defaults)
        store.setPasscode("2468")
        store.removePasscode()

        XCTAssertEqual(store.method, .math)
        XCTAssertFalse(store.hasPasscode)
        XCTAssertFalse(store.verifyPasscode("2468"))
    }

    func testConfigurationPersistsAcrossInstances() {
        let first = AdultGateStore(defaults: defaults)
        first.setPasscode("9999")
        first.biometricEnabled = true

        let second = AdultGateStore(defaults: defaults)
        XCTAssertEqual(second.method, .passcode)
        XCTAssertTrue(second.hasPasscode)
        XCTAssertTrue(second.verifyPasscode("9999"))
        XCTAssertTrue(second.biometricEnabled)
    }

    func testChangingPasscodeInvalidatesTheOld() {
        let store = AdultGateStore(defaults: defaults)
        store.setPasscode("1111")
        store.setPasscode("2222")
        XCTAssertFalse(store.verifyPasscode("1111"))
        XCTAssertTrue(store.verifyPasscode("2222"))
    }
}
