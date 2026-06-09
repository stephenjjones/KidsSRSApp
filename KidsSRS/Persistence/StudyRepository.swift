import CoreData
import KidsSRSCore

// MARK: - UI-facing value types

/// One studyable card for a session: display content + its scheduling state.
/// Spec §4.1: the study UI/view model sees this value, never `CardMO`/`CardStateMO`.
struct StudyCard: Identifiable, Equatable {
    /// Stable card id (Spec §5).
    let id: UUID
    var front: String
    var back: String
    var hint: String?
    /// Optional front/back images (Spec §5), downsized JPEG data.
    var frontImage: Data?
    var backImage: Data?
    /// The pure scheduling state (Spec §7) for this child × card.
    var state: SchedulerState
}

/// Today's bounded plan for a child: the ordered queue, the child's pacing (so
/// the caller can build the right `Scheduler`), and the child's accessibility
/// preferences (Spec §11) that the study screen applies.
struct StudyPlan: Equatable {
    var cards: [StudyCard]
    var pacingProfile: PacingProfile
    var preferences: StudyPreferences
}

/// Per-child accessibility preferences consumed by the study flow (Spec §11).
struct StudyPreferences: Equatable {
    var dyslexiaMode: Bool
    var readAloud: Bool
    var reduceMotion: Bool

    static let `default` = StudyPreferences(dyslexiaMode: false,
                                            readAloud: false,
                                            reduceMotion: false)
}

/// One drawable Game Mode card (Spec §14.5): display content plus its content
/// `kind`, so the UI can present text questions (and, later, video). Like
/// `StudyCard`, the view never sees `CardMO`.
struct GameDrawCard: Identifiable, Equatable {
    let id: UUID
    var front: String
    var back: String
    var hint: String?
    /// `text` / `image` / `video` (Spec §14.2). Board-game draws are text by default.
    var kind: String
}

/// Errors surfaced by `StudyRepository`.
enum StudyRepositoryError: LocalizedError {
    case childNotFound(UUID)
    case cardNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .childNotFound: return "That child profile could no longer be found."
        case .cardNotFound: return "That card could no longer be found."
        }
    }
}

// MARK: - Repository

