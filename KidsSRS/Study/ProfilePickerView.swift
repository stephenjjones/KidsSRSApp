import SwiftUI

/// "Pick your face" launch screen — no passwords for kids (Spec §6.1).
/// Lists the family's persisted `Child` profiles; only the parent zone is gated
/// (§8.1), via the adult challenge presented before entering.
struct ProfilePickerView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: ProfilePickerViewModel
    @State private var showingGate = false
    @State private var rewardsTarget: ChildSummary?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 20)]

    /// Injected by the caller on the main actor (the live store in the app, a
    /// `.sample()` one in previews).
    init(model: ProfilePickerViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Who's studying?")
                .font(.largeTitle.bold())
                .padding(.top, 40)

            if model.children.isEmpty {
                emptyState
            } else {
                profileGrid
            }

            Spacer()

            // Adult gate entry (Spec §8.1) — the parent zone is gated.
            Button {
                showingGate = true
            } label: {
                Label("Parents", systemImage: "lock.fill")
            }
            .padding(.bottom, 24)
            .accessibilityLabel("Parents — opens an adult check")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingGate) {
            adultGate
        }
        .sheet(item: $rewardsTarget, onDismiss: { model.load() }) { child in
            RewardCollectionView(model: RewardCollectionViewModel(childID: child.id,
                                                                  childName: child.displayName))
        }
        .task { model.load() }
    }

    private var profileGrid: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(model.children) { child in
                VStack(spacing: 8) {
                    Button {
                        appState.startStudying(childID: child.id)
                    } label: {
                        VStack(spacing: 12) {
                            ChildAvatar(child: child)
                            Text(child.displayName.isEmpty ? "—" : child.displayName)
                                .font(.title3.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Study as \(child.displayName)")

                    Button { rewardsTarget = child } label: {
                        Label("Rewards", systemImage: "trophy.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(child.displayName)'s rewards")
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No profiles yet", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Ask a grown-up to add a profile in Parents.")
        }
    }

    /// The adult challenge, presented as a dismissible sheet (Spec §8.1).
    private var adultGate: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { showingGate = false }
                Spacer()
            }
            .padding()

            Spacer(minLength: 0)
            AdultGateView {
                showingGate = false
                appState.enterParentZone()
            }
            Spacer(minLength: 0)
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }
}

/// Deterministic default avatar derived from a child's stable id, so the same
/// child always shows the same face across launches (Spec §6.1). Used by
/// `ChildAvatar` as the fallback when the child hasn't equipped a reward avatar.
struct ProfileFace {
    let symbol: String
    let color: Color

    init(id: UUID) {
        let symbols = ["hare.fill", "tortoise.fill", "bird.fill", "cat.fill",
                       "dog.fill", "ladybug.fill", "fish.fill", "pawprint.fill"]
        let palette: [Color] = [.pink, .green, .blue, .orange,
                                .purple, .teal, .red, .indigo]
        // Use the first two bytes of the UUID — stable across processes.
        symbol = symbols[Int(id.uuid.0) % symbols.count]
        color = palette[Int(id.uuid.1) % palette.count]
    }
}

#Preview("With profiles") {
    ProfilePickerView(model: .sample())
        .environmentObject(AppState())
}

#Preview("Empty") {
    ProfilePickerView(
        model: ProfilePickerViewModel(
            repository: ChildRepository(persistence: PersistenceController(inMemory: true))
        )
    )
    .environmentObject(AppState())
}
