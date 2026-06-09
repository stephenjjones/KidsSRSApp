import XCTest
@testable import KidsSRSCore

final class YouTubeVideoIDTests: XCTestCase {

    private let id = "dQw4w9WgXcQ" // 11 chars

    func testWatchURL() {
        XCTAssertEqual(YouTubeVideoID.extract(from: "https://www.youtube.com/watch?v=\(id)"), id)
    }

    func testWatchURLWithExtraParams() {
        XCTAssertEqual(
            YouTubeVideoID.extract(from: "https://youtube.com/watch?v=\(id)&list=PL123&index=2"), id)
    }

    func testShortURL() {
        XCTAssertEqual(YouTubeVideoID.extract(from: "https://youtu.be/\(id)"), id)
    }

    func testEmbedURL() {
        XCTAssertEqual(YouTubeVideoID.extract(from: "https://www.youtube.com/embed/\(id)"), id)
    }

    func testShortsURL() {
        XCTAssertEqual(YouTubeVideoID.extract(from: "https://www.youtube.com/shorts/\(id)"), id)
    }

    func testBareID() {
        XCTAssertEqual(YouTubeVideoID.extract(from: id), id)
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(YouTubeVideoID.extract(from: "  https://youtu.be/\(id)  "), id)
    }

    func testSchemelessURLs() {
        XCTAssertEqual(YouTubeVideoID.extract(from: "youtu.be/\(id)"), id)
        XCTAssertEqual(YouTubeVideoID.extract(from: "www.youtube.com/watch?v=\(id)"), id)
    }

    func testNonYouTubeHostReturnsNil() {
        XCTAssertNil(YouTubeVideoID.extract(from: "https://example.com/watch?v=\(id)"))
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(YouTubeVideoID.extract(from: "not a url"))
    }
}
