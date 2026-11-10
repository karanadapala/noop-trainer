import SwiftUI
import StrandDesign
import TrainerKit

/// "I'm unwell" (D219): one tap pauses every plan; the type is optional and can be added later.
struct UnwellSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sick = SickDayStore.shared
    @State private var kind: IllnessKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What is it? (optional)")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("It decides how gently your plans come back. Skip it if you're not sure.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ChoiceChips(options: IllnessKind.allCases, label: \.label, selected: kind) {
                            kind = kind == $0 ? nil : $0
                        }
                        Text(IllnessKind.hint)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    RuleCard(options: sick.options)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle("I'm unwell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                NoopButton("Pause my plans", systemImage: "pause.fill", kind: .primary, fullWidth: true) {
                    sick.markUnwell(kind: kind)
                    dismiss()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(StrandPalette.surfaceBase)
            }
        }
    }
}

/// While ill (D221, D223): plans are paused; one check each morning; the red flags show by themselves
/// when it isn't getting better.
struct SickDayCard: View {
    let episode: SickEpisode
    @ObservedObject private var sick = SickDayStore.shared
    @State private var fever = false
    @State private var showRules = false
    @State private var showFlags = false

    var body: some View {
        let today = sick.todaysCheck()
        let flags = SickDays.showRedFlags(episode, options: sick.options)
        StrandCard(padding: 20, tint: StrandPalette.restColor) {
            VStack(alignment: .leading, spacing: 14) {
                RegimenOverline(text: "Unwell · day \(episode.days(now: Date()))", color: StrandPalette.restColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rest is the plan today")
                        .font(StrandFont.rounded(28))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Every plan is paused. Nothing is lost: a few days off costs almost no fitness.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if episode.kind == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What is it? (optional)")
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                        ChoiceChips(options: IllnessKind.allCases, label: \.label, selected: nil) { sick.setKind($0) }
                        Text(IllnessKind.hint)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                panel {
                    if let today {
                        HStack {
                            Text("This morning: \(today.feel.label)\(today.fever ? " · fever" : "")")
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            Button("Change") { fever = today.fever; sick.clearTodaysCheck() }
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.accent)
                                .buttonStyle(.plain)
                        }
                    } else {
                        Text("How are you this morning?")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Toggle(isOn: $fever) {
                            Text("A fever in the last 24 hours")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        .tint(StrandPalette.statusWarning)
                        ChoiceChips(options: SickFeel.allCases, label: \.label, selected: nil, fill: StrandPalette.surfaceOverlay) {
                            sick.check($0, fever: fever)
                        }
                    }
                }
                if SickDays.proposeEnd(episode, restingHRNearUsual: sick.strapLevel.map { $0 == .quiet }, options: sick.options) {
                    panel {
                        Text("Better two mornings running. Back to normal?")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        NoopButton("Back to normal", systemImage: "checkmark", kind: .primary, fullWidth: true) {
                            sick.backToNormal()
                        }
                    }
                }
                if flags || showFlags { RedFlagList() }
                HStack(spacing: 18) {
                    Button(showRules ? "Hide what's OK" : "What's OK while ill") { showRules.toggle() }
                    if !flags { Button(showFlags ? "Hide the signs" : "Signs to get checked") { showFlags.toggle() } }
                    Spacer()
                }
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
                .buttonStyle(.plain)
                if showRules { RuleCard(options: sick.options, framed: false) }
                if today == nil || today?.feel != .normal {
                    Button { sick.backToNormal() } label: {
                        Label("I'm back to normal", systemImage: "arrow.uturn.forward")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
    }
}

/// "Feeling ill? Check this first" (D220).
struct RuleCard: View {
    let options: SickDayOptions
    var framed = true

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            if framed {
                Text("Feeling ill? Check this first")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            ForEach(Array(SickDays.ruleCard(options: options).enumerated()), id: \.offset) { i, rule in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(StrandFont.subhead.weight(.semibold).monospacedDigit())
                        .foregroundStyle(StrandPalette.accent)
                    Text(rule)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if framed { RedFlagList() }
        }
        if framed {
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
        } else {
            content
        }
    }
}

/// The signs that mean see a doctor. Advice to show, not a diagnosis.
struct RedFlagList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Get checked")
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.statusCritical)
            ForEach(SickDays.redFlags, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(StrandPalette.statusCritical).frame(width: 5, height: 5)
                    Text(item)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Advice to show, not a diagnosis.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }
}

/// The way back after an illness (D224): each plan's first day back, dated, with what it means for that
/// plan, read from the plan itself.
struct WayBackCard: View {
    let episode: SickEpisode
    let plans: [any TrainingPlan]
    @ObservedObject private var sick = SickDayStore.shared

    var body: some View {
        let cal = Calendar.current
        let resumes = SickDays.resumes(after: episode, options: sick.options)
        let rows = Dictionary(grouping: plans) { resumes[$0.intensity] ?? cal.startOfDay(for: Date()) }
            .sorted { $0.key < $1.key }
        let end = sick.wayBackEnds(episode) ?? Date()
        StrandCard(padding: 20, tint: StrandPalette.accent) {
            VStack(alignment: .leading, spacing: 14) {
                RegimenOverline(text: "The way back", color: StrandPalette.accent)
                Text(cal.startOfDay(for: Date()) >= end ? "Back to your normal plan today"
                     : "Back to normal \(Self.day(end))")
                    .font(StrandFont.rounded(26))
                    .foregroundStyle(StrandPalette.textPrimary)
                if SickDays.walkOnly(after: episode, options: sick.options, now: Date()) {
                    row(when: "Today", title: "An easy walk", detail: "15–30 minutes, nothing harder.")
                }
                ForEach(rows, id: \.key) { date, group in
                    ForEach(Array(group.enumerated()), id: \.element.id) { i, plan in
                        let step = SickDays.step(daysMissed: SickDays.daysMissed(plan: plan, episode: episode, now: Date()),
                                                 options: sick.options)
                        row(when: i == 0 ? Self.day(date) : "", title: plan.title, detail: plan.wayBack(step))
                    }
                }
                if episode.end.map({ cal.isDateInToday($0) }) == true {
                    Button { sick.stillUnwell() } label: {
                        Text("Still unwell")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(when: String, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(when)
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.accent)
                .frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(detail)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

/// The strap's illness watch, asked rather than decided (D222).
struct StrapAskCard: View {
    let raised: Bool
    @ObservedObject private var sick = SickDayStore.shared

    var body: some View {
        StrandCard(padding: 18, tint: StrandPalette.statusWarning) {
            VStack(alignment: .leading, spacing: 12) {
                RegimenOverline(text: "From your strap", color: StrandPalette.statusWarning)
                Text(raised ? "Your body may be fighting something" : "Your heart rate's been higher than usual")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(raised ? "Today is easy: a walk, back care, mobility. Classes: you might be contagious."
                     : "How do you feel?")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if raised {
                    HStack(spacing: 10) {
                        NoopButton("I'm fine, keep the plan", kind: .secondary, fullWidth: true) { sick.answerStrap(.fine) }
                        NoopButton("I'm unwell", kind: .secondary, fullWidth: true) { sick.answerStrap(.ill) }
                    }
                } else {
                    HStack(spacing: 10) {
                        NoopButton("Fine", kind: .secondary, fullWidth: true) { sick.answerStrap(.fine) }
                        NoopButton("A bit off", kind: .secondary, fullWidth: true) { sick.answerStrap(.bitOff) }
                        NoopButton("Ill", kind: .secondary, fullWidth: true) { sick.answerStrap(.ill) }
                    }
                }
                Text("An estimate from heart rate, HRV, breathing and skin temperature. You decide.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The illness cards for the top of the Regimen: unwell, the way back, or the strap's question.
struct IllnessCards: View {
    let plans: [any TrainingPlan]
    @ObservedObject private var sick = SickDayStore.shared

    var body: some View {
        if let episode = sick.current {
            SickDayCard(episode: episode)
        } else if let ctx = sick.context() {
            WayBackCard(episode: ctx.episode, plans: plans)
        } else if sick.strapAsks() {
            StrapAskCard(raised: sick.strapLevel == .raised)
        }
    }
}

/// On a plan's own screen: why it's paused today, from the same funnel as the Regimen.
struct SickPauseBanner: View {
    let planID: String
    @ObservedObject private var sick = SickDayStore.shared

    var body: some View {
        if sick.context() != nil || sick.easyToday(),
           let today = ActivePlans.day().plans.first(where: { $0.planID == planID }), today.status == .hold {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: sick.current != nil ? "bed.double" : "leaf")
                    .foregroundStyle(StrandPalette.restColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(today.headline)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(today.detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
        }
    }
}

/// Every sick-day number (D220–D224, D233), in Setup.
struct SickDaySettingsView: View {
    @ObservedObject private var sick = SickDayStore.shared

    var body: some View {
        ScreenScaffold(title: "Sick days", subtitle: "What pauses while you're ill, and how each plan comes back.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                section("While you're ill") {
                    Toggle(isOn: $sick.options.floorOnColdDays) {
                        label("Offer a 2-minute floor on cold days", nil)
                    }
                    .tint(StrandPalette.accent)
                    stepper("Red flags after this many \"Worse\" mornings", $sick.options.redFlagsAfterWorse, 1...7)
                    stepper("…or this many \"Same\" mornings", $sick.options.redFlagsAfterSame, 2...14)
                    stepper("Suggest \"Back to normal\" after \"Better\" mornings", $sick.options.proposeEndAfterBetter, 1...5)
                }
                section("Coming back") {
                    stepper("Easy days after fever, flu or a stomach bug", $sick.options.easyDaysAfterFeverType, 0...5)
                    stepper("Hard sessions wait (days) after flu or COVID-19", $sick.options.hardWaitDays, 0...21)
                    stepper("…or after being ill this many days", $sick.options.longIllnessDays, 1...14)
                }
                section("Days missed → the way back") {
                    ForEach(sick.options.bands.indices, id: \.self) { i in
                        let band = sick.options.bands[i]
                        if let upTo = band.upToDays {
                            Stepper(value: Binding(get: { upTo }, set: { sick.options.bands[i].upToDays = $0 }),
                                    in: (i == 0 ? 0 : (sick.options.bands[i - 1].upToDays ?? 0) + 1)...365) {
                                label("Up to \(upTo) days: \(Self.name(band.step))", nil)
                            }
                        } else {
                            label("Longer: \(Self.name(band.step))", nil)
                        }
                    }
                }
            }
        }
        .fadesNavigationBarOnScroll()
    }

    static func name(_ step: WayBackStep) -> String {
        switch step {
        case .carryOn: return "carry on"
        case .repeatLast: return "the last session again"
        case .repeatBlock: return "the last block again"
        case .stepBack: return "one block back"
        case .restart: return "from the start"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).strandOverline()
            let body = VStack(alignment: .leading, spacing: 14, content: content)
            NoopCard(padding: 16) { body }
        }
    }

    private func stepper(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) { label(title, "\(value.wrappedValue)") }
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
