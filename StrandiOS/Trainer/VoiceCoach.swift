import AVFoundation
import Foundation
import TrainerKit

/// Speaks workout cues over whatever else is playing (NOOP Trainer, D6/D11).
///
/// The session is `.playback` + `.voicePrompt` with `.mixWithOthers` and `.duckOthers`: music and video
/// keep playing, dip while a cue is spoken, and come back when the session deactivates after the last
/// queued utterance. `.playback` ignores the silent switch on purpose — a muted phone in a pocket must
/// still coach. Speaking while locked relies on the `audio` background mode in `project.yml`.
///
/// The countdown into a segment change is beeps, not words: short beeps at -3, -2, -1 and a long one
/// on the change, generated in code so there is no sound file to ship.
///
/// A home routine records no workout, so nothing else keeps the app running once the phone locks.
/// `keepAwake(true)` plays a silent loop under the cues for that. While it runs the session never goes
/// inactive, and ducking only changes when a session is (re)activated, so each cue briefly re-activates
/// the session with `.duckOthers` and the end of each cue re-activates it without: music dips for the
/// cue only, as it does without the loop.
@MainActor
final class VoiceCoach: NSObject {
    private let synth = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private let voice: AVSpeechSynthesisVoice?
    private var beeper: AVAudioPlayer?
    private var beeping = false
    /// Speech that arrived while the countdown was still sounding; spoken once it ends.
    private var afterBeeps: String?
    private var silentLoop: AVAudioPlayer?
    private var ducking = false

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
        if beeping {
            afterBeeps = text
            return
        }
        if interrupt, synth.isSpeaking { synth.stopSpeaking(at: .word) }
        activate()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = false
        synth.speak(utterance)
    }

    /// Plays the countdown so its long beep lands `delay` seconds from now. `skip` starts it that far in
    /// instead, when the cue is already late, so the long beep still lands on the change.
    func countdown(delay: TimeInterval, skip: TimeInterval) {
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        if beeper == nil {
            beeper = try? AVAudioPlayer(data: Self.countdownSound())
            beeper?.delegate = self
            beeper?.prepareToPlay()
        }
        guard let beeper else { return }
        activate()
        beeper.currentTime = skip
        beeping = beeper.play(atTime: beeper.deviceCurrentTime + delay)
    }

    /// Silences a countdown in progress (pause or stop mid-countdown).
    func cancelCountdown() {
        beeper?.stop()
        beeping = false
        afterBeeps = nil
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        cancelCountdown()
        releaseSession()
    }

    /// Keeps the app running with the phone locked (home routines) by playing silence under the cues.
    func keepAwake(_ on: Bool) {
        if on {
            guard silentLoop == nil, let loop = try? AVAudioPlayer(data: Self.wav(Array(repeating: 0, count: 44_100))) else { return }
            loop.numberOfLoops = -1
            silentLoop = loop
            ducking = true
            setDucking(false)
            NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                                   name: AVAudioSession.interruptionNotification, object: session)
        } else {
            guard let loop = silentLoop else { return }
            NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: session)
            loop.stop()
            silentLoop = nil
            prepare()
            releaseSession()
        }
    }

    private func activate() {
        if silentLoop != nil { setDucking(true) } else { try? session.setActive(true) }
    }

    private func releaseSession() {
        guard !synth.isSpeaking, !beeping else { return }
        if silentLoop != nil { setDucking(false); return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Re-activates the session with or without `.duckOthers`, pausing the silent loop across the gap.
    private func setDucking(_ on: Bool) {
        guard let loop = silentLoop else { return }
        guard on != ducking else {
            if !loop.isPlaying { loop.play() }
            return
        }
        loop.pause()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.playback, mode: .voicePrompt, options: on ? [.mixWithOthers, .duckOthers] : [.mixWithOthers])
        try? session.setActive(true)
        loop.play()
        ducking = on
    }

    /// A call or alarm stops the loop; start it again when the interruption ends.
    @objc private nonisolated func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        Task { @MainActor in
            guard let loop = self.silentLoop else { return }
            try? self.session.setActive(true)
            loop.play()
        }
    }

    private func beepsFinished() {
        beeping = false
        if let text = afterBeeps {
            afterBeeps = nil
            say(text, interrupt: true)
        } else {
            releaseSession()
        }
    }

    /// 16-bit mono WAV: three short 880 Hz beeps one second apart, then a long 1320 Hz beep starting
    /// exactly at 3 s (`CueTimeline.countdownLead`), like a gym interval timer.
    static func countdownSound() -> Data {
        let rate = 44_100
        let tones: [(start: Double, length: Double, hz: Double)] =
            [(0, 0.15, 880), (1, 0.15, 880), (2, 0.15, 880), (CueTimeline.countdownLead, 0.6, 1320)]
        let total = Int((CueTimeline.countdownLead + 0.7) * Double(rate))
        var samples = [Int16](repeating: 0, count: total)
        for tone in tones {
            let first = Int(tone.start * Double(rate))
            let count = Int(tone.length * Double(rate))
            let fade = Int(0.005 * Double(rate))   // 5 ms ramps, so the beeps don't click
            for n in 0..<count where first + n < total {
                let ramp = min(1, Double(min(n, count - 1 - n)) / Double(fade))
                let value = sin(2 * .pi * tone.hz * Double(n) / Double(rate)) * 0.6 * ramp
                samples[first + n] = Int16(value * Double(Int16.max))
            }
        }
        return wav(samples)
    }

    /// 16-bit mono 44.1 kHz WAV data.
    static func wav(_ samples: [Int16]) -> Data {
        let rate = 44_100
        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        samples.forEach { append($0) }
        return data
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

extension VoiceCoach: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if player === self.beeper { self.beepsFinished() } }
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
