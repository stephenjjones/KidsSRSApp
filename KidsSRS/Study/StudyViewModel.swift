import Foundation
import KidsSRSCore

/// Drives one study session (Spec §6.2–§6.5), bridging the UI to the pure
/// `KidsSRSCore` scheduler **and** the persisted store.
///
/// The session queue is composed from the child's assigned-deck cards + their
/// `CardState` (via `StudyRepository`), and every grade is written back so
/// progress survives relaunch and syncs (Spec §5). The predict-then-verify flow
/// itself is unchanged; only the data is now real.
@MainActor
final class StudyViewModel: ObservableObject {

    /// One studyable card (display content + its scheduling state).
    struct Card: Identifiable, Equatable {
        let id: UUID
        var front: String
        var back: String
        var hint: String?
        var frontImage: Data?
        var backImage: Data?
        var state: SchedulerState
    }

    /// The phases of the predict-then-verify flow (Spec §6.3).
    enum Phase: Equatable {
        case loading      // fetching today's queue from the store
        case predict      // 1–2: show prompt, child commits a confidence prediction
        case reveal       // 3: answer shown, child taps Got it / Missed it
        case finished     // 6.5: session complete (or nothing due)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var queue: [Card] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var prediction: Prediction?
    /// Coaching message derived from the metacognition flag (Spec §6.4).
    @Published private(set) var coachingMessage: String?
    @Published private(set) var correctCount = 0
    /// The child's accessibility preferences for this session (Spec §11).
    @Published private(set) var preferences: StudyPreferences = .default
    /// Reward state to display at session end (Spec §9.3); `nil` until loaded.
    @Published private(set) var rewardSummary: RewardSummary?
    @Published var errorMessage: String?

    private let childID: UUID
    private let repository: StudyRepository
    private let rewards: RewardRepository
    private let clock: () -> Date
    /// Built from the child's pacing profile when the session loads (Spec §7.3).
    private var scheduler = Scheduler(profile: .normal)
    /// Session bookkeeping for the dashboard log (Spec §8.4).
    private var sessionStartedAt: Date?
    private var newIntroducedCount = 0

    init(childID: UUID,
         repository: StudyRepository = StudyRepository(),
         rewards: RewardRepository = RewardRepository(),
         clock: @escaping () -> Date = Date.init) {
        self.childID = childID
        self.repository = repository
        self.rewards = rewards
        self.clock = clock
    }

    var current: Card? { queue.indices.contains(index) ? queue[index] : nil }
    var progress: Double {
        queue.isEmpty ? 1 : Double(index) / Double(queue.count)
    }

    // MARK: - Loading

    /// Compose today's bounded session for the child (Spec §6.2).
    func load() {
        do {
            let plan = try repository.loadSession(forChild: childID, now: clock())
            scheduler = Scheduler(profile: plan.pacingProfile)
            preferences = plan.preferences
            queue = plan.cards.map {
                Card(id: $0.id, front: $0.front, back: $0.back, hint: $0.hint,
                     frontImage: $0.frontImage, backImage: $0.backImage, state: $0.state)
            }
            index = 0
            correctCount = 0
            prediction = nil
            coachingMessage = nil
            newIntroducedCount = queue.filter { $0.state.status == .new }.count
            sessionStartedAt = queue.isEmpty ? nil : clock()
            // Current reward state, so the end/caught-up screen can show the
            // collection and next unlock (Spec §9.3).
            rewardSummary = try? rewards.summary(forChild: childID)
            phase = queue.isEmpty ? .finished : .predict
        } catch {
            errorMessage = error.localizedDescription
            queue = []
            phase = .finished
        }
    }

    // MARK: - Flow

    /// Step 2: child commits a prediction *before* the reveal.
    func choosePrediction(_ p: Prediction) {
        guard phase == .predict else { return }
        prediction = p
        phase = .reveal
    }

    /// Steps 4–5: child self-rates after seeing the answer; we schedule the card
    /// and persist the new state (Spec §5).
    func grade(_ grade: Grade) {
        guard phase == .reveal, let prediction, var card = current else { return }

        let review = ReviewInput(grade: grade, prediction: prediction, reviewedAt: clock())
        card.state = scheduler.apply(review, to: card.state)
        queue[index] = card

        if grade == .gotIt { correctCount += 1 }
        coachingMessage = Self.coaching(for: card.state.lastConfidenceFlag)

        do {
            try repository.saveState(forChild: childID, cardID: card.id, state: card.state)
        } catch {
            errorMessage = error.localizedDescription
        }

        advance()
    }

    private func advance() {
        prediction = nil
        if index + 1 < queue.count {
            index += 1
            phase = .predict
        } else {
            phase = .finished
            recordSession()
        }
    }

    /// Log the just-finished session for the parent dashboard (Spec §8.4).
    /// Only real, completed sessions are logged (guarded against double-record).
    private func recordSession() {
        guard let startedAt = sessionStartedAt, !queue.isEmpty else { return }
        sessionStartedAt = nil
        do {
            try repository.recordSession(forChild: childID,
                                         startedAt: startedAt,
                                         endedAt: clock(),
                                         cardsSeen: queue.count,
                                         cardsCorrect: correctCount,
                                         newIntroduced: newIntroducedCount)
            // Advance the deterministic reward ladder for this completed session
            // and surface any new unlock for the celebration (Spec §9.3).
            rewardSummary = try rewards.recordCompletedSession(forChild: childID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Spec §6.4: flag-only metacognition coaching (never affects scheduling).
    static func coaching(for flag: ConfidenceFlag?) -> String? {
        switch flag {
        case .overConfident:  return "Tricky one! Let's see it again soon."
        case .underConfident: return "You knew more than you thought! 🎉"
        case .calibrated, .none: return nil
        }
    }

    /// Preview/demo factory: an in-memory store seeded with a child + an assigned
    /// deck so the flow is runnable without the live store.
    static func sample() -> StudyViewModel {
        let context = PersistenceController(inMemory: true).container.viewContext
        let decks = DeckRepository(context: context)
        let children = ChildRepository(context: context)
        let child = try? children.createChild(name: "Mia")
        if let child, let deck = try? decks.createDeck(title: "Sample") {
            _ = try? decks.addCard(to: deck.id, front: "2 × 6", back: "12", hint: nil)
            _ = try? decks.addCard(to: deck.id, front: "Capital of France", back: "Paris", hint: nil)
            _ = try? decks.addCard(to: deck.id, front: "\"their\" vs \"there\"",
                                   back: "their = belonging; there = place", hint: nil)
            try? decks.setDeck(deck.id, assigned: true, toChild: child.id)
        }
        let model = StudyViewModel(childID: child?.id ?? UUID(),
                                   repository: StudyRepository(context: context),
                                   rewards: RewardRepository(context: context))
        model.load()
        return model
    }
}
