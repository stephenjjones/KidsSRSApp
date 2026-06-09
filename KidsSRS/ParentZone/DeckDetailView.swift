import SwiftUI

/// One deck's card list (Spec §8.3): shows cards in order, tap to edit, an
/// "Add card" button, reorder (EditButton + `.onMove` on iOS, drag on macOS),
/// and delete with confirmation. Pushed from `DeckListView`.
struct DeckDetailView: View {
    @StateObject private var model: DeckDetailViewModel

    @State private var editTarget: CardEditTarget?
    @State private var deleteTarget: CardDraft?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    init(model: DeckDetailViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if model.cards.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .navigationTitle(model.deck.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        #endif
        .toolbar { toolbarContent }
        .sheet(item: $editTarget) { target in
            CardFormView(target: target, allTags: model.allTagNames) { edits in
                switch target {
                case .new:
                    model.addCard(edits)
                case .existing(let card):
                    model.updateCard(id: card.id, edits)
                }
            }
        }
        .confirmationDialog(
            "Delete this card?",
            isPresented: deletePresented,
            titleVisibility: .visible,
            presenting: deleteTarget
        ) { card in
            Button("Delete card", role: .destructive) {
                model.deleteCard(id: card.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently removes the card from this deck.")
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            if !model.cards.isEmpty { EditButton() }
        }
        #endif
        ToolbarItem {
            Button { editTarget = .new } label: {
                Label("Add card", systemImage: "plus")
            }
            .accessibilityLabel("Add card")
        }
    }

    private var cardList: some View {
        List {
            ForEach(model.cards) { card in
                Button { editTarget = .existing(card) } label: {
                    CardRow(card: card)
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteTarget = card } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                #endif
                .contextMenu {
                    Button { editTarget = .existing(card) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { deleteTarget = card } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { model.moveCards(from: $0, to: $1) }

            Section {
                Button { editTarget = .new } label: {
                    Label("Add card", systemImage: "plus")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No cards yet", systemImage: "plus.rectangle.on.rectangle")
        } description: {
            Text("Add the first card to “\(model.deck.displayTitle)”.")
        } actions: {
            Button("Add card") { editTarget = .new }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Presentation bindings

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

/// One row in the card list: front prominent, back secondary, optional hint.
private struct CardRow: View {
    let card: CardDraft

    var body: some View {
        HStack(spacing: 12) {
            if let data = card.frontImage, let image = Image(cardImageData: data) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(frontDisplay)
                    .font(.headline)
                    .lineLimit(2)
                Text(backDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let hint = card.hint, !hint.isEmpty {
                    Label(hint, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !card.tags.isEmpty {
                    Label(card.tags.joined(separator: ", "), systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-tap to edit this card")
    }

    private var frontDisplay: String {
        card.front.isEmpty ? (card.frontImage != nil ? "Image card" : "—") : card.front
    }
    private var backDisplay: String {
        card.back.isEmpty ? (card.backImage != nil ? "Image" : "—") : card.back
    }

    private var accessibilityText: String {
        let frontDesc = card.front.isEmpty ? (card.frontImage != nil ? "image" : "empty") : card.front
        let backDesc = card.back.isEmpty ? (card.backImage != nil ? "image" : "empty") : card.back
        var parts = ["Front, \(frontDesc)", "Back, \(backDesc)"]
        if let hint = card.hint, !hint.isEmpty { parts.append("Hint, \(hint)") }
        if !card.tags.isEmpty { parts.append("Categories, \(card.tags.joined(separator: ", "))") }
        return parts.joined(separator: ". ")
    }
}

#Preview("Cards") {
    NavigationStack {
        DeckDetailView(model: .sample())
    }
}

#Preview("Empty") {
    NavigationStack {
        DeckDetailView(
            model: DeckDetailViewModel(
                deck: DeckSummary(id: UUID(), title: "New deck", cardCount: 0),
                repository: DeckRepository(persistence: PersistenceController(inMemory: true))
            )
        )
    }
}
