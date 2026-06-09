import AVFoundation

/// Text-to-speech read-aloud for the study flow (Spec §11 — accessibility for
/// struggling readers). A thin wrapper over `AVSpeechSynthesizer` that works on
/// both iOS and macOS; the UI owns one instance and drives it from the child's
/// `readAloud` preference plus a manual "speak" button.
@MainActor
final class SpeechReader: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    /// Speak `text`, cancelling anything currently being spoken. A slightly
    /// slower-than-default rate suits early readers.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()
        #if os(iOS)
        // Ensure speech is audible even with the ring/silent switch set — this is
        // an accessibility aid, not background media.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