/// The Core Data boundary for the study loop (Spec §6.2 / §7).
///
/// Bridges the persisted store to the pure `KidsSRSCore` scheduler: it gathers a
/// child's assigned-deck cards with their `CardState`, composes a bounded daily
/// session via `SessionPlanner`, and writes each post-review `SchedulerState`
/// back to the store. `CardState` rows are materialized **lazily** — only once a
/// card is actually graded — so unstudied cards don't accumulate empty state.
final class StudyRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    convenience init(persistence: PersistenceController = .shared) {
        self.init(context: persistence.container.viewContext)
    }

    static var preview: StudyRepository {
        StudyRepository(persistence: .preview)
    }

    // MARK: Session composition

    /// Build today's bounded session for a child (Spec §6.2: reviews first, then
    /// new cards; both capped by the child's parent-set limits, §7.4).
    func loadSession(forChild childID: UUID, now: Date) throws -> StudyPlan {
        let child = try childMO(id: childID)
        let pacing = PacingProfile(rawValue: child.pacingProfile ?? "") ?? .normal
        let preferences = StudyPreferences(dyslexiaMode: child.dyslexiaMode,
                                           readAloud: child.readAloud,
                                           reduceMotion: child.reduceMotion)
        let limits = SessionPlanner.Limits(
            dailyReviewLimit: Int(child.dailyReviewLimit),
            newCardsPerDay: Int(child.dailyNewCardLimit)
        )

        // Assigned decks → their cards. A card belongs to one deck, so no dupes.
        // Sorted (deck title, card order) for a deterministic session order.
        // Video (song) cards are excluded — they review via Song Review (§14.3),
        // not the predict-then-verify flashcard flow.
        let decks = (child.assignedDecks as? Set<DeckMO>) ?? []
        let cards = decks
            .flatMap { ($0.cards as? Set<CardMO>) ?? [] }
            .filter { !$0.isDeleted && $0.kind != "video" }
            .sorted(by: Self.cardOrder)

        let states = try cardStateMap(forChild: childID)

        var byID: [UUID: CardMO] = [:]
        var candidates: [SessionPlanner.Item<UUID>] = []
        for card in cards {
            guard let cardID = card.id else { continue }
            byID[cardID] = card
            let state = states[cardID].map(Self.schedulerState(from:)) ?? .makeNew()
            candidates.append(SessionPlanner.Item(id: cardID, state: state))
        }

        let plannedIDs = SessionPlanner().plan(candidates: candidates, limits: limits, now: now)

        let queue: [StudyCard] = plannedIDs.compactMap { cardID in
            guard let card = byID[cardID] else { return nil }
            let state = states[cardID].map(Self.schedulerState(from:)) ?? .makeNew()
            return StudyCard(id: cardID,
                             front: card.frontText ?? "",
                             back: card.backText ?? "",
                             hint: card.hint,
                             frontImage: card.frontImage,
                             backImage: card.backImage,
                             state: state)
        }
        return StudyPlan(cards: queue, pacingProfile: pacing, preferences: preferences)
    }

    // MARK: Game Mode draw (Spec §14.5)

    /// Build an individualized Game Mode draw pool for a child: cards in the
    /// child's assigned decks, filtered to the chosen categories (`tagIDs`;
    /// **empty ⇒ no category filter**), ranked by `GameDrawPlanner` so the cards
    /// the child knows *least* well come first. The caller draws from the front
    /// of the list (or samples by rank). Reuses the same assigned-deck +
    /// `CardState` gathering as the daily study session.
    func loadGameDraw(forChild childID: UUID, tagIDs: Set<UUID>, now: Date) throws -> [GameDrawCard] {
        let child = try childMO(id: childID)

        // Video (song) cards belong to Song Review, not the board-game draw.
        let decks = (child.assignedDecks as? Set<DeckMO>) ?? []
        var cards = decks
            .flatMap { ($0.cards as? Set<CardMO>) ?? [] }
            .filter { !$0.isDeleted && $0.kind != "video" }

        // Category filter: keep cards carrying at least one of the chosen tags.
        if !tagIDs.isEmpty {
            cards = cards.filter { card in
                let tags = (card.tags as? Set<TagMO>) ?? []
                return tags.contains { $0.id.map(tagIDs.contains) ?? false }
            }
        }

        let states = try cardStateMap(forChild: childID)
        var byID: [UUID: CardMO] = [:]
        var candidates: [SessionPlanner.Item<UUID>] = []
        for card in cards {
            guard let cardID = card.id else { continue }
            byID[cardID] = card
            let state = states[cardID].map(Self.schedulerState(from:)) ?? .makeNew()
            candidates.append(SessionPlanner.Item(id: cardID, state: state))
        }

        let rankedIDs = GameDrawPlanner().ranked(candidates: candidates, now: now)
        return rankedIDs.compactMap { cardID in
            guard let card = byID[cardID] else { return nil }
            return GameDrawCard(id: cardID,
                                front: card.frontText ?? "",
                                back: card.backText ?? "",
                                hint: card.hint,
                                kind: card.kind ?? "text")
        }
    }

    // MARK: Smart Song Review (cross-playlist, Spec §14.3)

    /// Build a spaced-repetition Song Review for the selected children: every
    /// song (across **all** playlists) that is due or new for at least one chosen
    /// child, ranked by `SongReviewPlanner`. Empty selection ⇒ no songs.
    func generateSongReview(forChildren childIDs: Set<UUID>, now: Date,
                            newSongLimit: Int = 10) throws -> [PlaylistSong] {
        guard !childIDs.isEmpty else { return [] }
        let selected = Array(childIDs)

        // All song (video) cards across every playlist.
        let cardRequest = NSFetchRequest<CardMO>(entityName: "Card")
        cardRequest.predicate = NSPredicate(format: "kind == %@", "video")
        let songCards = try context.fetch(cardRequest).filter { !$0.isDeleted }

        // The selected children's scheduler state on those songs.
        let stateRequest = NSFetchRequest<CardStateMO>(entityName: "CardState")
        stateRequest.predicate = NSPredicate(format: "card.kind == %@ AND child.id IN %@",
                                             "video", selected.map { $0 as NSUUID })
        var stateMap: [UUID: [UUID: SchedulerState]] = [:] // cardID → childID → state
        for mo in try context.fetch(stateRequest) {
            guard let cardID = mo.card?.id, let childID = mo.child?.id else { continue }
            stateMap[cardID, default: [:]][childID] = Self.schedulerState(from: mo)
        }

        var byID: [UUID: CardMO] = [:]
        var candidates: [SongReviewPlanner.Candidate<UUID>] = []
        for card in songCards {
            guard let cardID = card.id else { continue }
            byID[cardID] = card
            let perChild = stateMap[cardID] ?? [:]
            candidates.append(SongReviewPlanner.Candidate(id: cardID,
                                                          childStates: selected.map { perChild[$0] }))
        }

        let ranked = SongReviewPlanner().plan(candidates: candidates, now: now, newLimit: newSongLimit)
        return ranked.compactMap { id in
            guard let card = byID[id] else { return nil }
            return PlaylistSong(id: id, title: card.frontText ?? "",
                                videoRef: card.videoRef ?? "", hint: card.hint)
        }
    }

    // MARK: Song scoring (parent-led, Spec §14.3 / §14.4)

    /// Apply a parent's 3-level rating for one child on one song and persist the
    /// resulting scheduling state (Spec §14.4). Uses the child's pacing profile
    /// to build the scheduler. Called once per scored child per song.
    func scoreSong(forChild childID: UUID, cardID: UUID, grade: ParentGrade, now: Date) throws {
        try applyAdultGrade(forChild: childID, cardID: cardID, grade: grade, now: now)
    }

    /// Mark a Game Mode draw correct/incorrect for a child (Spec §14.5). Feeds the
    /// scheduler like a review — correct ⇒ advance, incorrect ⇒ lapse — with no
    /// predict-then-verify, so no metacognition flag is recorded.
    func scoreGameDraw(forChild childID: UUID, cardID: UUID, correct: Bool, now: Date) throws {
        try applyAdultGrade(forChild: childID, cardID: cardID,
                            grade: correct ? .knowsIt : .doesntKnowIt, now: now)
    }

    /// Apply an adult/observer grade (no prediction ⇒ no metacognition flag) to a
    /// (child × card) and persist the resulting scheduling state (Spec §14.4).
    private func applyAdultGrade(forChild childID: UUID, cardID: UUID,
                                 grade: ParentGrade, now: Date) throws {
        let child = try childMO(id: childID)
        let pacing = PacingProfile(rawValue: child.pacingProfile ?? "") ?? .normal
        let current = try currentState(forChild: childID, cardID: cardID)
        let next = Scheduler(profile: pacing)
            .apply(ParentReviewInput(grade: grade, reviewedAt: now), to: current)
        try saveState(forChild: childID, cardID: cardID, state: next)
    }

    /// The stored scheduling state for a (child, card), or a fresh one if the
    /// child has never been scored on this card.
    private func currentState(forChild childID: UUID, cardID: UUID) throws -> SchedulerState {
        let request = NSFetchRequest<CardStateMO>(entityName: "CardState")
        request.predicate = NSPredicate(format: "child.id == %@ AND card.id == %@",
                                        childID as NSUUID, cardID as NSUUID)
        request.fetchLimit = 1
        if let mo = try context.fetch(request).first {
            return Self.schedulerState(from: mo)
        }
        return .makeNew()
    }

    // MARK: Persistence of a review

    /// Persist the post-review scheduling state for a (child, card). Creates the
    /// `CardState` row on first review (Spec §5 — keyed on child × card).
    func saveState(forChild childID: UUID, cardID: UUID, state: SchedulerState) throws {
        let cardState = try findOrCreateCardState(childID: childID, cardID: cardID)
        Self.apply(state, to: cardState)
        try save()
    }

    /// Record a completed study session (Spec §8.4 — powers the dashboard).
    func recordSession(forChild childID: UUID,
                       startedAt: Date,
                       endedAt: Date,
                       cardsSeen: Int,
                       cardsCorrect: Int,
                       newIntroduced: Int) throws {
        let child = try childMO(id: childID)
        let log = SessionLogMO(context: context)
        log.id = UUID()
        log.child = child
        log.startedAt = startedAt
        log.endedAt = endedAt
        log.cardsSeen = Int32(cardsSeen)
        log.cardsCorrect = Int32(cardsCorrect)
        log.newIntroduced = Int32(newIntroduced)
        try save()
    }

    // MARK: - Private helpers

    private func childMO(id: UUID) throws -> ChildMO {
        guard let child = try context.fetchFirst(ChildMO.self, entityName: "Child", id: id) else {
            throw StudyRepositoryError.childNotFound(id)
        }
        return child
    }

    /// Existing card states for a child, keyed by card id.
    private func cardStateMap(forChild childID: UUID) throws -> [UUID: CardStateMO] {
        let request = NSFetchRequest<CardStateMO>(entityName: "CardState")
        request.predicate = NSPredicate(format: "child.id == %@", childID as NSUUID)
        var map: [UUID: CardStateMO] = [:]
        for state in try context.fetch(request) {
            if let cardID = state.card?.id { map[cardID] = state }
        }
        return map
    }

    private func findOrCreateCardState(childID: UUID, cardID: UUID) throws -> CardStateMO {
        let request = NSFetchRequest<CardStateMO>(entityName: "CardState")
        request.predicate = NSPredicate(format: "child.id == %@ AND card.id == %@",
                                        childID as NSUUID, cardID as NSUUID)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        let child = try childMO(id: childID)
        guard let card = try context.fetchFirst(CardMO.self, entityName: "Card", id: cardID) else {
            throw StudyRepositoryError.cardNotFound(cardID)
        }
        let state = CardStateMO(context: context)
        state.child = child
        state.card = card
        return state
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    /// Deterministic session ordering: by deck title, then card order.
    private static func cardOrder(_ lhs: CardMO, _ rhs: CardMO) -> Bool {
        let lt = lhs.deck?.title ?? ""
        let rt = rhs.deck?.title ?? ""
        if lt != rt { return lt.localizedCaseInsensitiveCompare(rt) == .orderedAscending }
        return lhs.order < rhs.order
    }

    // MARK: Mapping (defensive — CardState attributes are optional/scalar, Spec §5)

    static func schedulerState(from mo: CardStateMO) -> SchedulerState {
        SchedulerState(
            status: CardStatus(rawValue: mo.status ?? "") ?? .new,
            easeFactor: mo.easeFactor,
            intervalDays: mo.intervalDays,
            repetitions: Int(mo.repetitions),
            lapses: Int(mo.lapses),
            learningStepIndex: mo.learningStepIndex?.intValue,
            dueDate: mo.dueDate ?? .distantPast,
            lastReviewedAt: mo.lastReviewedAt,
            lastConfidenceFlag: mo.lastConfidenceFlag.flatMap { ConfidenceFlag(rawValue: $0) }
        )
    }

    static func apply(_ state: SchedulerState, to mo: CardStateMO) {
        mo.status = state.status.rawValue
        mo.easeFactor = state.easeFactor
        mo.intervalDays = state.intervalDays
        mo.repetitions = Int32(state.repetitions)
        mo.lapses = Int32(state.lapses)
        mo.learningStepIndex = state.learningStepIndex.map { NSNumber(value: $0) }
        mo.dueDate = state.dueDate
        mo.lastReviewedAt = state.lastReviewedAt
        mo.lastConfidenceFlag = state.lastConfidenceFlag?.rawValue
    }
}
