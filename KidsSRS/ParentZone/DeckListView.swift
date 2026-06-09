import SwiftUI

/// Parent deck list — the top level of the deck-authoring flow (Spec §8.3).
///
/// Reached from `ParentDashboardView` → "Author decks", inside the adult-gated
/// parent zone (§8.1). Lists the parent's `parentAuthored` decks; supports
/// create / rename / delete, and drills into a deck's cards.
struct DeckListView: View {
    @StateObject private var model: DeckEditorViewModel

    @State private var showingNewDeck = false
    @State private var newDeckTitle = ""
    @State private var renameTarget: DeckSummary?
    @State private var renameTitle = ""
    @State private var deleteTarget: DeckSummary?

    /// Inject the deck-list view model (the live store in the app, a `.sample()`
    /// or in-memory one in previews). Constructed by the caller on the main actor.
    init(model: DeckEditorViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if model.decks.isEmpty {
                emptyState
            } else {
                deckList
            }
        }
        .navigationTitle("Author decks")
        .toolbar {
            ToolbarItem {
                Button { presentNewDeck() } label: {
                    Label("New deck", systemImage: "plus")
                }
                .accessibilityLabel("New deck")
            }
        }
        .alert("New deck", isPresented: $showingNewDeck) {
            TextField("Deck title", text: $newDeckTitle)
            Button("Create") { _ = model.createDeck(title: newDeckTitle) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name this deck — for example “Spanish — Animals”.")
        }
        .alert("Rename deck", isPresented: renamePresented) {
            TextField("Deck title", text: $renameTitle)
            Button("Save") {
                if let renameTarget {
                    model.renameDeck(id: renameTarget.id, title: renameTitle)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this deck?",
            isPresented: deletePresented,
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { deck in
            Button("Delete “\(deck.displayTitle)”", role: .destructive) {
                model.deleteDeck(id: deck.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { deck in
            Text("This permanently removes the deck and its \(deck.cardCount) "
                 + (deck.cardCount == 1 ? "card." : "cards."))
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

    // MARK: Subviews

    private var deckList: some View {
        List {
            ForEach(model.decks) { deck in
                NavigationLink {
                    DeckDetailView(model: model.makeDetailViewModel(for: deck))
                } label: {
                    DeckRow(deck: deck)
                }
                #if os(iOS)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteTarget = deck } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { presentRename(deck) } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                #endif
                .contextMenu {
                    Button { presentRename(deck) } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) { deleteTarget = deck } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No decks yet", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Create a deck to start adding flashcards for your child to study.")
        } actions: {
            Button("New deck") { presentNewDeck() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Actions

    private func presentNewDeck() {
        newDeckTitle = ""
        showingNewDeck = true
    }

    private func presentRename(_ deck: DeckSummary) {
        renameTitle = deck.title
        renameTarget = deck
    }

    // MARK: Presentation bindings

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

/// One row in the deck list: title + card count.
private struct DeckRow: View {
    let deck: DeckSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(.tint)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.displayTitle)
                    .font(.headline)
                Text("\(deck.cardCount) \(deck.cardCount == 1 ? "card" : "cards")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deck.displayTitle), \(deck.cardCount) "
                            + (deck.cardCount == 1 ? "card" : "cards"))
    }
}

extension DeckSummary {
    /// A non-empty title for display, falling back when a deck has no title.
    var displayTitle: String { title.isEmpty ? "Untitled deck" : title }
}

#Preview("Decks") {
    NavigationStack {
        DeckListView(model: .sample())
    }
}

#Preview("Empty") {
    NavigationStack {
        DeckListView(
            model: DeckEditorViewModel(
                repository: DeckRepository(persistence: PersistenceController(inMemory: true))
            )
        )
    }
}
