import SwiftUI
import KidsSRSCore

/// A parent-led Song Review session (Spec §14.3): the playlist plays on-screen
/// and the parent rates each child per song with the 3-level parent grade
/// (§14.4). Color is never the only signal — each grade pairs a color with an
/// icon + label (Spec §11).
struct SongReviewView: View {
    @StateObject private var model: SongReviewViewModel
    /// Video chokepoint: no `YouTubePlayerView` is built unless consent is
    /// granted (Spec §14.1 — "before any video loads").
    @StateObject private var consent: VideoConsentStore
    @Environment(\.dismiss) private var dismiss

    init(model: SongReviewViewModel, consent: VideoConsentStore = VideoConsentStore()) {
        _model = StateObject(wrappedValue: model)
        _consent = StateObject(wrappedValue: consent)
    }

    var body: some View {
        Group {
            if !consent.isGranted {
                consentGate
            } else if model.songs.isEmpty {
                ContentUnavailableView("No songs in this playlist",
                                       systemImage: "music.note",
                                       description: Text("Add songs before starting a review."))
            } else if model.isFinished {
                finishedView
            } else {
                content
            }
        }
        .navigationTitle("Song Review")
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

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let song = model.currentSong {
                    YouTubePlayerView(videoID: song.videoRef,
                                      onEnded: { model.songDidEnd() },
                                      onError: { model.reportPlayerError(code: $0) })
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        // Orient VoiceOver to the player region while keeping the
                        // embedded player's own controls reachable (Spec §11).
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Video player")

                    Text(song.title.isEmpty ? "Untitled song" : song.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)

                    if let note = model.playerNote {
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }

                transport
                Divider()
                if model.children.isEmpty {
                    Text("Add children in the parent zone to score them.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    presence
                    Divider()
                    scoring
                }
            }
            .padding()
        }
    }

    /// Shown instead of the player until a parent consents (Spec §14.1).
    private var consentGate: some View {
        ScrollView {
            VideoConsentView { consent.grant() }
                .padding()
                .frame(maxWidth: .infinity)
        }
    }

    private var finishedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("All done!")
                .font(.largeTitle.bold())
            Text("You reviewed \(model.songs.count) \(model.songs.count == 1 ? "song" : "songs").")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { model.restart() } label: {
                    Label("Play again", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                Button { dismiss() } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Who's here?" — toggle which children are in the room (Spec §14.3).
    private var presence: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who's here?")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.children) { child in
                        let isHere = model.presentChildIDs.contains(child.id)
                        let name = child.displayName.isEmpty ? "Unnamed" : child.displayName
                        Button { model.togglePresence(child.id) } label: {
                            Label(name, systemImage: isHere ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(isHere ? .accentColor : .secondary)
                        .accessibilityLabel("\(name), \(isHere ? "here" : "not here")")
                        .accessibilityAddTraits(isHere ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transport: some View {
        HStack {
            Button { model.goPrevious() } label: {
                Label("Previous", systemImage: "backward.fill")
            }
            .disabled(!model.hasPrevious)

            Spacer()
            Text(model.positionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()

            Button { model.goNext() } label: {
                Label("Next", systemImage: "forward.fill")
            }
            .disabled(!model.hasNext)
        }
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
    }

    private var scoring: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How well does each child know this song?")
                .font(.headline)
            if model.presentChildren.isEmpty {
                Text("No one's marked here — pick who's present above.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.presentChildren) { child in
                VStack(alignment: .leading, spacing: 6) {
                    Text(child.displayName.isEmpty ? "Unnamed" : child.displayName)
                        .font(.subheadline.bold())
                    HStack(spacing: 8) {
                        ForEach(ParentGrade.allCases, id: \.self) { grade in
                            ScoreButton(grade: grade,
                                        isSelected: model.selection[child.id] == grade) {
                                model.grade(grade, forChild: child.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }
}

/// One 3-level grade button — icon + label + color, so the rating is never
/// conveyed by color alone (Spec §11).
private struct ScoreButton: View {
    let grade: ParentGrade
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: grade.symbolName)
                    .imageScale(.large)
                Text(grade.shortLabel)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(grade.tint)
        .background(isSelected ? grade.tint.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(grade.tint, lineWidth: isSelected ? 2 : 0)
        }
        .accessibilityLabel(grade.fullLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private extension ParentGrade {
    var fullLabel: String {
        switch self {
        case .doesntKnowIt: return "Doesn't know it"
        case .gettingThere: return "Getting there"
        case .knowsIt:      return "Knows it"
        }
    }
    var shortLabel: String {
        switch self {
        case .doesntKnowIt: return "Doesn't\nknow it"
        case .gettingThere: return "Getting\nthere"
        case .knowsIt:      return "Knows it"
        }
    }
    var symbolName: String {
        switch self {
        case .doesntKnowIt: return "xmark.circle.fill"
        case .gettingThere: return "circle.lefthalf.filled"
        case .knowsIt:      return "checkmark.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .doesntKnowIt: return .red
        case .gettingThere: return .orange
        case .knowsIt:      return .green
        }
    }
}

#Preview("Player (consented)") {
    let granted = VideoConsentStore(defaults: UserDefaults(suiteName: "preview-sr-granted")!)
    granted.grant()
    return NavigationStack {
        SongReviewView(model: .sample(), consent: granted)
    }
}

#Preview("Consent gate") {
    NavigationStack {
        SongReviewView(model: .sample(),
                       consent: VideoConsentStore(defaults: UserDefaults(suiteName: "preview-sr-gate")!))
    }
}
