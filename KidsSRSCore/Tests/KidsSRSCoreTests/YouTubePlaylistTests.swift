import XCTest
@testable import KidsSRSCore

final class YouTubePlaylistIDTests: XCTestCase {
    private let id = "PLQ9tM66Cfklw6R_oGIE0BkGndyQWWPuwM"

    func testExtractsFromPlaylistURL() {
        XCTAssertEqual(YouTubePlaylistID.extract(from: "https://www.youtube.com/playlist?list=\(id)"), id)
    }
    func testExtractsFromWatchURLWithListParam() {
        XCTAssertEqual(
            YouTubePlaylistID.extract(from: "https://youtube.com/watch?v=abcdefghijk&list=\(id)"), id)
    }
    func testExtractsSchemelessAndBareID() {
        XCTAssertEqual(YouTubePlaylistID.extract(from: "youtube.com/playlist?list=\(id)"), id)
        XCTAssertEqual(YouTubePlaylistID.extract(from: id), id)
    }
    func testRejectsVideoIDAndJunk() {
        XCTAssertNil(YouTubePlaylistID.extract(from: "dQw4w9WgXcQ")) // 11-char video id
        XCTAssertNil(YouTubePlaylistID.extract(from: "not a url"))
    }
}

final class YouTubePlaylistParserTests: XCTestCase {

    func testParsesTitleAndOrderedDeDupedVideos() {
        let html = """
        <html><head>
        <meta property="og:title" content="Earth &amp; Space Songs">
        <title>Earth &amp; Space Songs - YouTube</title>
        </head><body>
        <script>var ytInitialData = {"contents":{"list":{"contents":[
          {"playlistVideoRenderer":{"videoId":"aaaaaaaaaaa","title":{"runs":[{"text":"First Song"}]}}},
          {"playlistVideoRenderer":{"videoId":"bbbbbbbbbbb","title":{"simpleText":"Second Song"}}},
          {"playlistVideoRenderer":{"videoId":"aaaaaaaaaaa","title":{"runs":[{"text":"Dup ignored"}]}}}
        ]}}};</script>
        </body></html>
        """
        let result = YouTubePlaylistParser.parse(html: html)
        XCTAssertEqual(result.title, "Earth & Space Songs")
        XCTAssertEqual(result.videos, [
            .init(id: "aaaaaaaaaaa", title: "First Song"),
            .init(id: "bbbbbbbbbbb", title: "Second Song"),
        ])
    }

    func testParsesLockupLayoutAndSkipsNonVideoLockups() {
        // YouTube serves either layout depending on session/region — the newer
        // `lockupViewModel` (contentId + title) or the older `playlistVideoRenderer`
        // (verified live 2026-06: an anonymous fetch currently returns the latter).
        // The parser handles both; the 11-char id filter keeps out channel lockups.
        let html = """
        <html><head><meta property="og:title" content="Songs"></head><body>
        <script>var ytInitialData = {"contents":[
          {"lockupViewModel":{"contentId":"ccccccccccc","contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
            "metadata":{"lockupMetadataViewModel":{"title":{"content":"Lockup Song"}}}}},
          {"lockupViewModel":{"contentId":"UCnotAVideoIdChannel00","metadata":{"lockupMetadataViewModel":{"title":{"content":"A Channel"}}}}}
        ]};</script></body></html>
        """
        let result = YouTubePlaylistParser.parse(html: html)
        XCTAssertEqual(result.videos, [.init(id: "ccccccccccc", title: "Lockup Song")])
    }

    func testEmptyWhenNoYtInitialData() {
        let result = YouTubePlaylistParser.parse(html: "<html><body>nothing here</body></html>")
        XCTAssertNil(result.title)
        XCTAssertTrue(result.videos.isEmpty)
    }

    func testFallsBackToTitleTagWhenNoOgTitle() {
        // No og:title meta → fall back to <title>, stripping the " - YouTube" suffix.
        let html = """
        <html><head><title>My Playlist - YouTube</title></head><body>
        <script>var ytInitialData = {"contents":[]};</script></body></html>
        """
        XCTAssertEqual(YouTubePlaylistParser.parse(html: html).title, "My Playlist")
    }
}
