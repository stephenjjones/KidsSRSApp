import Foundation
import KidsSRSCore

/// Manages one playlist's **songs** for Song Review (Spec §14.3): list, add (by
/// pasting a YouTube link), delete. Mirrors `DeckDetailViewModel`, but for video
/// cards. Talks only to `DeckRepository` and exposes value types (Spec §4.1).
@MainActor
final class SongDeckViewModel: ObservableObject {
    @Published private(set) var deck: DeckSummary
    @Published private(set) var songs: [PlaylistSong] = []
    @Published var errorMessage: String?

    private let repository: DeckRepository
    private let mfk: MadeForKidsChecking

    init(deck: DeckSummary, repository: DeckRepository = DeckRepository(),
         mfk: MadeForKidsChecking = YouTubeDataAPIMadeForKidsChecker()) {
        self.deck = deck
        self.repository = repository
        self.mfk = mfk
    }

    func load() {
        perform { self.songs = try self.repository.fetchSongs(in: self.deck.id) }
    }

    /// Add a song from a pasted title + YouTube URL/ID. The video must be
    /// designated **made for kids** on YouTube (Spec §14.1); anything unparseable
    /// or not-MFK surfaces a friendly error rather than being added.
    func addSong(title: String, youTube: String) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRef = youTube.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedRef.isEmpty else { return }
        guard let videoID = YouTubeVideoID.extract(from: trimmedRef) else {
            errorMessage = "That doesn't look like a YouTube video link."
            return
        }
        let status = await mfk.status(forVideoID: videoID)
        guard status.isAllowed else {
            errorMessage = Self.notAllowedMessage(status)
            return
        }
        perform {
            try self.repository.addVideoCard(to: self.deck.id, title: trimmedTitle,
                                             youTube: trimmedRef, hint: nil)
        }
        load()
    }

    /// Why a video was rejected by the made-for-kids gate (Spec §14.1).
    static func notAllowedMessage(_ status: MadeForKidsStatus) -> String {
        switch status {
        case .notMadeForKids:
            return "Only videos marked “made for kids” on YouTube can be added. This one isn’t."
        case .unknown:
            return "We couldn’t confirm this video is “made for kids,” so it can’t be added. Check your connection and try again."
        case .madeForKids:
            return ""   // not reached — allowed videos are added
        }
    }

    func deleteSongs(at offsets: IndexSet) {
        let ids = offsets.map { songs[$0].id }
        perform { for id in ids { try self.repository.deleteCard(id: id) } }
        load()
    }

    /// A review session view model for this playlist (live store).
    func makeReviewViewModel() -> SongReviewViewModel {
        SongReviewViewModel(deck: deck)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    /// Preview/test factory backed by the in-memory store with a seeded playlist.
    static func sample() -> SongDeckViewModel {
        let repository = DeckRepository.preview
        let deck = (try? repository.createDeck(title: "Morning Songs"))
            ?? DeckSummary(id: UUID(), title: "Morning Songs", cardCount: 0)
        _ = try? repository.addVideoCard(to: deck.id, title: "Days of the Week",
                                         youTube: "https://youtu.be/36n93jvjkDs", hint: nil)
        _ = try? repository.addVideoCard(to: deck.id, title: "Count to 100",
                                         youTube: "https://youtu.be/0VLxWIHRD4E", hint: nil)
        let model = SongDeckViewModel(deck: deck, repository: repository)
        model.load()
        return model
    }
}

/// Drives a parent-led Song Review session (Spec §14.3): plays a playlist's
/// songs in order; for each song the parent rates every child on the 3-level
/// parent grade (§14.4), which feeds each child's scheduler state.
@MainActor
final class SongReviewViewModel: ObservableObject {
    @Published private(set) var songs: [PlaylistSong] = []
    @Published private(set) var children: [ChildSummary] = []
    @Published private(set) var index = 0
    /// The grade chosen for each child on the *current* song — for highlighting
    /// the selection. Reset when the song changes.
    @Published private(set) var selection: [UUID: ParentGrade] = [:]
    /// A readable note when the current video can't be played (e.g. the owner
    /// disabled embedding — Spec §14.1). Cleared on song change.
    @Published private(set) var playerNote: String?
    /// Which children are in the room — only they are scored (Spec §14.3). All
    /// present by default; persists across songs within the session.
    @Published private(set) var presentChildIDs: Set<UUID> = []
    /// True once the last song has finished playing.
    @Published private(set) var isFinished = false
    @Published var errorMessage: String?

    /// What this session reviews: one playlist, or a generated cross-playlist set.
    enum Source {
        case deck(DeckSummary)
        case generated(songs: [PlaylistSong], childIDs: [UUID])
    }

