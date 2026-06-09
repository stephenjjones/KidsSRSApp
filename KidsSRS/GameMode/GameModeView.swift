import SwiftUI

/// Game Mode (Spec §14.5): set up a child + categories, then draw individualized
/// cards to replace a board game's question cards. Reveal the answer, optionally
/// mark right/wrong. Reached from the parent zone.
struct GameModeView: View {
    @StateObject private var model: GameModeViewModel

    init(model: GameModeViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        Group {
            if model.isPlaying { drawView } else { setupView }
        }
        .navigationTitle("Game Mode")
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

    // MARK: Setup

    private var setupView: some View {
        Form {
            Section("Player") {
                if model.children.isEmpty {
                    Text("Add a child in the parent zone first.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Child", selection: $model.selectedChildID) {
                        ForEach(model.children) { child in
                            Text(child.displayName.isEmpty ? "Unnamed" : child.displayName)
                                .tag(Optional(child.id))
                        }
                    }
                }
            }

            Section {
                if model.allTags.isEmpty {
                    Text("No categories yet. Tag some cards to filter by category.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.allTags) { tag in
                        Button { model.toggleTag(tag.id) } label: {
                            HStack {
                                Text(tag.name)
                                Spacer()
                                if model.selectedTagIDs.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.selectedTagIDs.contains(tag.id) ? [.isSelected] : [])
                    }
                }
            } header: {
                Text("Categories")
            } footer: {
                Text(model.selectedTagIDs.isEmpty
                     ? "No categories selected — draws from all of this child's cards."
                     : "Draws only from the selected categories.")
            }

            Section {
                Button { model.start() } label: {
                    Label("Start game", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)
            }
        }
    }

    // MARK: Playing

    private var drawView: some View {
        VStack(spacing: 20) {
            Text("\(model.selectedChildName)'s card")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let card = model.current {
                cardView(card)
                Spacer()
                controls
            } else {
                Spacer()
                ContentUnavailableView("No cards to draw",
                                       systemImage: "rectangle.on.rectangle.slash",
                                       description: Text("This child has no cards in the chosen categories."))
                Spacer()
            }

            Button(role: .cancel) { model.endGame() } label: {
                Label("End game", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private func cardView(_ card: GameDrawCard) -> some View {
        let dyslexia = model.selectedChild?.dyslexiaMode ?? false
        return VStack(spacing: 16) {
            Text(card.front.isEmpty ? "—" : card.front)
                .dyslexiaText(.title, enabled: dyslexia)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            if model.isRevealed {
                Divider()
                Text(card.back.isEmpty ? "—" : card.back)
                    .dyslexiaText(.title2, enabled: dyslexia)
                    .multilineTextAlignment(.center)
                if let hint = card.hint, !hint.isEmpty {
                    Label(hint, systemImage: "lightbulb")
                        .dyslexiaText(.callout, enabled: dyslexia)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel(card))
    }

    private func cardAccessibilityLabel(_ card: GameDrawCard) -> String {
        var parts = ["Card. \(card.front.isEmpty ? "no prompt" : card.front)"]
        if model.isRevealed {
            parts.append("Answer, \(card.back.isEmpty ? "none" : card.back)")
            if let hint = card.hint, !hint.isEmpty { parts.append("Hint, \(hint)") }
        }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder
    private var controls: some View {
        if model.isRevealed {
            HStack(spacing: 12) {
                Button { model.score(correct: false) } label: {
                    Label("Missed it", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button { model.score(correct: true) } label: {
                    Label("Got it", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
            Button { model.skip() } label: {
                Label("Skip — don't score", systemImage: "forward.fill")
            }
            .buttonStyle(.bordered)
        } else {
            Button { model.reveal() } label: {
                Label("Reveal answer", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

#Preview("Setup") {
    NavigationStack { GameModeView(model: .sample()) }
}
