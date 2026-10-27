import AVFoundation
import Foundation

/// Speaks workout cues over whatever else is playing (NOOP Trainer, D6/D11).
///
/// The session is `.playback` + `.voicePrompt` with `.mixWithOthers` and `.duckOthers`: music and video
/// keep playing, dip while a cue is spoken, and come back when the session deactivates after the last
/// queued utterance. `.playback` ignores the silent switch on purpose — a muted phone in a pocket must
/// still coach. Speaking while locked relies on the `audio` background mode in `project.yml`.
@MainActor
final class VoiceCoach: NSObject {
    private let synth = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private let voice: AVSpeechSynthesisVoice?

    override init() {
        voice = VoiceCoach.bestVoice()
        super.init()
        synth.delegate = self
        synth.usesApplicationAudioSession = true
    }

    func prepare() {
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
    }

    /// `interrupt` cuts off a status line already being spoken so a segment change is never late.
    func say(_ text: String, interrupt: Bool) {
        if interrupt, synth.isSpeaking { synth.stopSpeaking(at: .word) }
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = false
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        releaseSession()
    }

    private func releaseSession() {
        guard !synth.isSpeaking else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Best installed voice for the phone's language: Premium, then Enhanced, then the default.
    /// Premium voices are a free download in Settings → Accessibility → Spoken Content → Voices.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let sameLanguage = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(String(language.prefix(2))) }
        let sameRegion = sameLanguage.filter { $0.language == language }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality {
            case .premium: return 2
            case .enhanced: return 1
            default: return 0
            }
        }
        return (sameRegion.isEmpty ? sameLanguage : sameRegion).max { rank($0) < rank($1) }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    static var hasHighQualityVoice: Bool {
        guard let v = bestVoice() else { return false }
        return v.quality == .premium || v.quality == .enhanced
    }
}

extension VoiceCoach: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.releaseSession() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.releaseSession() }
    }
}
