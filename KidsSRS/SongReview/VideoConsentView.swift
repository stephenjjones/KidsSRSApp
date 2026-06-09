import SwiftUI

/// The parental-consent step for video (Spec §14.1). Presents the required
/// disclosures and a deliberate grant action. Shown by the video chokepoint
/// (`SongReviewView`) whenever consent isn't yet granted, and reused in settings.
///
/// > ⚠️ LEGAL (§14.1): the "Allow videos" action below is an **interim informed
/// > acknowledgment**, NOT verifiable parental consent (VPC), and the §8.1 adult
/// > gate is not VPC either. A legally-approved verification mechanism must
/// > replace this action — and be signed off — before release. This view's job
/// > is to surface the disclosures and drive the (real, enforced) consent state.
struct VideoConsentView: View {
    let onGrant: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("A grown-up's OK is needed for videos", systemImage: "play.rectangle.fill")
                .font(.title2.bold())
                .labelStyle(.titleAndIcon)

            disclosure("Songs play from YouTube",
                       "Videos load directly from YouTube. Google may collect information from your child, and ads can play before or during songs.",
                       systemImage: "globe")
            disclosure("Not in Apple's Kids Category",
                       "Because it includes YouTube video, Song Review isn't covered by Apple's Kids rules — unlike the rest of the app.",
                       systemImage: "person.fill.questionmark")
            disclosure("You stay in control",
                       "You can turn videos off again any time in Parents → Song Review → Video consent.",
                       systemImage: "hand.raised.fill")

            Button {
                // ⚠️ LEGAL (§14.1): interim informed-acknowledgment, NOT VPC.
                // Replace this with a legally-approved verifiable-consent step
                // (e.g. transaction/ID verification) before launch.
                onGrant()
            } label: {
                Text("I'm the parent — turn on videos")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: 520)
    }

    private func disclosure(_ title: String, _ body: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(body)")
    }
}

/// Parent-facing management of video consent (Spec §14.1): see status, grant
/// proactively, or revoke. Reached from `ParentDashboardView` → Song Review.
struct VideoConsentSettingsView: View {
    @StateObject private var consent: VideoConsentStore
    @State private var confirmingRevoke = false

    init(consent: VideoConsentStore = VideoConsentStore()) {
        _consent = StateObject(wrappedValue: consent)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Videos", value: consent.isGranted ? "On" : "Off")
                if let date = consent.grantedAt {
                    LabeledContent("Allowed on",
                                   value: date.formatted(date: .abbreviated, time: .shortened))
                }
            } header: {
                Text("Song Review video")
            } footer: {
                Text(consent.isGranted
                     ? "Song Review can play YouTube videos. Turn this off to block them again."
                     : "Song Review will ask for your consent before playing any video.")
            }

            if consent.isGranted {
                Section {
                    Button("Turn off videos", role: .destructive) { confirmingRevoke = true }
                }
            } else {
                Section {
                    VideoConsentView { consent.grant() }
                        .padding(.vertical, 8)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Video consent")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Turn off videos?",
                            isPresented: $confirmingRevoke,
                            titleVisibility: .visible) {
            Button("Turn off videos", role: .destructive) { consent.revoke() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Song Review will ask for your consent again before playing any video.")
        }
    }
}

#Preview("Consent gate") {
    ScrollView {
        VideoConsentView { }
            .padding()
    }
}

#Preview("Settings — off") {
    NavigationStack {
        VideoConsentSettingsView(
            consent: VideoConsentStore(defaults: UserDefaults(suiteName: "preview-consent-off")!)
        )
    }
}
