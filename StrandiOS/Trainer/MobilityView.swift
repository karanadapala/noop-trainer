import SwiftUI
import StrandDesign
import TrainerKit

/// The Mobility plan (D127, D148): where you are in the 12 weeks, today's session, this week's drills,
/// the rules and settings. Sessions run on the voice-guided routine player.
struct MobilityView: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var store = MobilityStore.shared
    @ObservedObject private var heavyDuty = HeavyDutyStore.shared
    @ObservedObject private var runner = C25KRunner.shared
    @ObservedObject private var routineRunner = RoutineRunner.shared

    @State private var blocked = false
    @State private var confirmRemove = false
    @State private var testing = false
    /// "Do a session instead" on a test day.
    @State private var sessionInstead = false

    private var plan: MobilityPlan { store.plan() }

    var body: some View {
        ScreenScaffold(title: "Mobility", subtitle: "Range back for the hips, hamstrings and back, one small step a week.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                SickPauseBanner(planID: Mobility.planID)
                if let flare = BackFlare.current(entries: runner.pain, now: Date()) { BackFlareCard(flare: flare) }
                if store.enabled {
                    phaseStrip
                    if store.awaitingUnease != nil { uneaseCard }
                    todayCard
                    testsSection
                    drillList
                    rulesCard
                    settingsSection
                } else {
                    setupCard
                    rulesCard
                }
            }
        }
        .fadesNavigationBarOnScroll()
        .onAppear { BackCareStore.shared.updateWake(from: repo.sleeps) }
        .fullScreenCover(isPresented: Binding(
            get: { routineRunner.state != .idle && routineRunner.routine?.variant == .mobility },
            set: { _ in })) {
            RoutinePlayerView()
        }
        .sheet(isPresented: $testing) {
            MobilityTestView(isBaseline: store.tests.isEmpty, shinCleared: plan.shinCleared) { store.saveTest($0) }
        }
        .alert("Another session is running", isPresented: $blocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Finish or stop the run or routine that's going, then start this one.")
        }
        .confirmationDialog("Remove Mobility from the regimen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { store.enabled = false }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your log and week are kept; adding it again carries on from there.")
        }
    }

    // MARK: Setup

    private var setupCard: some View {
        StrandCard(padding: 20, tint: StrandPalette.effortColor) {
            VStack(alignment: .leading, spacing: 14) {
                RegimenOverline(text: "Mobility", color: StrandPalette.effortColor)
                Text("Twelve weeks to bend, squat and sit cross-legged again")
                    .font(StrandFont.rounded(26))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    bullet("Weeks 1–4: gentle range. The roll-down goes a little further each week, from your knees to the floor.")
                    bullet("Weeks 5–8: fuller range, contract–relax stretches, and deep squats once the shin is cleared.")
                    bullet("Weeks 9–12: strength at end range on alternate sessions; the spine stays neutral under load.")
                    bullet("After training, or in the evening on rest days; never in the first hour after waking.")
                    bullet("A back flare means hips only for 48 hours, and the weeks step back.")
                }
                NoopButton("Add Mobility", systemImage: "plus", kind: .primary, fullWidth: true) { store.enabled = true }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(StrandPalette.textTertiary).frame(width: 5, height: 5)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Where you are

    /// The 12 weeks as three blocks of four, today's week marked.
    private var phaseStrip: some View {
        let week = plan.week(now: Date())
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(1...12, id: \.self) { w in
                    Capsule()
                        .fill(w < week ? StrandPalette.accent : w == week ? StrandPalette.effortColor
                              : StrandPalette.textTertiary.opacity(0.22))
                        .frame(height: 6)
                        .padding(.trailing, w % 4 == 0 && w < 12 ? 6 : 0)
                }
            }
            HStack {
                ForEach([Mobility.Phase.gentle, .fuller, .strength], id: \.self) { p in
                    Text(p.label)
                        .font(StrandFont.caption.weight(Mobility.Phase.of(week: week) == p ? .semibold : .regular))
                        .foregroundStyle(Mobility.Phase.of(week: week) == p ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Week \(week) of 12, \(Mobility.Phase.of(week: week).label)")
        }
    }

    // MARK: Today

    private var testToday: Bool { !sessionInstead && plan.testFitsToday(tests: store.tests, now: Date()) }

    private var todayCard: some View {
        let today = sessionInstead ? MobilityPlan(options: plan.options, start: plan.start, log: plan.log, pain: plan.pain,
                                                  shinCleared: plan.shinCleared, liftToday: plan.liftToday,
                                                  liftDone: plan.liftDone, wake: plan.wake).today(now: Date())
            : plan.today(now: Date())
        let next = plan.next(now: Date())
        return StrandCard(padding: 20, tint: today.status == .session ? StrandPalette.effortColor : nil) {
            VStack(alignment: .leading, spacing: 12) {
                RegimenOverline(text: "Today", color: today.status == .session ? StrandPalette.effortColor : StrandPalette.restColor)
                Text(today.headline)
                    .font(StrandFont.rounded(28))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(today.detail)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if testToday {
                    NoopButton("Start the test day", systemImage: "ruler", kind: .primary, fullWidth: true) { testing = true }
                    Button { sessionInstead = true } label: {
                        Label("Do a session instead", systemImage: "arrow.triangle.2.circlepath")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.accent)
                    }
                    .buttonStyle(.plain)
                } else if case .session(let s) = next {
                    NoopButton("Start the session", systemImage: "play.fill", kind: .primary, fullWidth: true) {
                        if !store.start(s, plan: plan) { blocked = true }
                    }
                    Text("Voice-guided: every hold timed and every rep counted, with the phone locked if you like.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Test days

    private var uneaseCard: some View {
        StrandCard(padding: 18, tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 12) {
                RegimenOverline(text: "After the test day", color: StrandPalette.accent)
                Text("Back unease this morning, 0 to 10?")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                PainScaleRow(selected: nil) { store.setNextDayUnease($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var testsSection: some View {
        let changes = MobilityMetric.allCases.compactMap { MobilityChange.of($0, in: store.tests) }
        let due = plan.testDue(tests: store.tests, now: Date())
        VStack(alignment: .leading, spacing: 10) {
            Text("Test days").strandOverline()
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    if changes.isEmpty {
                        Text("No tests yet. The first one is your baseline: an afternoon without lifting, about 25 minutes.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(changes.enumerated()), id: \.element.metric) { i, c in
                        if i > 0 { Divider().overlay(StrandPalette.hairline).padding(.leading, 16) }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.metric.label)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(c.verdict == .baselineOnly ? "Baseline \(Self.num(c.baseline)) \(c.metric.unit)"
                                     : "\(Self.num(c.baseline)) → \(Self.num(c.latest)) \(c.metric.unit)")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            Spacer()
                            if c.verdict != .baselineOnly {
                                StatePill(LocalizedStringKey(Self.verdict(c.verdict)), tone: c.verdict == .better ? .positive
                                          : c.verdict == .worse ? .warning : .neutral, showsDot: false)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            Text(store.tests.isEmpty ? "A change only counts when it's past the test's measurement error and holds for two tests in a row."
                 : "Next test day: \(due <= Date() ? "due now" : due.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))). A change counts when it's past the measurement error twice in a row.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func num(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }

    static func verdict(_ v: MobilityChange.Verdict) -> String {
        switch v {
        case .better: return "Better"
        case .worse: return "Worse"
        case .noRealChange, .baselineOnly: return "No real change yet"
        }
    }

    // MARK: This week

    private var drillList: some View {
        let next = plan.next(now: Date())
        let session: Mobility.Session = { if case .session(let s) = next { return s }; return .full }()
        let routine = plan.routine(for: session, now: Date())
        return VStack(alignment: .leading, spacing: 10) {
            Text(session == .full ? "This week's session" : session == .short ? "The short session" : "Hips only")
                .strandOverline()
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(routine.items.enumerated()), id: \.element.exercise.id) { i, item in
                        if i > 0 { Divider().overlay(StrandPalette.hairline).padding(.leading, 16) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.exercise.name)
                                .font(StrandFont.body.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("\(BackCareView.amount(item.dose)) · \(item.dose.variant)")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.exercise.howTo)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            if !plan.shinCleared {
                Text("Deep-squat holds and heel drops join once the shin's getting-back-to-running checks are passed.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Rules

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every session").strandOverline()
            NoopCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    bullet("Bending without load is practice, not danger: relax and let the back round, slowly.")
                    bullet("Lifting anything heavy is different: brace, then hinge. No loaded bending for 12 weeks.")
                    bullet("Some stretch is fine, up to 3 out of 10, and no worse the next morning.")
                    bullet("Anything below the knee or in the big toe: stop that drill. The end of each session asks.")
                    bullet("Slow, no bouncing; breathe out into each stretch.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").strandOverline()
            NoopCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Stepper(value: $store.options.minutesAfterWaking, in: 0...180, step: 15) {
                        HStack {
                            Text("Wait after waking")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            Text("\(store.options.minutesAfterWaking) min")
                                .font(StrandFont.bodyNumber)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
            }
            NoopButton("Remove Mobility from the regimen", systemImage: "minus.circle", kind: .tertiary) { confirmRemove = true }
        }
    }
}
