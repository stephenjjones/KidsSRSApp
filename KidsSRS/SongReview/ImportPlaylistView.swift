import SwiftUI
import KidsSRSCore

/// Imports a YouTube playlist into a new song playlist (Spec §14.3): paste a
/// public playlist link, preview the videos, optionally rename, then create a
/// deck with one video card per song.
///
/// Reads the playlist *page* (no API key, any size up to ~100). The default name
/// comes from the playlist; it's editable before import.
@MainActor
final class ImportPlaylistViewModel: ObservableObject {
    enum Phase: Equatable { case entry, loading, preview, importing }

    @Published var url = ""
    @Published var name = ""
    @Published private(set) var videos: [YouTubePlaylistParser.Video] = []
    /// How many playlist videos were dropped because they aren't made for kids.
    @Published private(set) var excludedCount = 0
    @Published private(set) var phase: Phase = .entry
    @Published var errorMessage: String?

    private let decks: DeckRepository
    private let mfk: MadeForKidsChecking

    init(decks: DeckRepository = DeckRepository(),
         mfk: MadeForKidsChecking = YouTubeDataAPIMadeForKidsChecker()) {
        self.decks = decks
        self.mfk = mfk
    }

    var canFind: Bool { phase != .loading && YouTubePlaylistID.extract(from: url) != nil }
    var canImport: Bool {
        phase == .preview && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !videos.isEmpty
    }

    /// Fetch + parse the playlist page, then show the preview.
    func find() async {
        guard let playlistID = YouTubePlaylistID.extract(from: url) else {
            errorMessage = "That doesn't look like a YouTube playlist link."
            return
        }
        phase = .loading
        errorMessage = nil
        excludedCount = 0
        do {
            let html = try await Self.fetchHTML(playlistID: playlistID)
            let result = YouTubePlaylistParser.parse(html: html)
            guard !result.videos.isEmpty else {
                phase = .entry
                errorMessage = "Couldn't find any videos. Make sure the playlist is public."
                return
            }
            // Keep only made-for-kids videos (Spec §14.1) — fail-closed: anything
            // we can't confirm is dropped from the import.
            let statuses = await mfk.statuses(forVideoIDs: result.videos.map(\.id))
            let allowed = result.videos.filter { statuses[$0.id]?.isAllowed == true }
            excludedCount = result.videos.count - allowed.count
            guard !allowed.isEmpty else {
                phase = .entry
                errorMessage = "None of these videos are marked “made for kids,” so none can be imported."
                return
            }
            videos = allowed
            name = result.title ?? "Imported playlist"
            phase = .preview
        } catch {
            phase = .entry
            errorMessage = "Couldn't load that playlist. Check your connection and that it's public."
        }
    }

    /// Create the deck + a video card per song. Returns the new deck id on success.
    @discardableResult
    func performImport() -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !videos.isEmpty else { return nil }
        phase = .importing
        do {
            let songs = videos.map { (videoID: $0.id, title: $0.title) }
            let deck = try decks.createSongDeck(title: trimmed, songs: songs)
            return deck.id
        } catch {
            phase = .preview
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private static func fetchHTML(playlistID: String) async throws -> String {
        let url = URL(string: "https://www.youtube.com/playlist?list=\(playlistID)")!
        var request = URLRequest(url: url)
        // A desktop UA gets the page that embeds `ytInitialData`.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }
}

struct ImportPlaylistView: View {
    @StateObject private var model: ImportPlaylistViewModel
    @Environment(\.dismiss) private var dismiss

    init(model: ImportPlaylistViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("YouTube playlist link", text: $model.url, axis: .vertical)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        #endif
                    Button { Task { await model.find() } } label: {
                        if model.phase == .loading {
                            ProgressView()
                        } else {
                            Text("Find playlist")
                        }
                    }
                    .disabled(!model.canFind)
                    // Announce the action even while the spinner replaces the text (§11).
                    .accessibilityLabel(model.phase == .loading ? "Finding playlist" : "Find playlist")
                } header: {
                    Text("Import from YouTube")
                } footer: {
                    Text("Paste a public YouTube playlist link. We'll make a song playlist with a card for each video.")
                }

                if model.phase == .preview || model.phase == .importing {
                    Section("Name") {
                        TextField("Playlist name", text: $model.name)
                    }
                    Section {
                        ForEach(model.videos, id: \.id) { video in
                            Label(video.title, systemImage: "music.note")
                                .lineLimit(1)
                        }
                    } header: {
                        Text("\(model.videos.count) \(model.videos.count == 1 ? "song" : "songs")")
                    } footer: {
                        if model.excludedCount > 0 {
                            Text("\(model.excludedCount) video\(model.excludedCount == 1 ? "" : "s") skipped — not marked “made for kids.”")
                        }
                    }
                }
            }
            .navigationTitle("Import playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        if model.performImport() != nil { dismiss() }
                    }
                    .disabled(!model.canImport)
                }
            }
            .alert("Something went wrong",
                   isPresented: errorPresented,
                   presenting: model.errorMessage) { _ in
                Button("OK") { model.errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}
