import Foundation

/// Extracts a YouTube **playlist** id (the `list=` value) from a pasted URL or a
/// bare id (Spec §14.3 playlist import). Returns nil if none is found.
public enum YouTubePlaylistID {

    private static let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    public static func extract(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isID(trimmed) { return trimmed }

        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        if let list = items.first(where: { $0.name == "list" })?.value, isID(list) {
            return list
        }
        return nil
    }

    /// Playlist ids are longer than the 11-char video id and share its alphabet.
    private static func isID(_ s: String) -> Bool {
        (13...64).contains(s.count) && s.unicodeScalars.allSatisfy(allowed.contains)
    }
}
