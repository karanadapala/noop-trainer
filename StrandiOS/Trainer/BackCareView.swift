import SwiftUI
import StrandDesign
import TrainerKit

/// Back care (D98–D101): today's session, the levels of the Big 3 and Core B, the rules, the settings.
/// Sessions run on the voice-guided routine player.
struct BackCareView: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var store = BackCareStore.shared
    @ObservedObject private var heavyDuty = HeavyDutyStore.shared
    @ObservedObject private var runner = C25KRunner.shared
    @ObservedObject private var routineRunner = RoutineRunner.shared

    @State private var blocked = false
    /// "Not yet" on today's level-up offer.
    @State private var offerDismissed = false
    @State private var confirmRemove = false

    private var plan: BackCarePlan { store.plan() }

    var body: some View {
        ScreenScaffold(title: "Back care", subtitle: "McGill's Big 3 most days, and core work after lifting. Never to failure.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                if store.enabled {
                    todayCard
                    if !offerDismissed, let ex = plan.levelUpOffer(now: Date()) { levelUpCard(ex) }
                    exerciseList("Big 3 · most days", BackCare.coreA)
                    exerciseList("Core B · after lifting", BackCare.coreB)
                    rulesCard
                    settingsSection
                } else {
                    setupCard
                    rulesCard
                }
            }
        }
        .fadesNavigationBarOnScroll()
        .onAppear { store.updateWake(from: repo.sleeps) }
        .fullScreenCover(isPresented: Binding(
            get: { routineRunner.state != .idle && routineRunner.routine?.variant.isBackCare == true },
            set: { _ in })) {
            RoutinePlayerView()
        }
        .alert("Another session is running", isPresented: $blocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Finish or stop the run or routine that's going, then start this one.")
        }
        .confirmationDialog("Remove Back care from the regimen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { store.enabled = false }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your levels and log are kept. The side plank goes back into the rest-day routine.")
        }
    }

    // MARK: Setup

    private var setupCard: some View {
        StrandCard(padding: 20, tint: StrandPalette.effortColor) {
            VStack(alignment: .leading, spacing: 14) {
                RegimenOverline(text: "Mobility", color: StrandPalette.effortColor)
                Text("A strong, steady back, a few minutes a day")
                    .font(StrandFont.rounded(26))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    bullet("The Big 3 (curl-up, side plank, bird dog) most days: about 8 minutes, short holds counted aloud.")
                    bullet("On lifting days, one short set before and Core B after the lifts, in place of sit-ups.")
                    bullet("It moves up a level after a week of sessions that felt easy, one exercise at a time.")
                    bullet("It takes over the side plank in your rest-day routine.")
                }
                NoopButton("Add Back care", systemImage: "plus", kind: .primary, fullWidth: true) { store.enabled = true }
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

    // MARK: Today

    private var todayCard: some View {
        let next = plan.next(now: Date())
        let today = plan.today(now: Date())
        let routine = store.routine(for: next)
        return StrandCard(padding: 20, tint: routine != nil ? StrandPalette.effortColor : nil) {
            VStack(alignment: .leading, spacing: 12) {
                RegimenOverline(text: "Today", color: routine != nil ? StrandPalette.effortColor : StrandPalette.restColor)
                Text(today.headline)
                    .font(StrandFont.rounded(30))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(today.detail)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let routine {
                    NoopButton(startTitle(next), systemImage: "play.fill", kind: .primary, fullWidth: true) {
                        if !store.start(session(next), routine: routine) { blocked = true }
                    }
                    Text("Voice-guided: every hold is counted, with the phone locked if you like.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if case .warmUp = next {
                    textLink("Not lifting today? Switch to the full Big 3", systemImage: "arrow.triangle.2.circlepath") {
                        heavyDuty.skipToday()
                    }
                }
                if case .coreB = next, !didBigThreeToday {
                    textLink("Do the Big 3 instead", systemImage: "arrow.triangle.2.circlepath") {
                        if !store.start(.coreA, routine: BackCare.coreA(levels: store.levels)) { blocked = true }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var didBigThreeToday: Bool {
        store.log.contains { Calendar.current.isDateInToday($0.date) && $0.session != .coreB }
    }

    private func startTitle(_ next: BackCarePlan.Next) -> LocalizedStringKey {
        switch next {
        case .warmUp: return "Start the warm-up"
        case .coreB: return "Start Core B"
        default: return "Start the Big 3"
        }
    }

    private func session(_ next: BackCarePlan.Next) -> BackCareLog.Session {
        switch next {
        case .warmUp: return .warmUp
        case .coreB: return .coreB
        default: return .coreA
        }
    }

    private func levelUpCard(_ ex: Exercise) -> some View {
        let next = Stage(rawValue: store.level(ex.id).rawValue + 1) ?? .strengthen
        return StrandCard(padding: 18, tint: StrandPalette.statusPositive) {
            VStack(alignment: .leading, spacing: 10) {
                RegimenOverline(text: "Ready for more", color: StrandPalette.statusPositive)
                Text("\(ex.name): \(ex.dose(next).variant.lowercased())")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("A week of sessions that felt easy. Next: \(Self.amount(ex.dose(next))).")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    NoopButton("Level up", kind: .primary, fullWidth: true) { store.levelUp(ex.id) }
                    NoopButton("Not yet", kind: .secondary, fullWidth: true) { offerDismissed = true }
                }
            }
        }
    }

    // MARK: Exercises

    private func exerciseList(_ title: String, _ exercises: [Exercise]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).strandOverline()
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { i, ex in
                        if i > 0 { Divider().overlay(StrandPalette.hairline).padding(.leading, 16) }
                        let dose = ex.dose(store.level(ex.id))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ex.name)
                                .font(StrandFont.body.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text("\(Self.amount(dose)) · \(dose.variant)")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(ex.howTo)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            if ex.id == "hingeDrill" {
                                Text("Legs day only")
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(StrandPalette.effortColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    /// "4-3-2 holds of 8 s, each side", "2 × 6 reps, each side".
    static func amount(_ d: Dose) -> String {
        let side = d.perSide ? ", each side" : ""
        if let p = d.pyramid, case .heldReps(_, let hold) = d.work {
            return p.map(String.init).joined(separator: "-") + " holds of \(hold) s" + side
        }
        switch d.work {
        case .reps(let n): return "\(d.sets) × \(n) reps" + side
        case .hold(let s): return "\(d.sets) × \(s) s" + side
        case .heldReps(let n, let hold): return "\(d.sets) × \(n), \(hold) s holds" + side
        }
    }

    // MARK: Rules

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every session").strandOverline()
            NoopCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    bullet("Never to failure: end each hold on the count, or sooner at the first shake, sag or arch.")
                    bullet("Brace, then hinge, every time you bend: picking up dumbbells, loading plates, setting pins.")
                    bullet("Not in the first hour after waking; the discs are fullest then.")
                    bullet("Left big-toe pain or any new leg symptom ends the session. Your health profile lists the signs to get checked.")
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
                        setting("Wait after waking", "\(store.options.minutesAfterWaking) min")
                    }
                    Toggle(isOn: $store.options.warmUpBeforeLifting) { setting("A short set before lifting", nil) }
                        .tint(StrandPalette.accent)
                    Stepper(value: $store.options.easySessionsToLevelUp, in: 3...10) {
                        setting("Easy sessions before the next level", "\(store.options.easySessionsToLevelUp)")
                    }
                }
            }
            NoopButton("Remove Back care from the regimen", systemImage: "minus.circle", kind: .tertiary) { confirmRemove = true }
        }
    }

    private func setting(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
            if let value {
                Spacer()
                Text(value)
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func textLink(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
        }
        .buttonStyle(.plain)
    }
}
