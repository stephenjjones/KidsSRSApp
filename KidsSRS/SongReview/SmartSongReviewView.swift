import SwiftUI

/// "Smart Review" (Spec §14.3): pick which kids to review for, then auto-build a
/// spaced-repetition song list — the songs those kids most need, pooled from
/// every playlist — and play it with the normal Song Review scoring.
@MainActor
final class SmartSongReviewViewModel: ObservableObject {
    @Published private(set) var children: [ChildSummary] = []
    @Published private(set) var selectedIDs: Set<UUID> = []
    /// Non-nil once a review has been generated — drives the player.
    @Published private(set) var review: SongReviewViewModel?
    /// True when generation found nothing due/new for the selection.
    @Published private(set) var generatedEmpty = false
    @Published var errorMessage: String?

    private let childRepository: ChildRepository
    private let study: StudyRepository
    private let now: () -> Date

    init(childRepository: ChildRepository = ChildRepository(),
         study: StudyRepository = StudyRepository(),
         now: @escaping () -> Date = Date.init) {
        self.childRepository = childRepository
        self.study = study
        self.now = now
    }

    var canBuild: Bool { !selectedIDs.isEmpty }

    func load() {
        do {
            children = try childRepository.fetchChildren()
        } catch {
            errorMessage = error.localizedDescription
        }
        if selectedIDs.isEmpty { selectedIDs = Set(children.map(\.id)) } // default: everyone
    }

    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        generatedEmpty = false
    }

    func build() {
        generatedEmpty = false
        do {
            let songs = try study.generateSongReview(forChildren: selectedIDs, now: now())
            if songs.isEmpty {
                generatedEmpty = true
            } else {
                review = SongReviewViewModel(
                    source: .generated(songs: songs, childIDs: Array(selectedIDs)),
                    childRepository: childRepository, study: study, now: now)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func sample() -> SmartSongReviewViewModel {
        let persistence = PersistenceController(inMemory: true)
        let children = ChildRepository(persistence: persistence)
        let decks = DeckRepository(persistence: persistence)
        let study = StudyRepository(persistence: persistence)
        let mia = try? children.createChild(name: "Mia")
        _ = try? children.createChild(name: "Theo")
        if let deck = try? decks.createDeck(title: "Songs") {
            _ = try? decks.addVideoCard(to: deck.id, title: "Days of the Week",
                                        youTube: "youtu.be/36n93jvjkDs", hint: nil)
            _ = try? decks.addVideoCard(to: deck.id, title: "Count to 100",
                                        youTube: "youtu.be/0VLxWIHRD4E", hint: nil)
        }
        _ = mia
        let model = SmartSongReviewViewModel(childRepository: children, study: study)
        model.load()
        return model
    }
}

struct SmartSongReviewView: View {
    @StateObject private var model: SmartSongReviewViewModel

    init(model: SmartSongReviewViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if let review = model.review {
                SongReviewView(model: review)
            } else {
                setup
            }
        }
        .navigationTitle("Smart Review")
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

    private var setup: some View {
        Form {
            Section {
                if model.children.isEmpty {
                    Text("Add children in the parent zone first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.children) { child in
                        let on = model.selectedIDs.contains(child.id)
                        Button { model.toggle(child.id) } label: {
                            HStack {
                                Text(child.displayName.isEmpty ? "Unnamed" : child.displayName)
                                Spacer()
                                if on { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
            } header: {
                Text("Review for")
            } footer: {
                Text("Builds a review of the songs these kids most need to practice, pulled from every playlist.")
            }

            Section {
                Button { model.build() } label: {
                    Label("Build review", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canBuild)

                if model.generatedEmpty {
                    Label("Nothing's due right now — everyone's caught up. 🎉", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

#Preview {
    NavigationStack { SmartSongReviewView(model: .sample()) }
}
