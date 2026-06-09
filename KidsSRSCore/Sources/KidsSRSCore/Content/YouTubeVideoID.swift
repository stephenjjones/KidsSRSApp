import Foundation

/// Extracts a YouTube video ID from the URL forms a parent is likely to paste
/// (Spec §14.2). Pure and dependency-free, so it can be unit-tested and reused
/// by the deck editor and the player. Returns `nil` if no plausible
/// 11-character video ID is found.
public enum YouTubeVideoID {

    /// A YouTube video ID is 11 characters of `[A-Za-z0-9_-]`.
    private static let length = 11
    private static let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    /// Best-effort extraction from a pasted URL or bare ID. Handles
    /// `watch?v=`, `youtu.be/`, `/embed/`, and `/shorts/` forms.
    public static func extract(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A bare ID pasted on its own.
        if isID(trimmed) { return trimmed }

        // Ensure a scheme so `host` / `pathComponents` parse — parents often
        // paste "youtu.be/<id>" or "www.youtube.com/watch?v=<id>" without one.
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized) else { return nil }
        let host = (url.host ?? "").lowercased()

        if host.hasSuffix("youtu.be") {
            return firstIDPathComponent(of: url)          // youtu.be/<id>
        }
        if host.contains("youtube.com") {
            if let v = queryItem(url, "v"), isID(v) { return v }  // watch?v=<id>
            return firstIDPathComponent(of: url)          // /embed/<id>, /shorts/<id>
        }
        return nil
    }

    private static func isID(_ s: String) -> Bool {
        s.count == length && s.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func firstIDPathComponent(of url: URL) -> String? {
        url.pathComponents.first(where: isID)
    }

    private static func queryItem(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}
