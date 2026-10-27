import SwiftUI
import StrandDesign
import TrainerKit

/// Voice-guided Couch to 5K (NOOP Trainer, Sprint 0). Pick a day, press Start, put the phone away:
/// every segment change, countdown and heart-rate correction is spoken over your music.
struct C25KView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @ObservedObject private var runner = C25KRunner.shared

    @State private var week = 1
    @State private var day = 1
    @State private var confirmStop = false
    @State private var blockedByWorkout = false
    @State private var linking: GuidedSession?

    private var picked: GuidedSession? { C25K.session(week: week, day: day) }

    var body: some View {
        ScreenScaffold(title: "C25K Coach",
                       subtitle: "Voice-guided Couch to 5K. Start, lock the phone, and listen.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                statusRow
                switch runner.state {
                case .running, .paused: activeCard
                case .finished: finishedCard
                case .idle: EmptyView()
                }
                if runner.state == .idle || runner.state == .finished {
                    programCard
                    pickerCard
                    planCard
                }
            }
        }
        .onAppear {
            if runner.state == .idle {
                week = runner.nextSession.week
                day = runner.nextSession.day
            }
        }
        .confirmationDialog("Stop this workout?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop and save", role: .destructive) { runner.stop() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("The workout is saved, but this day won't be marked as done.")
        }
        .sheet(item: $linking) { s in
            C25KLinkSheet(session: s) { entry in runner.link(s, to: entry) }
                .environmentObject(model)
        }
        .alert("Another workout is running", isPresented: $blockedByWorkout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("End the workout on the Live screen first, then start the C25K session.")
        }
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 10) {
            if live.bonded {
                StatePill("Strap connected", tone: .positive)
            } else {
                StatePill("No strap: voice cues only", tone: .warning)
            }
            Spacer()
            if !VoiceCoach.hasHighQualityVoice {
                StatePill("Basic voice", tone: .neutral, showsDot: false)
            }
        }
    }

    // MARK: Running

    private var activeCard: some View {
        StrandCard(padding: 24, tint: segmentColor) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(segmentTitle)
                        .font(StrandFont.title1)
                        .foregroundStyle(segmentColor)
                    Spacer()
                    if let s = runner.session, s.week > 0 {
                        Text("Week \(s.week) · Day \(s.day)")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }

                Text(clock(runner.segmentRemaining))
                    .font(StrandFont.display(84))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let next = runner.nextSegment {
                    Text("Next: \(C25KRunner.verb(next.kind)) \(CueTimeline.spokenDuration(next.seconds))")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }

                ProgressView(value: min(runner.elapsed, Double(runner.session?.totalSeconds ?? 1)),
                             total: Double(runner.session?.totalSeconds ?? 1))
                    .tint(segmentColor)

                HStack {
                    metric("Elapsed", clock(runner.elapsed))
                    Spacer()
                    metric("Heart rate", model.bpm.map { "\($0) bpm" } ?? "--")
                    Spacer()
                    metric("Zone", zoneLabel)
                }

                if let said = runner.lastSpoken {
                    Text("“\(said)”")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    if runner.state == .running {
                        NoopButton("Pause", systemImage: "pause.fill", kind: .secondary, fullWidth: true) { runner.pause() }
                    } else {
                        NoopButton("Resume", systemImage: "play.fill", kind: .primary, fullWidth: true) { runner.resume() }
                    }
                    NoopButton("Stop", systemImage: "stop.fill", kind: .destructive, fullWidth: true) { confirmStop = true }
                }
            }
        }
    }

    private var finishedCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Session complete", systemImage: "checkmark.seal.fill")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.statusPositive)
                if let s = runner.session, s.week > 0 {
                    Text("Week \(s.week), day \(s.day) is done and saved in Workouts.")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                NoopButton("Done", kind: .secondary) {
                    runner.dismissFinished()
                    week = runner.nextSession.week
                    day = runner.nextSession.day
                }
            }
        }
    }

    // MARK: Whole-program progress

    private var doneCount: Int { C25K.all.filter { runner.isCompleted($0) }.count }

    private var programCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Week \(runner.nextSession.week) of \(C25K.weeks)")
                        .font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text("\(doneCount) of \(C25K.all.count) runs")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                ProgressView(value: Double(doneCount), total: Double(C25K.all.count))
                    .tint(StrandPalette.statusPositive)
                // One row per week, three dots per row: done / next up / selected / still to come.
                VStack(spacing: 8) {
                    ForEach(1...C25K.weeks, id: \.self) { w in
                        HStack(spacing: 10) {
                            Text("W\(w)")
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .frame(width: 28, alignment: .leading)
                            ForEach(1...C25K.daysPerWeek, id: \.self) { d in
                                dayDot(week: w, day: d)
                            }
                            Spacer()
                        }
                    }
                }
                Text("Tap a day to choose it below.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func dayDot(week w: Int, day d: Int) -> some View {
        let s = C25K.session(week: w, day: d)
        let done = s.map { runner.isCompleted($0) } ?? false
        let isNext = runner.nextSession.week == w && runner.nextSession.day == d && !done
        let isSelected = week == w && day == d
        return Button {
            week = w
            day = d
        } label: {
            ZStack {
                Circle()
                    .fill(done ? StrandPalette.statusPositive
                          : isNext ? StrandPalette.effortColor.opacity(0.35)
                          : StrandPalette.textTertiary.opacity(0.18))
                if done {
                    Image(systemName: "checkmark")
                        .font(StrandFont.caption.weight(.bold))
                        .foregroundStyle(StrandPalette.goldDeepText)
                } else {
                    Text("\(d)")
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(isNext ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(isSelected ? StrandPalette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(w), day \(d)\(done ? ", done" : isNext ? ", next" : "")")
    }

    // MARK: Picking a day

    private var pickerCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose a session")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Stepper("Week \(week) of \(C25K.weeks)", value: $week, in: 1...C25K.weeks)
                    .font(StrandFont.body)
                Picker("Day", selection: $day) {
                    ForEach(1...C25K.daysPerWeek, id: \.self) { d in
                        Text(dayLabel(d)).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                NoopButton("Start", systemImage: "figure.run", kind: .primary, fullWidth: true) {
                    guard let picked else { return }
                    if !runner.start(picked, model: model) { blockedByWorkout = true }
                }
                NoopButton("Test the voice (2-minute session)", systemImage: "speaker.wave.2.fill", kind: .tertiary) {
                    if !runner.start(C25K.rehearsal, model: model) { blockedByWorkout = true }
                }
                Text("Records as a normal Running workout (HR, Effort and GPS route). Music keeps playing; it dips while the coach speaks.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private var planCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Week \(week), day \(day)")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    if let picked {
                        Text("\(picked.totalSeconds / 60) min")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                ForEach(Array(summaryLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if let picked {
                    if let entry = runner.logEntry(picked) {
                        Label("Done: \(C25KLinkSheet.summary(start: entry.startTs, durationS: entry.durationS, avgHr: entry.avgHr, distanceM: entry.distanceM)) (\(entry.source.label))",
                              systemImage: "checkmark.circle.fill")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.statusPositive)
                    } else {
                        NoopButton("Link a past workout…", systemImage: "link", kind: .tertiary) { linking = picked }
                    }
                    Toggle("Marked as done", isOn: Binding(
                        get: { runner.isCompleted(picked) },
                        set: { runner.setCompleted(picked, $0) }))
                        .font(StrandFont.subhead)
                }
            }
        }
    }

    // MARK: Helpers

    private func dayLabel(_ d: Int) -> String {
        guard let s = C25K.session(week: week, day: d) else { return "Day \(d)" }
        return runner.isCompleted(s) ? "Day \(d) ✓" : "Day \(d)"
    }

    /// Collapses repeated run/walk pairs: "6 × run 90 seconds, walk 2 minutes".
    private var summaryLines: [String] {
        guard let picked else { return [] }
        let middle = Array(picked.segments.dropFirst().dropLast())
        var lines = ["Warm-up walk, 5 minutes"]
        if middle.count >= 2, middle.count.isMultiple(of: 2) {
            let pair = Array(middle.prefix(2))
            let repeats = middle.count / 2
            if repeats > 1, (0..<repeats).allSatisfy({ Array(middle[($0 * 2)..<($0 * 2 + 2)]) == pair }) {
                lines.append("\(repeats) × run \(CueTimeline.spokenDuration(pair[0].seconds)), walk \(CueTimeline.spokenDuration(pair[1].seconds))")
                lines.append("Cool-down walk, 5 minutes")
                return lines
            }
        }
        for seg in middle {
            lines.append("\(C25KRunner.verb(seg.kind)) \(CueTimeline.spokenDuration(seg.seconds))")
        }
        lines.append("Cool-down walk, 5 minutes")
        return lines
    }

    private var segmentTitle: String {
        guard runner.state != .paused else { return "Paused" }
        return runner.currentSegment.map { C25KRunner.verb($0.kind) } ?? "Finishing"
    }

    private var segmentColor: Color {
        switch runner.currentSegment?.kind {
        case .run: return StrandPalette.effortColor
        case .walk, .warmUp, .coolDown: return StrandPalette.restColor
        case nil: return StrandPalette.statusPositive
        }
    }

    private var zoneLabel: String {
        guard let bpm = model.bpm, live.streamingLiveHR else { return "--" }
        return "Z\(model.profile.hrZoneSet.zoneNumber(forBPM: Double(bpm)))"
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.overline)
                .foregroundStyle(StrandPalette.textTertiary)
            Text(value)
                .font(StrandFont.bodyNumber)
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
