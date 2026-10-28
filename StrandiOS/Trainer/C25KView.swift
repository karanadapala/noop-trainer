import SwiftUI
import StrandDesign
import TrainerKit

/// Voice-guided Couch to 5K (NOOP Trainer). The screen answers one question: what is today, a run or
/// a rest? The session card leads with the run drawn to scale; on the day after a run a rest card comes
/// first, with advice from the morning Charge score. The plan ladder below shows all 27 sessions.
struct C25KView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var runner = C25KRunner.shared
    @ObservedObject private var routineRunner = RoutineRunner.shared

    @State private var week = 1
    @State private var day = 1
    @State private var confirmStop = false
    @State private var blockedByWorkout = false
    @State private var linking: GuidedSession?
    @State private var reportingPain = false
    @State private var showingRedFlags = false
    @State private var confirmRunAnyway = false
    @State private var askedAfterRun = false
    @State private var routineChoice: RoutineVariant?
    @State private var confirmRestart: Int?
    @State private var takingCalfTest = false

    private var picked: GuidedSession? { C25K.session(week: week, day: day) }
    private var isPickedNext: Bool { week == runner.nextSession.week && day == runner.nextSession.day }
    private var charge: Double? { repo.today?.recovery }
    private var painState: PainState { runner.painState }

    private var lastRun: Date? { runner.lastRunDate }

    private var today: TrainingDay { TrainingDay.on(Date(), lastRun: lastRun) }

    var body: some View {
        ScreenScaffold(title: "C25K Coach", subtitle: "Couch to 5K in nine weeks, coached by voice.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                statusRow
                switch runner.state {
                case .running, .paused:
                    activeCard
                case .finished:
                    finishedCard
                    planCard
                case .idle:
                    if !painState.active.isEmpty { bodyCard }
                    if isPickedNext { todayCard }
                    if today == .runDay && onHold { routineCard(title: "Rest-day routine") }
                    sessionCard
                    if today == .runDay && !onHold { routineCard(title: "Not running today?") }
                    planCard
                }
            }
        }
        .onAppear { if runner.state == .idle { selectNext() } }
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
        .sheet(isPresented: $reportingPain) {
            PainReportSheet(title: "Something hurts") { runner.recordPain($0) }
        }
        .sheet(isPresented: $showingRedFlags) { RedFlagSheet() }
        .sheet(isPresented: $takingCalfTest) {
            CalfTestSheet(last: routineRunner.benchmarks.last, painful: calfTestBlocked) { left, right in
                routineRunner.addBenchmark(left: left, right: right)
            }
        }
        .confirmationDialog(confirmRestart.map { "Restart week \($0)?" } ?? "", isPresented: Binding(
            get: { confirmRestart != nil }, set: { if !$0 { confirmRestart = nil } }), titleVisibility: .visible) {
            Button("Restart week \(confirmRestart ?? 1)") {
                if let w = confirmRestart { runner.restartWeek(w) }
                confirmRestart = nil
                selectNext()
            }
            Button("Cancel", role: .cancel) { confirmRestart = nil }
        } message: {
            Text("Its runs come up again, labelled \"\(WeekRestart.label(attempt: runner.attempt(week: confirmRestart ?? 1) + 1) ?? "")\". The runs you've done are kept, and the rest-day levels hold until you're through it.")
        }
        .fullScreenCover(isPresented: Binding(get: { routineRunner.state != .idle }, set: { _ in })) {
            RoutinePlayerView()
        }
        .confirmationDialog("Run anyway?", isPresented: $confirmRunAnyway, titleVisibility: .visible) {
            Button("Start the run") { startPicked() }
            Button("Rest today", role: .cancel) {}
        } message: {
            Text("\(painState.holds.map(\.reason).joined(separator: ". ")). If you run, stop as soon as it's more than mild.")
        }
        .alert("Another workout is running", isPresented: $blockedByWorkout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("End the workout on the Live screen first, then start the C25K session.")
        }
    }

    // MARK: Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            if live.bonded {
                StatePill("Strap connected", tone: .positive)
            } else {
                StatePill("No strap: voice only", tone: .warning)
            }
            if !VoiceCoach.hasHighQualityVoice {
                StatePill("Basic voice", tone: .neutral, showsDot: false)
            }
        }
    }

    // MARK: Today (rest day, or done for today)

    @ViewBuilder
    private var todayCard: some View {
        switch today {
        case .runDay:
            EmptyView()
        case .restDay(let from):
            restCard(title: "Rest day", reason: "You ran yesterday. Your next run is \(Self.dayPhrase(from)).",
                     showsRoutine: true)
        case .ranToday(let from):
            restCard(title: "Done for today", reason: "Nice work. Rest tomorrow; your next run is \(Self.dayPhrase(from)).",
                     showsRoutine: false)
        }
    }

    private func restCard(title: String, reason: String, showsRoutine: Bool) -> some View {
        let advice = RestAdvice.forCharge(charge)
        return StrandCard(padding: 20, tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    overline("Today", color: StrandPalette.restColor)
                    Spacer()
                    if let charge { chargeChip(charge) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(StrandFont.rounded(30))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(reason)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Divider().overlay(StrandPalette.hairline)
                VStack(alignment: .leading, spacing: 4) {
                    Text(advice.headline)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(advice.detail)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsRoutine {
                    Divider().overlay(StrandPalette.hairline)
                    routineSection
                }
                Divider().overlay(StrandPalette.hairline)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(RestTip.forRestDay(sleepMinutes: repo.today?.totalSleepMin), id: \.text) { tip in
                        tipRow(tip)
                    }
                }
                if showsRoutine, calfTestDue { calfTestRow }
                if painState.active.isEmpty {
                    textLink("Something hurts", systemImage: "bandage") { reportingPain = true }
                }
            }
        }
    }

    private func tipRow(_ tip: RestTip) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: tip.kind == .sleep ? "moon.zzz" : "fork.knife")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.restColor)
                .frame(width: 20)
            Text(tip.text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Calf-raise test (D57)

    /// Not while calves or feet hurt: a test to fatigue would load them.
    private var calfTestBlocked: Bool { !Set(painState.active).isDisjoint(with: [.calves, .feet]) }

    private var calfTestDue: Bool {
        !calfTestBlocked && routineRunner.legsToday != .limiting
            && RestDayProgress.benchmarkDue(routineRunner.benchmarks, now: Date())
    }

    private var calfTestRow: some View {
        Button { takingCalfTest = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routineRunner.benchmarks.isEmpty ? "Calf-raise test" : "Calf-raise test due")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("About 3 minutes, every 3 weeks. You count, the coach keeps the numbers.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Rest-day routine (D37–D48)

    private func routineCard(title: String) -> some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                overline(title, color: StrandPalette.restColor)
                routineSection
            }
        }
    }

    /// Rest days so far in a row: 1 the day after a run.
    private var restDayInARow: Int {
        guard let lastRun else { return 2 }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: lastRun), to: cal.startOfDay(for: Date())).day ?? 2
    }

    private func routineInput(_ legs: LegFeel) -> RoutineBuilder.Input {
        let week = runner.nextSession.week
        return RoutineBuilder.Input(
            charge: charge, legs: legs, pain: painState, restDayInARow: restDayInARow, programWeek: week,
            stages: RestDayProgress.stages(log: routineRunner.sessions, pain: runner.pain, programWeek: week,
                                           repeatingWeek: runner.attempt(week: week) > 1),
            lastStrengthBlock: routineRunner.lastStrengthBlock, rotation: routineRunner.sessions.count)
    }

    @ViewBuilder
    private var routineSection: some View {
        if let done = routineRunner.doneToday {
            Label("Done today: \(done.variant.label) routine", systemImage: "checkmark.circle.fill")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.accent)
        } else if let legs = routineRunner.legsToday {
            let input = routineInput(legs)
            let suggested = RoutineBuilder.variant(for: input)
            let routine = RoutineBuilder.routine(for: input, variant: routineChoice ?? suggested)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(routine.variant.label) · about \(routine.estimatedMinutes) min")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(RoutineVariant.allCases.reversed(), id: \.self) { v in
                            Button(v == suggested ? "\(v.label) (suggested)" : v.label) { routineChoice = v }
                        }
                    } label: {
                        Text("Change")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
                Text(routine.variant.summary)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    if routine.walkMinutes > 0 { routineLine("Easy walk", "\(routine.walkMinutes) min") }
                    ForEach(routine.items, id: \.exercise.id) { item in
                        routineLine(item.exercise.name, item.dose.variant)
                    }
                }
                if !routine.skippedAreas.isEmpty {
                    Text("Leaving out anything that loads your \(routine.skippedAreas.map { $0.label.lowercased() }.joined(separator: " and ")) while it hurts.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NoopButton("Start the routine", systemImage: "play.fill", kind: .primary, fullWidth: true) {
                    if !routineRunner.start(routine) { blockedByWorkout = true }
                }
                Text("Voice-guided, so you can lock the phone. Put the mat down near a wall.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("How do your legs feel?")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                VStack(spacing: 8) {
                    ForEach(LegFeel.allCases, id: \.self) { feel in
                        Button { routineRunner.setLegs(feel) } label: { legFeelRow(feel) }
                            .buttonStyle(.plain)
                    }
                }
                Text("The coach picks today's routine from this and your Charge.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func legFeelRow(_ feel: LegFeel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feel.label)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(feel.detail)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
        .contentShape(Rectangle())
    }

    private func routineLine(_ name: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(StrandPalette.restColor).frame(width: 6, height: 6)
            Text(name).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
            Text(detail).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary).lineLimit(1)
        }
    }

    // MARK: Body (pain check, D49 / D61)

    private var bodyCard: some View {
        let state = painState
        return StrandCard(padding: 20, tint: state.isOnHold ? StrandPalette.statusWarning : nil) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    overline(state.isOnHold ? "Runs on hold" : "Your body",
                             color: state.isOnHold ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                    Spacer()
                    Button("Add") { reportingPain = true }
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                }
                ForEach(state.active, id: \.self) { area in
                    if state.needsCheck.contains(area) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(area.label): compared with yesterday?")
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            ChoiceChips(options: PainTrend.allCases, label: \.label, selected: nil,
                                        tint: StrandPalette.statusWarning) { trend in
                                runner.recordPain([PainEntry(area: area, date: Date(), kind: .trend(trend))])
                            }
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text(area.label)
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            Text(state.summary(area) ?? "")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
                if state.isOnHold {
                    Text("Rest today. The hold lifts by itself when a morning check says gone or less.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !state.needsCheck.isEmpty {
                    Text("Answer each morning. Same or worse puts today's run on hold.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                } else {
                    Text("The coach asks again tomorrow morning.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if state.suggestRepeatingWeek {
                    Text("If it keeps coming back, repeating this C25K week is a good idea.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let w = runner.restartableWeek {
                        textLink("Restart week \(w)", systemImage: "arrow.counterclockwise") { confirmRestart = w }
                    }
                }
                if state.showRedFlags || state.isOnHold {
                    NoopButton("When to get it checked", systemImage: "cross.case", kind: .secondary) { showingRedFlags = true }
                } else {
                    textLink("When to get it checked", systemImage: "cross.case") { showingRedFlags = true }
                }
            }
        }
    }

    private func chargeChip(_ score: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(StrandPalette.recoveryColor(score)).frame(width: 8, height: 8)
            Text("Charge \(Int(score.rounded()))")
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(StrandPalette.surfaceInset))
        .accessibilityLabel("Charge \(Int(score.rounded())), \(StrandPalette.recoveryState(score).lowercased())")
    }

    // MARK: Session

    private var sessionCard: some View {
        StrandCard(padding: 20, tint: isPickedNext && today == .runDay && !onHold ? StrandPalette.effortColor : nil) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    overline(sessionEyebrow, color: onHold ? StrandPalette.statusWarning
                             : isPickedNext ? StrandPalette.effortColor : StrandPalette.textTertiary)
                    Spacer()
                    sessionMenu
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Week \(week) · Day \(day)")
                            .font(StrandFont.rounded(30))
                            .foregroundStyle(StrandPalette.textPrimary)
                        if let again = WeekRestart.label(attempt: runner.attempt(week: week)) {
                            Text(again)
                                .font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(StrandPalette.surfaceOverlay))
                                .overlay(Capsule().stroke(StrandPalette.hairlineStrong, lineWidth: 1))
                        }
                    }
                    if let picked {
                        Text(Self.shape(of: picked))
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }

                if let picked {
                    VStack(alignment: .leading, spacing: 8) {
                        SessionStrip(session: picked)
                        HStack(spacing: 14) {
                            legend("Run", StrandPalette.effortColor)
                            legend("Walk", StrandPalette.restColor)
                            Spacer()
                            Text("5 min warm-up and cool-down")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }

                dayChips

                if let picked, let entry = runner.logEntry(picked) {
                    Label(C25KLinkSheet.summary(start: entry.startTs, durationS: entry.durationS,
                                                avgHr: entry.avgHr, distanceM: entry.distanceM),
                          systemImage: "checkmark.circle.fill")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                } else if let picked, runner.isCompleted(picked) {
                    Label("Marked as done", systemImage: "checkmark.circle.fill")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.accent)
                }

                if onHold {
                    Label("\(painState.holds.map(\.reason).joined(separator: ". ")). Rest today.",
                          systemImage: "pause.circle")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.statusWarning)
                } else if isPickedNext, today == .runDay, let note = RestAdvice.runDayNote(forCharge: charge) {
                    Label(note, systemImage: "battery.25percent")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.statusWarning)
                }

                VStack(spacing: 10) {
                    NoopButton(onHold ? "Run anyway" : startTitle, systemImage: "figure.run",
                               kind: pickedDone || onHold ? .secondary : .primary, fullWidth: true) {
                        if onHold { confirmRunAnyway = true } else { startPicked() }
                    }
                    Text("Saved as a Running workout with heart rate and route. Your music keeps playing and dips for each cue.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var onHold: Bool { painState.isOnHold }

    private func startPicked() {
        guard let picked else { return }
        if !runner.start(picked, model: model) { blockedByWorkout = true }
    }

    private var sessionEyebrow: String {
        if onHold { return "On hold" }
        if pickedDone { return "Done" }
        guard isPickedNext else { return "From the plan" }
        return today == .runDay ? "Today's run" : "Next run"
    }

    private var pickedDone: Bool { picked.map(runner.isCompleted) ?? false }

    private var startTitle: LocalizedStringKey {
        pickedDone ? "Run it again" : "Start week \(week), day \(day)"
    }

    private var dayChips: some View {
        HStack(spacing: 8) {
            ForEach(1...C25K.daysPerWeek, id: \.self) { d in
                let s = C25K.session(week: week, day: d)
                let done = s.map(runner.isCompleted) ?? false
                let selected = d == day
                Button { day = d } label: {
                    HStack(spacing: 5) {
                        if done { Image(systemName: "checkmark").font(StrandFont.caption.weight(.bold)) }
                        Text("Day \(d)").font(StrandFont.subhead.weight(.semibold))
                    }
                    .foregroundStyle(selected ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(selected ? StrandPalette.surfaceOverlay : StrandPalette.surfaceInset))
                    .overlay(Capsule().stroke(selected ? StrandPalette.hairlineStrong : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Day \(d)\(done ? ", done" : "")")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            if !isPickedNext {
                Button("Next run") { selectNext() }
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
            }
        }
    }

    private var sessionMenu: some View {
        Menu {
            if let picked {
                if runner.logEntry(picked) == nil {
                    Button { linking = picked } label: { Label("Link a past workout…", systemImage: "link") }
                }
                if runner.isCompleted(picked) {
                    Button { runner.setCompleted(picked, false) } label: { Label("Mark as not done", systemImage: "arrow.uturn.backward") }
                } else {
                    Button { runner.setCompleted(picked, true) } label: { Label("Mark as done", systemImage: "checkmark") }
                }
            }
            Button { reportingPain = true } label: { Label("Something hurts…", systemImage: "bandage") }
            if let w = runner.restartableWeek {
                Button { confirmRestart = w } label: { Label("Restart week \(w)…", systemImage: "arrow.counterclockwise") }
            }
            Button { takingCalfTest = true } label: { Label("Calf-raise test…", systemImage: "figure.stand") }
            Divider()
            Button {
                if !runner.start(C25K.rehearsal, model: model) { blockedByWorkout = true }
            } label: { Label("Play a 2-minute test", systemImage: "speaker.wave.2") }
        } label: {
            Image(systemName: "ellipsis")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }

    // MARK: Plan

    private var doneCount: Int { C25K.all.filter(runner.isCompleted).count }

    private var planCard: some View {
        StrandCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The plan")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Text("\(doneCount) of \(C25K.all.count) runs")
                        .font(StrandFont.subhead.monospacedDigit())
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                PlanLadder(isDone: runner.isCompleted, next: runner.nextSession, selectedWeek: week,
                           restAfter: RestDayProgress.restDaysAfterRuns(runner.log.mapValues(\.date),
                                                                        restDates: routineRunner.sessions.map(\.date)),
                           attempt: runner.attempt(week:)) { w in
                    week = w
                    day = (1...C25K.daysPerWeek).first { d in
                        C25K.session(week: w, day: d).map { !runner.isCompleted($0) } ?? false
                    } ?? 1
                }
                Text(Self.climbLine(next: runner.nextSession))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Running

    private var activeCard: some View {
        StrandCard(padding: 24, tint: segmentColor) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    overline(segmentEyebrow, color: segmentColor)
                    Spacer()
                    if let s = runner.session, s.week > 0 {
                        Text("Week \(s.week) · Day \(s.day)")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }

                VStack(spacing: 2) {
                    Text(clock(runner.segmentRemaining))
                        .font(StrandFont.display(88))
                        .tracking(StrandFont.displayTracking(88))
                        .foregroundStyle(StrandPalette.textPrimary)
                    if let next = runner.nextSegment {
                        Text("then \(C25KRunner.verb(next.kind).lowercased()) \(CueTimeline.spokenDuration(next.seconds))")
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)

                if let s = runner.session {
                    SessionStrip(session: s, elapsed: runner.elapsed, height: 30)
                }

                HStack {
                    metric("Heart rate", model.bpm.map { "\($0)" } ?? "--", unit: "bpm", dot: zoneColor)
                    Spacer()
                    metric("Elapsed", clock(runner.elapsed))
                    Spacer()
                    metric("Left", clock(Double(runner.session?.totalSeconds ?? 0) - runner.elapsed))
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
        StrandCard(padding: 20, tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 12) {
                overline("Session complete", color: StrandPalette.accent)
                if let s = runner.session, s.week > 0 {
                    Text("Week \(s.week) · Day \(s.day) done")
                        .font(StrandFont.rounded(30))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Saved in Workouts. Tomorrow is a rest day.")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if !askedAfterRun {
                        Divider().overlay(StrandPalette.hairline)
                        Text("Anything hurting?")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        HStack(spacing: 12) {
                            NoopButton("No", kind: .secondary, fullWidth: true) { askedAfterRun = true }
                            NoopButton("Yes, log it", systemImage: "bandage", kind: .secondary, fullWidth: true) {
                                askedAfterRun = true
                                reportingPain = true
                            }
                        }
                    }
                } else {
                    Text("Test complete")
                        .font(StrandFont.rounded(30))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                NoopButton("Done", kind: .secondary, fullWidth: true) {
                    runner.dismissFinished()
                    askedAfterRun = false
                    selectNext()
                }
            }
        }
    }

    // MARK: Helpers

    private func selectNext() {
        week = runner.nextSession.week
        day = runner.nextSession.day
    }

    private func overline(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking * 4)
            .foregroundStyle(color)
    }

    /// A left-aligned accent link, for secondary actions inside a card.
    private func textLink(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
        }
        .buttonStyle(.plain)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    /// "31 min · 6 runs of 90 seconds" or "38 min · 3 runs, longest 5 minutes".
    static func shape(of s: GuidedSession) -> String {
        let runs = s.segments.filter(\.kind.isRun).map(\.seconds)
        let total = "\(s.totalSeconds / 60) min"
        guard let longest = runs.max() else { return total }
        if runs.count == 1 { return "\(total) · one \(CueTimeline.spokenDuration(longest)) run" }
        if Set(runs).count == 1 { return "\(total) · \(runs.count) runs of \(CueTimeline.spokenDuration(longest))" }
        return "\(total) · \(runs.count) runs, longest \(CueTimeline.spokenDuration(longest))"
    }

    /// "Bar height is each day's longest run: 90 seconds next, 30 minutes by week 9."
    static func climbLine(next: GuidedSession) -> String {
        let now = CueTimeline.spokenDuration(PlanLadder.longestRun(next))
        let end = C25K.session(week: C25K.weeks, day: C25K.daysPerWeek).map { CueTimeline.spokenDuration(PlanLadder.longestRun($0)) } ?? "30 minutes"
        return "Bar height is each day's longest run: \(now) next, \(end) by week \(C25K.weeks)."
    }

    /// "tomorrow", "on Thursday", "today".
    static func dayPhrase(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInTomorrow(date) { return "tomorrow" }
        return "on " + date.formatted(.dateTime.weekday(.wide))
    }

    private var segmentEyebrow: String {
        guard runner.state != .paused else { return "Paused" }
        guard let s = runner.session, let i = runner.segmentIndex else { return "Finishing" }
        let seg = s.segments[i]
        if seg.kind.isRun {
            let n = s.segments.prefix(i + 1).filter(\.kind.isRun).count
            return s.runCount > 1 ? "Run \(n) of \(s.runCount)" : "Run"
        }
        return C25KRunner.verb(seg.kind)
    }

    private var segmentColor: Color {
        switch runner.currentSegment?.kind {
        case .run: return StrandPalette.effortColor
        case .walk, .warmUp, .coolDown: return StrandPalette.restColor
        case nil: return StrandPalette.accent
        }
    }

    private var zoneColor: Color? {
        guard let bpm = model.bpm, live.streamingLiveHR else { return nil }
        return StrandPalette.hrZoneColor(model.profile.hrZoneSet.zoneNumber(forBPM: Double(bpm)))
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, unit: String? = nil, dot: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(StrandFont.overline)
                .foregroundStyle(StrandPalette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(value)
                    .font(StrandFont.rounded(22, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let unit {
                    Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
