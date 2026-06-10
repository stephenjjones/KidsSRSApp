import Foundation

/// YouTube's "made for kids" (MFK) designation for a video.
enum MadeForKidsStatus: Equatable, Sendable {
    case madeForKids
    case notMadeForKids
    /// Couldn't determine (no API key, network/HTTP error, video private/removed,
    /// or the field was absent). Treated as **not allowed** — fail-closed.
    case unknown

    /// Only confirmed made-for-kids videos may be added to a playlist.
    var isAllowed: Bool { self == .madeForKids }
}

/// Verifies a YouTube video is designated **made for kids** before it can be added
/// to a Song Review playlist (Spec §14.1).
///
/// Restricting embeds to MFK content keeps YouTube in its personalized-ads-off /
/// contextual-only mode, which is the basis for offering video under COPPA's
/// "support for internal operations" path rather than separate verifiable parental
/// consent. The check is deliberately **fail-closed**: any uncertainty resolves to
/// `.unknown` (→ not added), so an unverifiable video never slips through.
protocol MadeForKidsChecking: Sendable {
    func status(forVideoID id: String) async -> MadeForKidsStatus
    /// Batched lookup (used by playlist import). Returns a status for every input id.
    func statuses(forVideoIDs ids: [String]) async -> [String: MadeForKidsStatus]
}

/// `MadeForKidsChecking` backed by the YouTube Data API v3 `videos.list` endpoint
/// (`part=status` → `status.madeForKids`).
///
/// The API key is read from the Info.plist `YouTubeDataAPIKey` value (wire it to a
/// build setting so it isn't committed). With no key the checker fails closed:
/// every video resolves to `.unknown`, so nothing can be added until a key is set.
struct YouTubeDataAPIMadeForKidsChecker: MadeForKidsChecking {
    var apiKey: String?
    var session: URLSession

    init(apiKey: String? = YouTubeDataAPIMadeForKidsChecker.configuredKey,
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// The key from Info.plist, or nil if missing/empty/unsubstituted.
    static var configuredKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "YouTubeDataAPIKey") as? String,
              !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        return raw
    }

    func status(forVideoID id: String) async -> MadeForKidsStatus {
        await statuses(forVideoIDs: [id])[id] ?? .unknown
    }

    func statuses(forVideoIDs ids: [String]) async -> [String: MadeForKidsStatus] {
        guard let apiKey, !ids.isEmpty else {
            return Dictionary(ids.map { ($0, .unknown) }, uniquingKeysWith: { a, _ in a })
        }
        var out: [String: MadeForKidsStatus] = [:]
        // videos.list accepts up to 50 ids per request.
        for chunk in Array(Set(ids)).chunked(into: 50) {
            out.merge(await fetchChunk(chunk, apiKey: apiKey)) { _, new in new }
        }
        // Any id the API didn't return (private/removed/region-blocked) → unknown.
        for id in ids where out[id] == nil { out[id] = .unknown }
        return out
    }

    private func fetchChunk(_ ids: [String], apiKey: String) async -> [String: MadeForKidsStatus] {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "status"),
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = components.url else { return [:] }
        var request = URLRequest(url: url)
        // Lets a Google API key whose "application restriction" is set to this
        // app's bundle id authorize the request — Google checks this header.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
            return Self.parse(responseData: data)
        } catch {
            return [:]   // network failure → callers resolve these ids to .unknown
        }
    }

    /// Pure parse of a `videos.list?part=status` JSON response into id → status.
    /// Factored out so the gating logic is unit-testable without the network.
    static func parse(responseData data: Data) -> [String: MadeForKidsStatus] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [:] }
        var out: [String: MadeForKidsStatus] = [:]
        for item in items {
            guard let id = item["id"] as? String,
                  let status = item["status"] as? [String: Any] else { continue }
            if let mfk = status["madeForKids"] as? Bool {
                out[id] = mfk ? .madeForKids : .notMadeForKids
            } else {
                out[id] = .unknown   // status present but no madeForKids field
            }
        }
        return out
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
