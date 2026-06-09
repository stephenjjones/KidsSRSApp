import SwiftUI

/// Per-child deck assignment (Spec §8.2 "which decks are assigned" / §8.3
/// "assignable to one or more children"). A toggle list of all authored decks;
/// flipping a toggle assigns/unassigns that deck to this child. Reached from
/// `ChildDetailView`.
struct AssignDecksView: View {
    @StateObject private var model: AssignDecksViewModel

    init(model: AssignDecksViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if model.decks.isEmpty {
                ContentUnavailableView {
                    Label("No decks yet", systemImage: "rectangle.stack")
                } description: {
                    Text("Create decks under “Author decks”, then assign them here.")
                }
            } else {
                List {
                    Section {
                        ForEach(model.decks) { deck in
                            Toggle(isOn: binding(for: deck)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(deck.displayTitle)
                                            .font(.headline)
                                        if deck.isBundled {
                                            Text("Starter")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.tint.opacity(0.15), in: Capsule())
                                        }
                                    }
                                    Text("\(deck.cardCount) \(deck.cardCount == 1 ? "card" : "cards")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel("\(deck.displayTitle)"
                                                + (deck.isBundled ? ", starter deck" : "")
                                                + ", \(deck.cardCount) "
                                                + (deck.cardCount == 1 ? "card" : "cards"))
                        }
                    } footer: {
                        Text("Assigned decks appear in \(model.childName)'s daily study session.")
                    }
                }
            }
        }
        .navigationTitle("Assigned decks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Something went wrong",
               isPresented: errorPresented,
               presenting: model.errorMessage) { _ in
            Button("OK") { model.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .task { model.load() }
    }

    private func binding(for deck: DeckSummary) -> Binding<Bool> {
        Binding(
            get: { model.isAssigned(deck.id) },
            set: { model.setAssigned(deck.id, $0) }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

/// Drives per-child deck assignment (Spec §8.2/§8.3). Reads all authored decks
/// and this child's assigned set through `DeckRepository`; exposes only value
/// types (§4.1).
@MainActor
final class AssignDecksViewModel: ObservableObject {
    @Published private(set) var decks: [DeckSummary] = []
    @Published private(set) var assignedDeckIDs: Set<UUID> = []
    @Published var errorMessage: String?

    let childID: UUID
    let childName: String
    private let repository: DeckRepository

    init(childID: UUID, childName: String, repository: DeckRepository = DeckRepository()) {
        self.childID = childID
        self.childName = childName
        self.repository = repository
    }

    func load() {
        perform {
            // Bundled starter decks are assignable too (Spec §9.1).
            self.decks = try self.repository.fetchAssignableDecks()
            self.assignedDeckIDs = try self.repository.assignedDeckIDs(forChild: self.childID)
        }
    }

    func isAssigned(_ deckID: UUID) -> Bool { assignedDeckIDs.contains(deckID) }

    func setAssigned(_ deckID: UUID, _ assigned: Bool) {
        // Optimistic update so the toggle responds immediately.
        if assigned { assignedDeckIDs.insert(deckID) } else { assignedDeckIDs.remove(deckID) }
        perform { try self.repository.setDeck(deckID, assigned: assigned, toChild: self.childID) }
        load()
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Preview factory: an in-memory store with a couple of decks, one assigned.
    static func sample() -> AssignDecksViewModel {
        let context = PersistenceController(inMemory: true).container.viewContext
        let decks = DeckRepository(context: context)
        let children = ChildRepository(context: context)
        let child = (try? children.createChild(name: "Mia"))
            ?? ChildSummary(id: UUID(), displayName: "Mia",
                            dailyNewCardLimit: 5, dailyReviewLimit: 40,
                            pacingProfile: .normal,
                            dyslexiaMode: false, readAloud: false, reduceMotion: false)
        let spanish = try? decks.createDeck(title: "Spanish — Animals")
        _ = try? decks.createDeck(title: "Multiplication × 7")
        if let spanish { try? decks.setDeck(spanish.id, assigned: true, toChild: child.id) }

        let model = AssignDecksViewModel(childID: child.id, childName: child.displayName,
                                         repository: decks)
        model.load()
        return model
    }
}

#Preview {
    NavigationStack {
        AssignDecksView(model: .sample())
    }
}
