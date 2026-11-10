import SwiftUI
import StrandDesign
import TrainerKit

/// "Anything hurting?": pick the areas, then 0–10 for each, or "one sharp spot" (D38, D49, D114). Used
/// after a run and from "Something hurts" on the C25K screen.
struct PainReportSheet: View {
    let title: String
    let onSave: ([PainEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scores: [BodyArea: Int] = [:]
    @State private var spots: Set<BodyArea> = []
    @State private var picked: [BodyArea] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tap where it hurts, then how much. Each morning the coach asks again.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(BodyArea.allCases, id: \.self) { area in
                        areaRow(area)
                    }
                }
                .padding(20)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let now = Date()
                        onSave(picked.compactMap { area in
                            if spots.contains(area) { return PainEntry(area: area, date: now, kind: .spot) }
                            return scores[area].map { PainEntry(area: area, date: now, kind: .rating($0)) }
                        })
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !picked.isEmpty && picked.allSatisfy { scores[$0] != nil || spots.contains($0) }
    }

    private func areaRow(_ area: BodyArea) -> some View {
        let on = picked.contains(area)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                if on { picked.removeAll { $0 == area } } else { picked.append(area) }
            } label: {
                HStack {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                    Text(area.label)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if on {
                PainScaleRow(selected: spots.contains(area) ? nil : scores[area]) {
                    scores[area] = $0
                    spots.remove(area)
                }
                if area == .back {
                    Text("Back pain, or the big-toe pain that comes with a flare. Runs, lifting and Core B rest for 48 hours.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    SpotToggle(on: spots.contains(area)) {
                        if spots.contains(area) { spots.remove(area) } else { spots.insert(area) }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised))
    }
}

/// 0–10 in one row of taps, with the anchor words underneath (D114).
struct PainScaleRow: View {
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(Array(PainScale.range), id: \.self) { n in
                    let isOn = n == selected
                    Button { onSelect(n) } label: {
                        Text("\(n)")
                            .font(StrandFont.subhead.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isOn ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(Circle().fill(isOn ? Self.tint(n).opacity(0.3) : StrandPalette.surfaceInset))
                            .overlay(Circle().stroke(isOn ? Self.tint(n) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) out of 10\(PainScale.anchor(n).map { ", \($0.lowercased())" } ?? "")")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Text(selected.flatMap(Self.caption) ?? "0 none · 3 noticeable · 5 distracting · 8 can't continue")
                .font(StrandFont.footnote)
                .foregroundStyle(selected.map { $0 > PainScale.limit ? StrandPalette.statusWarning : StrandPalette.textTertiary }
                                 ?? StrandPalette.textTertiary)
        }
    }

    static func tint(_ n: Int) -> Color {
        n <= PainScale.limit ? StrandPalette.accent : n < 7 ? StrandPalette.statusWarning : StrandPalette.statusCritical
    }

    static func caption(_ n: Int) -> String? {
        let word = PainScale.anchor(n).map { " · \($0)" } ?? ""
        return n > PainScale.limit ? "\(n)/10\(word): above the 3/10 limit" : "\(n)/10\(word)"
    }
}

/// "Sharp pain in one small spot on the bone": its own tap, since it's a red flag whatever the number.
struct SpotToggle: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                Label("Sharp pain in one small spot on the bone", systemImage: on ? "checkmark.square.fill" : "square")
                    .font(StrandFont.subhead)
                    .foregroundStyle(on ? StrandPalette.statusWarning : StrandPalette.textSecondary)
            }
            .buttonStyle(.plain)
            if on {
                Text("That's worth getting checked before running again. The coach will hold runs.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "What made you stop?" after a run ended early (D111, D119). Pain asks where, which side, how much,
/// what it feels like and the fingertip check, then says what to do. Advice, not a diagnosis.
struct StopSheet: View {
    let session: GuidedSession
    let onSave: (RunStop, [PainEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason: StopReason?
    @State private var area: BodyArea?
    @State private var side: PainSide?
    @State private var score: Int?
    @State private var feel: PainFeel?
    @State private var spot = false
    @State private var backPain = false
    @State private var breathingWarning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    question("What made you stop?") {
                        ChoiceChips(options: StopReason.allCases, label: \.label, selected: reason,
                                    tint: StrandPalette.statusWarning) { reason = $0 }
                    }
                    if reason == .breathing {
                        Toggle(isOn: $breathingWarning) {
                            Text("Chest pain, feeling faint, or very short of breath even after slowing down")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                        .tint(StrandPalette.statusCritical)
                    }
                    if reason == .pain { painQuestions }
                    if let advice { adviceCard(advice) }
                }
                .padding(20)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle("Run stopped")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder private var painQuestions: some View {
        question("Where?") {
            ChoiceChips(options: BodyArea.allCases, label: \.label, selected: area,
                        tint: StrandPalette.statusWarning) { area = $0 }
        }
        question("Which side?") {
            ChoiceChips(options: PainSide.allCases, label: \.label, selected: side,
                        tint: StrandPalette.statusWarning) { side = $0 }
        }
        question("Out of 10, how bad is it now, while walking?") {
            PainScaleRow(selected: score) { score = $0 }
        }
        question("What does it feel like?") {
            ChoiceChips(options: PainFeel.allCases, label: \.label, selected: feel,
                        tint: StrandPalette.statusWarning) { feel = $0 }
        }
        if area != .back { question("Press along it with two fingertips") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sore along a stretch of a few inches, or in one small spot on the bone?")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SpotToggle(on: spot) { spot.toggle() }
            }
        } }
        if area != .back && (side == .left || side == .right) {
            Toggle(isOn: $backPain) {
                Text("Back or buttock pain with it")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .tint(StrandPalette.statusWarning)
        }
    }

    private var entry: PainEntry? {
        guard reason == .pain, let area else { return nil }
        return PainEntry(area: area, date: Date(), kind: spot ? .spot : .rating(score ?? 0), side: side,
                         feel: feel, backPain: backPain)
    }

    private var advice: StopAdvice? {
        guard let reason else { return nil }
        if reason == .pain && (area == nil || score == nil) && !spot { return nil }
        return StopAdvice.after(reason: reason, score: score, spot: spot, nerveSign: entry?.nerveSign ?? false,
                                breathingWarning: breathingWarning)
    }

    private var canSave: Bool {
        guard let reason else { return false }
        return reason != .pain || (area != nil && (score != nil || spot))
    }

    private func save() {
        guard let reason else { return }
        let stop = RunStop(date: Date(), week: session.week, day: session.day, reason: reason,
                           painScore: reason == .pain ? score : nil, area: reason == .pain ? area : nil)
        onSave(stop, entry.map { [$0] } ?? [])
        dismiss()
    }

    private func question<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            content()
        }
    }

    private func adviceCard(_ advice: StopAdvice) -> some View {
        let tint = advice == .urgent ? StrandPalette.statusCritical
            : advice == .walkHomeGetChecked ? StrandPalette.statusWarning : StrandPalette.accent
        return Text(advice.text)
            .font(StrandFont.body.weight(.semibold))
            .foregroundStyle(StrandPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint, lineWidth: 1))
    }
}

/// A row of capsule choices, one selected, in the app's chip style.
struct ChoiceChips<Option: Hashable>: View {
    let options: [Option]
    let label: KeyPath<Option, String>
    let selected: Option?
    var tint: Color = StrandPalette.accent
    /// The unselected fill; on an inset panel, pass a colour that stands out from it.
    var fill: Color = StrandPalette.surfaceInset
    let onSelect: (Option) -> Void

    var body: some View {
        WrapLayout(spacing: 8) { chips }
    }

    @ViewBuilder private var chips: some View {
        ForEach(options, id: \.self) { option in
            let isOn = option == selected
            Button { onSelect(option) } label: {
                Text(option[keyPath: label])
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(isOn ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(isOn ? tint.opacity(0.28) : fill))
                    .overlay(Capsule().stroke(isOn ? tint : .clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }
}

/// Lays children out left to right, wrapping onto new lines, so a row of chips never turns into a column.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += size.width + gap
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// When to stop and get something checked (D53). Advice, not a diagnosis.
struct RedFlagSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Sore muscles for a day or two after a run are normal. These are the signs that aren't.")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    flag("Stop running and get it checked by a GP or physio",
                         ["Pain in one small spot on a bone that hurts to press with a fingertip",
                          "Pain that starts sooner each run, or hurts at rest or at night",
                          "Pain that's worse each morning"],
                         note: "These can be a bone stress injury. Caught early, most settle with less load.",
                         tint: StrandPalette.statusWarning)
                    flag("See a physio",
                         ["Achilles or heel stiffness on your first steps in the morning, getting worse week by week"],
                         note: "Early advice helps; the usual treatment is the right kind of exercise.",
                         tint: StrandPalette.statusWarning)
                    flag("Get urgent help (your local emergency number)",
                         ["Chest pain, fainting or severe breathlessness while exercising",
                          "A hot, red, swollen calf",
                          "Unable to put weight on a leg after a fall or twist"],
                         note: nil, tint: StrandPalette.statusCritical)
                    Text("Never push through sharp pain. Repeating a C25K week is always fine.")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .padding(20)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle("When to get it checked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func flag(_ title: String, _ signs: [String], note: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(tint)
            ForEach(signs, id: \.self) { sign in
                Label(sign, systemImage: "exclamationmark.circle")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Text(note)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised))
    }
}

/// The back flare path (D104; research 05 §6): what rests, what carries on, and when to get it checked.
/// Shown while a flare is on.
struct BackFlareCard: View {
    let flare: BackFlare

    var body: some View {
        let flags = RedFlags.for(.lowerBack)
        StrandCard(padding: 18, tint: StrandPalette.statusWarning) {
            VStack(alignment: .leading, spacing: 12) {
                RegimenOverline(text: "Back flare", color: StrandPalette.statusWarning)
                Text(flare.easy(now: Date())
                     ? "Easy until \(flare.easyUntil.formatted(.dateTime.weekday(.wide).hour().minute()))"
                     : "The morning check decides now")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                line("pause.circle", "Resting: runs, lifting and Core B for the first 48 hours. After that, \"less\" or \"gone\" in the morning brings them back at last week's level.")
                line("figure.walk", "Carry on: walking, the rest-day routine, lying face down if that helps, and the Big 3 only if it doesn't bring symptoms on.")
                if flare.seeClinician {
                    line("cross.case", flare.nerveSign
                         ? "Tingling or numbness came with it: see a GP or physio before training again."
                         : "It's been about a week: worth seeing a GP or physio.", tint: StrandPalette.statusWarning)
                } else {
                    line("cross.case", "See a GP or physio if it lasts about a week, spreads, or brings numbness, tingling or weakness.")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Get urgent help (your local emergency number)")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.statusCritical)
                    ForEach(flags.urgent, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(StrandPalette.statusCritical).frame(width: 5, height: 5)
                            Text(item)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("Advice to show, not a diagnosis.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func line(_ icon: String, _ text: String, tint: Color = StrandPalette.textSecondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
