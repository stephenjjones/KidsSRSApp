import XCTest
@testable import KidsSRS

/// Tests for the OpenDyslexic font integration (Spec §11).
final class DyslexiaFontProviderTests: XCTestCase {

    func testFamilyName() {
        XCTAssertEqual(DyslexiaFontProvider.familyName, "OpenDyslexic")
    }

    func testBundledFontRegistersAndIsAvailable() {
        // The OpenDyslexic .otf ships in the app bundle; registering it (idempotent)
        // makes the family available for dyslexia mode.
        DyslexiaFontProvider.registerBundledFonts()
        XCTAssertTrue(DyslexiaFontProvider.isAvailable,
                      "Bundled OpenDyslexic should register and be detectable")
    }

    func testBaseSizesAreOrderedByStyle() {
        // Sanity: larger text styles map to larger base sizes (Dynamic Type scales
        // from these via `relativeTo:`).
        XCTAssertGreaterThan(DyslexiaFriendly.baseSize(for: .largeTitle),
                             DyslexiaFriendly.baseSize(for: .body))
        XCTAssertGreaterThan(DyslexiaFriendly.baseSize(for: .title),
                             DyslexiaFriendly.baseSize(for: .caption))
    }
}
