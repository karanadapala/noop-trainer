import SwiftUI
import StrandDesign
import TrainerKit

/// The first open after a gap (D227): "Welcome back", no list of what was missed, one question, today's
/// step with its length already worked out, and a plan saved for next time.
struct ComebackSheet: View {
    let gapDays: Int
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ComebackStore.shared
    @ObservedObject private var morning = MorningBudget.shared
    @State private var reason: GapReason?
    @State private var fever = false
    @State private var chest = false
    @State private var page = 0
    @State private var reminded: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch page {
                    case 0: welcome
                    case 1: today
                    default: nextTime
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StrandPalette.surfaceBase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Later") { store.comeback = nil; dismiss() } } }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .interactiveDismissDisabled(page > 0)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome back.")
                .font(StrandFont.rounded(34))
                .foregroundStyle(StrandPalette.textPrimary)
            Text("Nothing's lost: a few days off costs almost no fitness. What happened?")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ChoiceChips(options: GapReason.allCases, label: \.label, selected: reason) { reason = $0 }
            if reason == .ill {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $fever) { question("A fever in the last 24 hours") }
                        .tint(StrandPalette.statusWarning)
                    Toggle(isOn: $chest) { question("Chest pain, a racing heart or unusual breathlessness") }
                        .tint(StrandPalette.statusCritical)
                    if chest { RedFlagList() }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
            }
            if reason == .injured {
                Text("Log it in the pain check on the plan it affects, so runs and lifts wait for it.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var today: some View {
        let day = ActivePlans.day()
        let budget = ActivePlans.budget()
        let next = day.next.flatMap { n in ActivePlans.all().first { $0.id == n.planID }.map { ($0.title, n) } }
        return VStack(alignment: .leading, spacing: 18) {
            Text(SickDayStore.shared.current != nil ? "Rest first" : "Today's step")
                .font(StrandFont.rounded(30))
                .foregroundStyle(StrandPalette.textPrimary)
            if SickDayStore.shared.current != nil {
                Text("Every plan stays paused until you're better. The Regimen asks each morning.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else if let (title, n) = next {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(title) · \(n.headline)")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(n.detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !budget.clear { DayBudgetBanner(budget: budget) }
                Text("When suits?")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                WrapLayout(spacing: 8) {
                    ForEach(morning.options.slots, id: \.self) { m in
                        Button { morning.remind(at: m); reminded = m } label: {
                            Text(MorningOptions.label(m))
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(reminded == m ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(reminded == m ? StrandPalette.accent.opacity(0.28) : StrandPalette.surfaceInset))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let reminded {
                    Text("A reminder comes \(morning.options.leadMinutes) min before \(MorningOptions.label(reminded)).")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            } else {
                Text("Nothing is due today. The way back starts with the next session.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private var nextTime: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next time you're ill, what should I do?")
                .font(StrandFont.rounded(26))
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("A plan made now is what makes the next comeback easier. It shows again when you tap \"I'm unwell\".")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $store.copingPlan)
                .font(StrandFont.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
        }
    }

    private var footer: some View {
        NoopButton(page == 0 ? "Continue" : page == 1 ? "Next" : "Save", kind: .primary, fullWidth: true) {
            switch page {
            case 0:
                if let reason { store.resolve(reason, fever: fever || chest) } else { store.resolve(.rather, fever: false) }
                page = 1
            case 1: page = 2
            default: dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(StrandPalette.surfaceBase)
    }

    private func question(_ text: String) -> some View {
        Text(text).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
    }
}

/// Presents the comeback screen over whatever tab is open.
struct ComebackPresenter: ViewModifier {
    @ObservedObject private var store = ComebackStore.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { store.comeback != nil }, set: { if !$0 { store.comeback = nil } })) {
            ComebackSheet(gapDays: store.comeback ?? 0)
        }
    }
}

/// Setup → Reminders: going quiet (D226) and the morning time budget (D229–D232).
struct TrainerRemindersView: View {
    @ObservedObject private var gap = ComebackStore.shared
    @ObservedObject private var morning = MorningBudget.shared

    var body: some View {
        ScreenScaffold(title: "Reminders", subtitle: "Few, kind, and quiet once you're back.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                section("Morning: today's time") {
                    Toggle(isOn: $morning.options.enabled) { label("Say how long today takes, once I'm up", nil) }
                        .tint(StrandPalette.accent)
                    Toggle(isOn: $morning.options.restDays) { label("On rest days too", nil) }
                        .tint(StrandPalette.accent)
                    stepper("If the strap hasn't synced: usual wake +", $morning.options.fallbackAfterUsualWake, 0...180, 15, "min")
                    stepper("Reminder before the chosen time", $morning.options.leadMinutes, 0...60, 5, "min")
                    ForEach(morning.options.slots.indices, id: \.self) { i in
                        stepper("Time button \(i + 1)", $morning.options.slots[i], 300...1380, 15, nil,
                                shown: MorningOptions.label(morning.options.slots[i]))
                    }
                    stepper("Pause after mornings with no reply", $morning.options.pauseAfterIgnored, 1...14, 1, nil)
                    if let wake = morning.usualWake {
                        Text("Your usual wake time: \(MorningOptions.label(wake)).")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if morning.paused {
                        NoopButton("Paused after no replies: keep sending", kind: .secondary, fullWidth: true) { morning.keepSending() }
                    }
                }
                section("When I go quiet") {
                    Toggle(isOn: $gap.options.enabled) { label("Check in after days with no sessions", nil) }
                        .tint(StrandPalette.accent)
                    ForEach(gap.options.steps.indices, id: \.self) { i in
                        stepper("Message \(i + 1) on gap day", $gap.options.steps[i].day, 1...60, 1, nil)
                    }
                    stepper("Sent at", $gap.options.hour, 6...21, 1, nil, shown: MorningOptions.label(gap.options.hour * 60 + gap.options.minute))
                    stepper("\"Back tomorrow\" reminder at", $gap.options.tomorrowHour, 5...21, 1, nil,
                            shown: MorningOptions.label(gap.options.tomorrowHour * 60))
                    stepper("\"Welcome back\" after gap days", $gap.options.comebackAfterDays, 1...14, 1, nil)
                    Text("Rest days don't count as gap days. Messages are booked on the phone each time the app closes, and cancelled when you're back.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                section("Your plan for next time you're ill") {
                    TextEditor(text: $gap.copingPlan)
                        .font(StrandFont.subhead)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                }
            }
        }
        .fadesNavigationBarOnScroll()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        let inner = VStack(alignment: .leading, spacing: 14, content: content)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).strandOverline()
            NoopCard(padding: 16) { inner }
        }
    }

    private func stepper(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int, _ unit: String?,
                         shown: String? = nil) -> some View {
        Stepper(value: value, in: range, step: step) {
            label(title, shown ?? "\(value.wrappedValue)\(unit.map { " \($0)" } ?? "")")
        }
    }

    private func label(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let value {
                Text(value).font(StrandFont.subhead.monospacedDigit()).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }
}
