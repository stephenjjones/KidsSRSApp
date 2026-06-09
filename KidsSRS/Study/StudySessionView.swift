import SwiftUI
import KidsSRSCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The core study screen: predict-then-verify (Spec §6.3), with per-child
/// accessibility applied (Spec §11): read-aloud (TTS), dyslexia-friendly text,
/// and reduce-motion.
struct StudySessionView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model: StudyViewModel
    @StateObject private var speech = SpeechReader()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// Injected by the caller on the main actor (the live store in the app, a
    /// `.sample()`-backed one in previews).
    init(model: StudyViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    /// Per-child reduce-motion OR the OS setting (Spec §11: bound to the system
    /// setting, overridable per child).
    private var reduceMotion: Bool {
        model.preferences.reduceMotion || systemReduceMotion
    }

    var body: some View {
        VStack(spacing: 24) {
            header

            switch model.phase {
            case .loading:
                Spacer()
                ProgressView("Getting today's cards…")
            case .predict, .reveal:
                if let card = model.current {
                    cardView(card)
                }
            case .finished:
                SessionCompleteView(correct: model.correctCount,
                                    total: model.queue.count,
                                    rewards: model.rewardSummary,
                                    reduceMotion: reduceMotion) {
                    appState.backToProfiles()
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .task { model.load() }
        .onChange(of: model.phase) { _, newPhase in autoReadIfNeeded(newPhase) }
        .onDisappear { speech.stop() }
        .alert("Something went wrong",
               isPresented: errorPresented,
               presenting: model.errorMessage) { _ in
            Button("OK") { model.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }

    private var header: some View {
        HStack {
            Button {
                appState.backToProfiles()
            } label: {
                Image(systemName: "house.fill")
            }
            .accessibilityLabel("Back to profiles")

            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
        }
    }

    @ViewBuilder
    private func cardView(_ card: StudyViewModel.Card) -> some View {
        VStack(spacing: 20) {
            // Prompt (front): image and/or text (Spec §6.3).
            VStack(spacing: 14) {
                if let data = card.frontImage, let image = Image(cardImageData: data) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .accessibilityLabel("Card image")
                }
                if !card.front.isEmpty {
                    Text(card.front)
                        .dyslexiaText(.largeTitle, enabled: model.preferences.dyslexiaMode)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))

            // Read-aloud is always available, not just when auto-read is on
            // (Spec §6.3 "read-aloud available" / §11).
            Button {
                speakCurrent()
            } label: {
                Label("Read aloud", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Read this card aloud")

            switch model.phase {
            case .predict:
                // Step 2: commit a prediction BEFORE revealing (Spec §6.3).
                VStack(spacing: 12) {
                    Text("Do you know it?").font(.headline)
                    HStack(spacing: 16) {
                        bigButton("I think I know it", systemImage: "lightbulb.fill") {
                            model.choosePrediction(.knowIt)
                        }
                        bigButton("Not sure", systemImage: "questionmark.circle.fill") {
                            model.choosePrediction(.notSure)
                        }
                    }
                }
            case .reveal:
                // Step 3–5: answer (image and/or text) + two-button self-rating.
                VStack(spacing: 12) {
                    if let data = card.backImage, let image = Image(cardImageData: data) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .accessibilityLabel("Answer image")
                    }
                    if !card.back.isEmpty {
                        Text(card.back)
                            .dyslexiaText(.title2, enabled: model.preferences.dyslexiaMode)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                HStack(spacing: 16) {
                    // Color-blind safe: icon + shape + text, not color alone (§11).
                    bigButton("Got it!", systemImage: "checkmark.circle.fill") {
                        model.grade(.gotIt)
                    }
                    bigButton("Missed it", systemImage: "arrow.counterclockwise.circle.fill") {
                        model.grade(.missedIt)
                    }
                }
            case .loading, .finished:
                EmptyView()
            }

            if let message = model.coachingMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }

    private func bigButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(title)
    }

    // MARK: Read-aloud (Spec §11)

    /// Speak the text currently in front of the child: the prompt while
    /// predicting, the answer once revealed.
    private func speakCurrent() {
        guard let card = model.current else { return }
        switch model.phase {
        case .predict: speech.speak(card.front)
        case .reveal:  speech.speak(card.back)
        case .loading, .finished: break
        }
    }

    /// Auto-read on each phase change when the child's `readAloud` pref is on.
    private func autoReadIfNeeded(_ phase: StudyViewModel.Phase) {
        guard model.preferences.readAloud else { return }
        switch phase {
        case .predict, .reveal: speakCurrent()
        case .loading, .finished: speech.stop()
        }
    }
}

struct SessionCompleteView: View {
    let correct: Int
    let total: Int
    var rewards: RewardSummary? = nil
    var reduceMotion: Bool = false
    let onDone: () -> Void

    /// No cards were due/new today — a calm "all caught up", not a failure state.
    private var isEmpty: Bool { total == 0 }
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isEmpty ? "checkmark.seal.fill" : "star.fill")
                .font(.system(size: 64))
                .foregroundStyle(isEmpty ? .green : .yellow)
                .symbolEffect(.bounce, options: .nonRepeating, value: bounce)
                .onAppear { if !reduceMotion { bounce.toggle() } }
            Text(isEmpty ? "All caught up!" : "You're done!")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(isEmpty
                 ? "Nothing to study right now — come back later."
                 : "\(correct) of \(total) correct")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let rewards {
                RewardSummaryView(summary: rewards, reduceMotion: reduceMotion)
                    .padding(.top, 4)
            }

            Button("Finish", action: onDone)
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
    }
}

/// Deterministic reward feedback at session end (Spec §9.3): celebrate any new
/// unlock, always show the next one, and display the collection so far.
private struct RewardSummaryView: View {
    let summary: RewardSummary
    let reduceMotion: Bool
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 14) {
            ForEach(summary.newlyUnlocked) { item in
                VStack(spacing: 6) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .symbolEffect(.bounce, options: .nonRepeating, value: celebrate)
                    Text("New! You unlocked the \(item.name)")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("New reward unlocked: \(item.name)")
            }

            if let next = summary.nextMilestone {
                ProgressView(value: summary.progressToNext) {
                    Label("\(summary.sessionsUntilNext) more to unlock \(next.item.name)",
                          systemImage: next.item.symbol)
                        .font(.subheadline)
                }
                .frame(maxWidth: 320)
            } else if !summary.unlockedItems.isEmpty {
                Text("You've collected them all! 🎉")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !summary.unlockedItems.isEmpty {
                HStack(spacing: 12) {
                    ForEach(summary.unlockedItems) { item in
                        RewardItemAvatar(item: item, size: 44)
                            .accessibilityLabel(item.name)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Your collection")
            }
        }
        .onAppear { if !reduceMotion { celebrate.toggle() } }
    }
}

extension Image {
    /// Build a SwiftUI `Image` from stored card image `Data` (Spec §5),
    /// cross-platform. Returns nil if the data isn't a decodable image.
    init?(cardImageData data: Data) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        return nil
        #endif
    }
}

#Preview("Session") {
    StudySessionView(model: .sample())
        .environmentObject(AppState())
}
