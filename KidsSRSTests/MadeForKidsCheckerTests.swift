import XCTest
@testable import KidsSRS

/// Tests for `YouTubeDataAPIMadeForKidsChecker` (Spec §14.1): parsing the Data API
/// `videos.list?part=status` response, and the fail-closed guarantees that keep a
/// non–made-for-kids (or unverifiable) video out of a playlist.
final class MadeForKidsCheckerTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testParseMapsMadeForKidsBooleans() {
        let json = """
        {"items":[
          {"id":"AAA","status":{"madeForKids":true}},
          {"id":"BBB","status":{"madeForKids":false}}
        ]}
        """
        let out = YouTubeDataAPIMadeForKidsChecker.parse(responseData: data(json))
        XCTAssertEqual(out["AAA"], .madeForKids)
        XCTAssertEqual(out["BBB"], .notMadeForKids)
    }

    func testParseTreatsMissingFieldAsUnknown() {
        let json = #"{"items":[{"id":"CCC","status":{"privacyStatus":"public"}}]}"#
        let out = YouTubeDataAPIMadeForKidsChecker.parse(responseData: data(json))
        XCTAssertEqual(out["CCC"], .unknown)
    }

    func testParseHandlesEmptyAndJunk() {
        XCTAssertTrue(YouTubeDataAPIMadeForKidsChecker.parse(responseData: data("{}")).isEmpty)
        XCTAssertTrue(YouTubeDataAPIMadeForKidsChecker.parse(responseData: data("not json")).isEmpty)
    }

    func testNoAPIKeyFailsClosed() async {
        let checker = YouTubeDataAPIMadeForKidsChecker(apiKey: nil)
        let one = await checker.status(forVideoID: "AAA")
        XCTAssertEqual(one, .unknown)
        let many = await checker.statuses(forVideoIDs: ["AAA", "BBB"])
        XCTAssertEqual(many["AAA"], .unknown)
        XCTAssertEqual(many["BBB"], .unknown)
    }

    func testIsAllowedOnlyForMadeForKids() {
        XCTAssertTrue(MadeForKidsStatus.madeForKids.isAllowed)
        XCTAssertFalse(MadeForKidsStatus.notMadeForKids.isAllowed)
        XCTAssertFalse(MadeForKidsStatus.unknown.isAllowed)
    }
}