    private let source: Source
    private let decks: DeckRepository
    private let childRepository: ChildRepository
    private let study: StudyRepository
    private let now: () -> Date

    init(source: Source,
         decks: DeckRepository = DeckRepository(),
         childRepository: ChildRepository = ChildRepository(),
         study: StudyRepository = StudyRepository(),
         now: @escaping () -> Date = Date.init) {
        self.source = source
        self.decks = decks
        self.childRepository = childRepository
        self.study = study
        self.now = now
    }

    /// Convenience: review a single playlist (deck).
    convenience init(deck: DeckSummary,
                     decks: DeckRepository = DeckRepository(),
                     childRepository: ChildRepository = ChildRepository(),
                     study: StudyRepository = StudyRepository(),
                     now: @escaping () -> Date = Date.init) {
        self.init(source: .deck(deck), decks: decks,
                  childRepository: childRepository, study: study, now: now)
    }

    var currentSong: PlaylistSong? { songs.indices.contains(index) ? songs[index] : nil }
    var hasNext: Bool { index + 1 < songs.count }
    var hasPrevious: Bool { index > 0 }
    var positionText: String { songs.isEmpty ? "" : "Song \(index + 1) of \(songs.count)" }

    /// The children currently marked present, in display order.
    var presentChildren: [ChildSummary] { children.filter { presentChildIDs.contains($0.id) } }

    func load() {
        switch source {
        case .deck(let deck):
            perform {
                self.songs = try self.decks.fetchSongs(in: deck.id)
                self.children = try self.childRepository.fetchChildren()
            }
            presentChildIDs = Set(children.map(\.id)) // everyone present by default
        case .generated(let songs, let childIDs):
            self.songs = songs
            perform {
                self.children = try self.childRepository.fetchChildren()
                    .filter { childIDs.contains($0.id) }
            }
            presentChildIDs = Set(childIDs)
        }
        index = 0
        isFinished = false
        resetForNewSong()
    }

    /// Toggle whether a child is in the room (and therefore scored).
    func togglePresence(_ childID: UUID) {
        if presentChildIDs.contains(childID) {
            presentChildIDs.remove(childID)
        } else {
            presentChildIDs.insert(childID)
        }
    }

    /// Map a YouTube IFrame error code to a parent-readable note (Spec §14.1).
    func reportPlayerError(code: Int) {
        switch code {
        case 2:
            playerNote = "That video link looks invalid."
        case 5:
            playerNote = "This video can't be played here. Try a different one."
        case 100:
            playerNote = "This video is unavailable — it may be private or removed."
        case 101, 150:
            playerNote = "This video's owner doesn't allow it to play outside YouTube. Try a different video."
        default:
            playerNote = "This video couldn't be played (error \(code))."
        }
    }

    /// Record the parent's rating for one child on the current song (Spec §14.4).
    func grade(_ grade: ParentGrade, forChild childID: UUID) {
        guard let song = currentSong else { return }
        perform {
            try self.study.scoreSong(forChild: childID, cardID: song.id,
                                     grade: grade, now: self.now())
        }
        selection[childID] = grade
    }

    /// The current video finished playing — advance, or end the playlist.
    func songDidEnd() {
        if hasNext { goNext() } else { isFinished = true }
    }

    func goNext() {
        guard hasNext else { return }
        index += 1
        resetForNewSong()
    }

    func goPrevious() {
        guard hasPrevious else { return }
        index -= 1
        resetForNewSong()
    }

    /// Restart the playlist from the first song.
    func restart() {
        index = 0
        isFinished = false
        resetForNewSong()
    }

    private func resetForNewSong() {
        selection = [:]
        playerNote = nil
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    /// Preview/test factory: an in-memory store seeded with a playlist + children.
    static func sample() -> SongReviewViewModel {
        let persistence = PersistenceController(inMemory: true)
        let decks = DeckRepository(persistence: persistence)
        let children = ChildRepository(persistence: persistence)
        let study = StudyRepository(persistence: persistence)
        let deck = (try? decks.createDeck(title: "Morning Songs"))
            ?? DeckSummary(id: UUID(), title: "Morning Songs", cardCount: 0)
        _ = try? decks.addVideoCard(to: deck.id, title: "Days of the Week",
                                    youTube: "https://youtu.be/36n93jvjkDs", hint: nil)
        _ = try? decks.addVideoCard(to: deck.id, title: "Count to 100",
                                    youTube: "https://youtu.be/0VLxWIHRD4E", hint: nil)
        _ = try? children.createChild(name: "Mia")
        _ = try? children.createChild(name: "Theo")
        let model = SongReviewViewModel(deck: deck, decks: decks,
                                        childRepository: children, study: study)
        model.load()
        return model
    }
}
