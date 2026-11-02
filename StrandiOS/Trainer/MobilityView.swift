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

    private var plan: MobilityPlan { store.plan() }

    var body: some View {
        ScreenScaffold(title: "Mobility", subtitle: "Range back for the hips, hamstrings and back, one small step a week.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                if let flare = BackFlare.current(entries: runner.pain, now: Date()) { BackFlareCard(flare: flare) }
                if store.enabled {
                    phaseStrip
                    todayCard
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

    private var todayCard: some View {
        let today = plan.today(now: Date())
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
                if case .session(let s) = next {
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
