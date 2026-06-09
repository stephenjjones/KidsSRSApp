import SwiftUI

/// Entry point for parent-led **Song Review** (Spec §14.3), inside the adult-
/// gated parent zone. This is the *single* navigation seam the deferred consent
/// gate (§14.1) will later wrap. Lists playlists (decks of song cards); drill in
/// to add songs and start a review.
///
/// Reuses `DeckEditorViewModel` for listing/creating decks — a "playlist" is just
/// a deck whose cards are video songs.
struct SongPlaylistView: View {
    @StateObject private var model: DeckEditorViewModel

    @State private var showingNewPlaylist = false
    @State private var showingImport = false
    @State private var newTitle = ""

    init(model: DeckEditorViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if model.decks.isEmpty { emptyState } else { playlists }
        }
        .navigationTitle("Song Review")
        .toolbar {
            ToolbarItem {
                Button { showingImport = true } label: {
                    Label("Import from YouTube", systemImage: "square.and.arrow.down")
                }
                .accessibilityLabel("Import from YouTube")
            }
            ToolbarItem {
                Button { presentNewPlaylist() } label: {
                    Label("New playlist", systemImage: "plus")
                }
                .accessibilityLabel("New playlist")
            }
        }
        .sheet(isPresented: $showingImport, onDismiss: { model.load() }) {
            ImportPlaylistView(model: ImportPlaylistViewModel())
        }
        .alert("New playlist", isPresented: $showingNewPlaylist) {
            TextField("Playlist name", text: $newTitle)
            Button("Create") { _ = model.createDeck(title: newTitle) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name this playlist — for example “Times-table songs”.")
        }
        .alert("Something went wrong",
               isPresented: errorPresented,
               presenting: model.errorMessage) { _ in
            Button("OK") { model.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .task { model.load() }
    }

    private var playlists: some View {
        List {
            Section {
                NavigationLink {
                    SmartSongReviewView(model: SmartSongReviewViewModel())
                } label: {
                    Label("Smart review (what's due)", systemImage: "sparkles")
                }
            } footer: {
                Text("Auto-builds a review of the songs your kids need most, across every playlist.")
            }
            Section("Playlists") {
                ForEach(model.decks) { deck in
                    NavigationLink {
                        SongDeckView(model: model.makeSongDeckViewModel(for: deck))
                    } label: {
                        Label(deck.displayTitle, systemImage: "music.note.list")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No playlists yet", systemImage: "music.note.list")
        } description: {
            Text("Import a YouTube playlist, or create one and add songs by link.")
        } actions: {
            Button("Import from YouTube") { showingImport = true }
                .buttonStyle(.borderedProminent)
            Button("New empty playlist") { presentNewPlaylist() }
        }
    }

    private func presentNewPlaylist() {
        newTitle = ""
        showingNewPlaylist = true
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

/// One playlist's songs: add (paste a YouTube link), delete, and start a review.
struct SongDeckView: View {
    @StateObject private var model: SongDeckViewModel

    @State private var showingAddSong = false
    @State private var songTitle = ""
    @State private var songURL = ""

    init(model: SongDeckViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if model.songs.isEmpty { emptyState } else { songList }
        }
        .navigationTitle(model.deck.displayTitle)
        .toolbar {
            ToolbarItem {
                Button { presentAddSong() } label: {
                    Label("Add song", systemImage: "plus")
                }
                .accessibilityLabel("Add song")
            }
        }
        .alert("Add song", isPresented: $showingAddSong) {
            TextField("Title", text: $songTitle)
            TextField("YouTube link or ID", text: $songURL)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            Button("Add") { model.addSong(title: songTitle, youTube: songURL) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a YouTube video link (or its 11-character ID).")
        }
        .alert("Something went wrong",
               isPresented: errorPresented,
               presenting: model.errorMessage) { _ in
            Button("OK") { model.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .task { model.load() }
    }

    private var songList: some View {
        List {
            ForEach(model.songs) { song in
                Label(song.title.isEmpty ? "Untitled song" : song.title,
                      systemImage: "music.note")
            }
            .onDelete(perform: model.deleteSongs)

            Section {
                Button { presentAddSong() } label: {
                    Label("Add song", systemImage: "plus")
                }
                NavigationLink {
                    SongReviewView(model: model.makeReviewViewModel())
                } label: {
                    Label("Start Song Review", systemImage: "play.circle.fill")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No songs yet", systemImage: "music.note")
        } description: {
            Text("Add songs by pasting their YouTube links, then start a review.")
        } actions: {
            Button("Add song") { presentAddSong() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func presentAddSong() {
        songTitle = ""
        songURL = ""
        showingAddSong = true
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

#Preview("Playlists") {
    NavigationStack {
        SongPlaylistView(model: .sample())
    }
}

#Preview("One playlist") {
    NavigationStack {
        SongDeckView(model: .sample())
    }
}
