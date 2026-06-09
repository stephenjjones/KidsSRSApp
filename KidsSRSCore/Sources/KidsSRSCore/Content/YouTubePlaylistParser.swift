import Foundation

/// Parses a YouTube **playlist page**'s HTML into a name + ordered video list
/// (Spec §14.3 playlist import). Pure (no network), so it's unit-testable; the
/// app fetches the HTML and hands it here.
///
/// It reads the page's embedded `ytInitialData` JSON for the videos (each
/// `playlistVideoRenderer`'s id + title) and the `og:title` meta for the playlist
/// name. This is **unofficial** — it depends on YouTube's page shape and returns
/// an empty video list if that changes.
public enum YouTubePlaylistParser {

    public struct Video: Equatable, Sendable {
        public let id: String
        public let title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public struct Result: Equatable, Sendable {
        public let title: String?
        public let videos: [Video]
        public init(title: String?, videos: [Video]) {
            self.title = title
            self.videos = videos
        }
    }

    public static func parse(html: String) -> Result {
        Result(title: playlistTitle(in: html), videos: videos(in: html))
    }

    // MARK: Videos

    private static func videos(in html: String) -> [Video] {
        guard let json = ytInitialData(in: html),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return [] }
        var videos: [Video] = []
        var seen = Set<String>()
        collect(root, into: &videos, seen: &seen)
        return videos
    }

    /// The `ytInitialData = { … };` JSON blob embedded in the page.
    private static func ytInitialData(in html: String) -> String? {
        guard let start = html.range(of: "ytInitialData = ") else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: ";</script>") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    /// Depth-first collection of every video node. They live in one ordered
    /// array, so iterating arrays in order preserves playlist order.
    private static func collect(_ node: Any, into videos: inout [Video], seen: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if let video = video(from: dict), seen.insert(video.id).inserted {
                videos.append(video)
            }
            for value in dict.values { collect(value, into: &videos, seen: &seen) }
        } else if let array = node as? [Any] {
            for value in array { collect(value, into: &videos, seen: &seen) }
        }
    }

    /// Extract a video from a node in either the current (`lockupViewModel`) or
    /// the older (`playlistVideoRenderer`) playlist layout. The 11-char id check
    /// keeps out channel/playlist lockups.
    private static func video(from dict: [String: Any]) -> Video? {
        if let lockup = dict["lockupViewModel"] as? [String: Any],
           let id = lockup["contentId"] as? String, isVideoID(id),
           let title = lockupTitle(lockup) {
            return Video(id: id, title: title)
        }
        if let renderer = dict["playlistVideoRenderer"] as? [String: Any],
           let id = renderer["videoId"] as? String, isVideoID(id),
           let title = text(renderer["title"]) {
            return Video(id: id, title: title)
        }
        return nil
    }

    /// `lockupViewModel.metadata.lockupMetadataViewModel.title.content`.
    private static func lockupTitle(_ lockup: [String: Any]) -> String? {
        let metadata = lockup["metadata"] as? [String: Any]
        let metaVM = metadata?["lockupMetadataViewModel"] as? [String: Any]
        let title = metaVM?["title"] as? [String: Any]
        return title?["content"] as? String
    }

    private static let idChars = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    private static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && s.unicodeScalars.allSatisfy(idChars.contains)
    }

    /// A YouTube text node: `{ "simpleText": … }` or `{ "runs": [{ "text": … }] }`.
    private static func text(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]], let first = runs.first {
            return first["text"] as? String
        }
        return nil
    }

    // MARK: Title

    private static func playlistTitle(in html: String) -> String? {
        if let value = metaContent(property: "og:title", in: html) { return value }
        if let title = between("<title>", "</title>", in: html) {
            return title.replacingOccurrences(of: " - YouTube", with: "")
        }
        return nil
    }

    /// `<meta property="…" content="…">` — content is read just after the property.
    private static func metaContent(property: String, in html: String) -> String? {
        guard let propRange = html.range(of: "property=\"\(property)\"") else { return nil }
        let rest = html[propRange.upperBound...]
        guard let contentRange = rest.range(of: "content=\"") else { return nil }
        let afterContent = rest[contentRange.upperBound...]
        guard let close = afterContent.range(of: "\"") else { return nil }
        return decodeEntities(String(afterContent[..<close.lowerBound]))
    }

    private static func between(_ open: String, _ close: String, in html: String) -> String? {
        guard let o = html.range(of: open),
              let c = html.range(of: close, range: o.upperBound..<html.endIndex) else { return nil }
        return decodeEntities(String(html[o.upperBound..<c.lowerBound]))
    }

    /// Decode the handful of HTML entities that show up in titles.
    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
