import XCTest
import CoreData
@testable import KidsSRS

/// Tests for `PersistenceController`'s graceful store-load handling (Spec §4):
/// a load failure is surfaced, not crashed on.
final class PersistenceControllerTests: XCTestCase {

    func testHealthyStoreHasNoLoadError() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertNil(controller.loadError, "A normal in-memory store loads without error")
    }

    func testStoreLoadErrorIsSurfacedNotCrashed() {
        let controller = PersistenceController(inMemory: true)
        let failure = NSError(domain: NSCocoaErrorDomain,
                              code: NSPersistentStoreIncompatibleVersionHashError)

        controller.applyStoreLoadResult(failure)
        XCTAssertNotNil(controller.loadError, "A store failure must be surfaced, not crash")

        // Recovering on a later successful load clears it.
        controller.applyStoreLoadResult(nil)
        XCTAssertNil(controller.loadError)
    }
}
