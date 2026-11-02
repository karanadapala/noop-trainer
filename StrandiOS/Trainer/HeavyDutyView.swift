import SwiftUI
import StrandDesign
import TrainerKit

/// Heavy Duty (D81): today's workout with each exercise's weight for today, then the settings. A
/// session runs on the Lift Log's own session screen, so every set lands in the Lift Log.
struct HeavyDutyView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var session: LiftSessionController
    @ObservedObject private var store = HeavyDutyStore.shared
    @ObservedObject private var regimen = RegimenStore.shared
    @ObservedObject private var runner = C25KRunner.shared

    /// The workout shown; nil follows what's due today.
    @State private var picked: HeavyDuty.Workout?
    @State private var confirmRemove = false
    @State private var nothingFits = false

    private var place: Place? { store.place(regimen) }
    private var plan: HeavyDutyPlan { store.plan(runner: runner) }
    private var c25kFinished: Bool { runner.plan.nextSession == nil }
    private var effort: LiftEffort {
        LiftEffort.on(Date(), firstSession: store.firstSession, c25kFinished: c25kFinished, options: store.options)
    }

    var body: some View {
        ScreenScaffold(title: "Heavy Duty", subtitle: "Mike Mentzer's method: one hard set per exercise, then rest.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                if store.enabled {
                    todayCard
                    workoutCard
                    settingsSection
                } else {
                    setupCard
                }
                Text("Heavy Duty is Mike Mentzer's training method, used here for personal, non-commercial training.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fadesNavigationBarOnScroll()
        .task(id: session.savedSessions) { await store.refresh(repo: repo) }
        .alert("Nothing to do here", isPresented: $nothingFits) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(place?.name ?? "This place") has none of the kit this workout needs. Pick another place below.")
        }
        .confirmationDialog("Remove Heavy Duty from the regimen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { store.enabled = false }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Your sets stay in the Lift Log. Adding it again picks up where you left off.")
        }
    }

    // MARK: Setup

    private var setupCard: some View {
        StrandCard(padding: 20, tint: StrandPalette.effortColor) {
            VStack(alignment: .leading, spacing: 14) {
                RegimenOverline(text: "Strength", color: StrandPalette.effortColor)
                Text("Upper and Legs, about once a week each")
                    .font(StrandFont.rounded(26))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    bullet("One working set per exercise, slow reps: 2 s up, 1 s hold, 3 s down.")
                    bullet("Two break-in weeks, then 1–2 reps short of failure while C25K runs.")
                    bullet("Your first session finds each weight; after that the app suggests it.")
                    bullet("Legs go two days before a run, never the day after lifting.")
                }
                placePicker
                NoopButton("Add Heavy Duty", systemImage: "plus", kind: .primary, fullWidth: true) {
                    store.enabled = true
                }
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

    private var placePicker: some View {
        HStack {
            Text("Where")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            Picker("Where", selection: $store.placeID) {
                ForEach(regimen.places) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
            .tint(StrandPalette.accent)
        }
    }

    // MARK: Today

    private var todayCard: some View {
        let today = plan.today(now: Date())
        let due = plan.due(now: Date())
        return StrandCard(padding: 20, tint: today.status == .session ? StrandPalette.effortColor : nil) {
            VStack(alignment: .leading, spacing: 12) {
                RegimenOverline(text: today.status == .session ? "Today" : today.headline,
                                color: today.status == .session ? StrandPalette.effortColor : StrandPalette.restColor)
                if let due {
                    Text(due.title)
                        .font(StrandFont.rounded(30))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(effort.detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(today.detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: The workout

    private var shown: HeavyDuty.Workout { picked ?? plan.due(now: Date()) ?? nextUp }

    /// When nothing is due: the workout done longest ago.
    private var nextUp: HeavyDuty.Workout {
        HeavyDuty.Workout.allCases.min { (store.last[$0] ?? .distantPast) < (store.last[$1] ?? .distantPast) } ?? .upper
    }

    private var workoutCard: some View {
        let workout = shown
        let exercises = HeavyDuty.exercises(workout, c25kFinished: c25kFinished)
        let isDue = plan.due(now: Date()) == workout
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The workout").strandOverline()
                Spacer()
                Picker("Workout", selection: Binding(get: { shown }, set: { picked = $0 })) {
                    ForEach(HeavyDuty.Workout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    if exercises.contains(where: { store.suggestion($0, at: place).kind == .findIt && (place?.has($0.kit) ?? true) }) {
                        Label("First time on a lift: start light. Sets of 10 slow reps, one step heavier each set; stop climbing when the 10th rep slows down. One step below that is your weight.",
                              systemImage: "scope")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().overlay(StrandPalette.hairline)
                    }
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { i, ex in
                        if i > 0 && exercises[i - 1].straightInto == nil {
                            Divider().overlay(StrandPalette.hairline).padding(.leading, 16)
                        }
                        exerciseRow(ex)
                    }
                }
            }
            if let lastDone = store.last[workout] {
                Text("Last \(workout.title.lowercased()) workout: \(lastDone.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            NoopButton(isDue ? "Start \(workout.title)" : "Start \(workout.title) anyway", systemImage: "play.fill",
                       kind: isDue ? .primary : .secondary, fullWidth: true) {
                if !store.start(workout, at: place, runner: runner, session: session), !session.isActive {
                    nothingFits = true
                }
            }
            Text("Opens the Lift Log's session screen with these weights filled in. Every set is saved there.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exerciseRow(_ ex: HeavyDuty.Exercise) -> some View {
        let here = place?.has(ex.kit) ?? true
        let s = store.suggestion(ex, at: place)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ex.name)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(here ? StrandPalette.textPrimary : StrandPalette.textTertiary)
                Text(here ? (s.kind == .findIt ? ex.cue : s.note) : "Not at \(place?.name ?? "this place"): skipped")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if ex.straightInto != nil {
                    Label("Straight into the next one, no rest", systemImage: "arrow.down")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.effortColor)
                }
            }
            Spacer(minLength: 8)
            if here {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(s.weight.map { "\(Self.trim($0)) \(place?.unit.label ?? "kg")" } ?? "First time")
                        .font(StrandFont.bodyNumber.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("× \(s.reps.label)")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    static func trim(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").strandOverline()
            NoopCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    placePicker
                    Divider().overlay(StrandPalette.hairline)
                    repsRow("Upper reps", $store.options.upperReps)
                    repsRow("Legs reps", $store.options.legReps)
                    Divider().overlay(StrandPalette.hairline)
                    Stepper(value: $store.options.daysBetween, in: 2...10) {
                        settingText("Days between the same workout", "\(store.options.daysBetween)")
                    }
                    Toggle(isOn: $store.options.shortOfFailureDuringC25K) {
                        settingText("Short of failure while C25K runs", nil)
                    }
                    .tint(StrandPalette.accent)
                    Toggle(isOn: $store.options.restDayAfterLifting) {
                        settingText("A rest day after each lifting day", nil)
                    }
                    .tint(StrandPalette.accent)
                    Divider().overlay(StrandPalette.hairline)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("When you outgrow the heaviest weight")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                        Text("If the place has nothing heavier, the app makes the lift harder another way: the first of these that's on.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(AcceptedStep.allCases, id: \.self) { step in
                        Toggle(isOn: Binding(
                            get: { store.options.acceptedSteps.contains(step) },
                            set: { on in
                                var steps = store.options.acceptedSteps.filter { $0 != step }
                                if on { steps.append(step) }
                                store.options.acceptedSteps = AcceptedStep.allCases.filter(steps.contains)
                            })) {
                            settingText(step.label, nil)
                        }
                        .tint(StrandPalette.accent)
                    }
                }
            }
            NoopButton("Remove Heavy Duty from the regimen", systemImage: "minus.circle", kind: .tertiary) {
                confirmRemove = true
            }
        }
    }

    private func repsRow(_ title: String, _ range: Binding<RepRange>) -> some View {
        HStack(spacing: 8) {
            settingText(title, nil)
            Spacer()
            Stepper("\(range.wrappedValue.low)", value: Binding(
                get: { range.wrappedValue.low },
                set: { range.wrappedValue = RepRange($0, max($0, range.wrappedValue.high)) }), in: 1...30)
                .labelsHidden()
            Text(range.wrappedValue.label)
                .font(StrandFont.bodyNumber)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(minWidth: 52)
            Stepper("\(range.wrappedValue.high)", value: Binding(
                get: { range.wrappedValue.high },
                set: { range.wrappedValue = RepRange(min($0, range.wrappedValue.low), $0) }), in: 1...30)
                .labelsHidden()
        }
    }

    private func settingText(_ title: String, _ value: String?) -> some View {
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
}
