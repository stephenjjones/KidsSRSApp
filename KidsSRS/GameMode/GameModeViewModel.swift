import Foundation
import KidsSRSCore

/// Drives **Game Mode** (Spec §14.5): the parent picks a child + categories, then
/// the app draws that child's cards — individualized by `GameDrawPlanner`
/// (neediest first) — to replace a board game's question cards. Reveal the
/// answer, then optionally mark right/wrong, which feeds the scheduler.
///
/// One view model with two phases (setup → playing) so there's no navigation to
/// stale-capture the selection. Talks only to repositories; exposes value types.
@MainActor
final class GameModeViewModel: ObservableObject {
    // Setup
    @Published private(set) var children: [ChildSummary] = []
    @Published private(set) var allTags: [TagSummary] = []
    @Published var selectedChildID: UUID?
    /// Chosen categories; **empty means all** (matches `loadGameDraw`).
    @Published private(set) var selectedTagIDs: Set<UUID> = []

    // Playing
    @Published private(set) var isPlaying = false
    @Published private(set) var pool: [GameDrawCard] = []
    @Published private(set) var index = 0
    @Published private(set) var isRevealed = false

    @Published var errorMessage: String?

    private let decks: DeckRepository
    private let childRepository: ChildRepository
    private let study: StudyRepository
    private let now: () -> Date

    init(decks: DeckRepository = DeckRepository(),
         childRepository: ChildRepository = ChildRepository(),
         study: StudyRepository = StudyRepository(),
         now: @escaping () -> Date = Date.init) {
        self.decks = decks
        self.childRepository = childRepository
        self.study = study
        self.now = now
    }

    var canStart: Bool { selectedChildID != nil }
    var current: GameDrawCard? { pool.indices.contains(index) ? pool[index] : nil }
    /// The chosen child (carries their accessibility prefs, Spec §11).
    var selectedChild: ChildSummary? { children.first { $0.id == selectedChildID } }
    var selectedChildName: String {
        let name = selectedChild?.displayName ?? ""
        return name.isEmpty ? "This player" : name
    }

    func load() {
        perform {
            self.children = try self.childRepository.fetchChildren()
            self.allTags = try self.decks.fetchTags()
        }
        if selectedChildID == nil { selectedChildID = children.first?.id }
    }

    func toggleTag(_ id: UUID) {
        if selectedTagIDs.contains(id) { selectedTagIDs.remove(id) } else { selectedTagIDs.insert(id) }
    }

    /// Build the individualized draw pool for the chosen child + categories.
    func start() {
        guard let childID = selectedChildID else { return }
        perform { self.pool = try self.study.loadGameDraw(forChild: childID,
                                                          tagIDs: self.selectedTagIDs,
                                                          now: self.now()) }
        index = 0
        isRevealed = false
        isPlaying = true
    }

    func endGame() {
        isPlaying = false
        pool = []
    }

    func reveal() { isRevealed = true }

    /// Advance without scoring.
    func skip() { advance() }

    /// Mark the current card right/wrong (Spec §14.5) and advance.
    func score(correct: Bool) {
        guard let childID = selectedChildID, let card = current else { return }
        perform { try self.study.scoreGameDraw(forChild: childID, cardID: card.id,
                                               correct: correct, now: self.now()) }
        advance()
    }

    private func advance() {
        isRevealed = false
        if index + 1 < pool.count {
            index += 1
        } else if let childID = selectedChildID {
            // Cycle: re-rank with the updated scheduler state and start over.
            perform { self.pool = try self.study.loadGameDraw(forChild: childID,
                                                              tagIDs: self.selectedTagIDs,
                                                              now: self.now()) }
            index = 0
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    /// Preview/test factory: in-memory store with a tagged, assigned deck + child.
    static func sample() -> GameModeViewModel {
        let persistence = PersistenceController(inMemory: true)
        let decks = DeckRepository(persistence: persistence)
        let children = ChildRepository(persistence: persistence)
        let study = StudyRepository(persistence: persistence)
        let child = (try? children.createChild(name: "Mia"))
            ?? ChildSummary(id: UUID(), displayName: "Mia", dailyNewCardLimit: 5,
                            dailyReviewLimit: 40, pacingProfile: .normal,
                            dyslexiaMode: false, readAloud: false, reduceMotion: false)
        if let deck = try? decks.createDeck(title: "Math") {
            for (q, a) in [("2 × 3", "6"), ("7 + 5", "12"), ("9 − 4", "5")] {
                if let card = try? decks.addCard(to: deck.id, front: q, back: a, hint: nil) {
                    try? decks.setTagNames(["Math"], forCard: card.id)
                }
            }
            try? decks.setDeck(deck.id, assigned: true, toChild: child.id)
        }
        let model = GameModeViewModel(decks: decks, childRepository: children, study: study)
        model.load()
        return model
    }
}
