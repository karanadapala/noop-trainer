import SwiftUI
import StrandDesign
import TrainerKit

/// "Anything hurting?": pick the areas, then how each one hurts (D38, D49). Used after a run and from
/// "Something hurts" on the C25K screen.
struct PainReportSheet: View {
    let title: String
    let onSave: ([PainEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var levels: [BodyArea: PainLevel] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tap where it hurts, then how it feels. Tomorrow morning the coach asks whether it's gone, less, the same or worse.")
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
                        onSave(levels.map { PainEntry(area: $0.key, date: now, kind: .report($0.value)) })
                        dismiss()
                    }
                    .disabled(levels.isEmpty)
                }
            }
        }
    }

    private func areaRow(_ area: BodyArea) -> some View {
        let on = levels[area] != nil
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                levels[area] = on ? nil : .mild
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
                ChoiceChips(options: PainLevel.allCases, label: \.label,
                            selected: levels[area], tint: StrandPalette.statusWarning) { levels[area] = $0 }
                if levels[area] == .sharp {
                    Text("Sharp pain in one spot is worth getting checked. The coach will show you when.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.statusWarning)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceRaised))
    }
}

/// A row of capsule choices, one selected, in the app's chip style.
struct ChoiceChips<Option: Hashable>: View {
    let options: [Option]
    let label: KeyPath<Option, String>
    let selected: Option?
    var tint: Color = StrandPalette.accent
    let onSelect: (Option) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) { chips }
        }
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
                    .background(Capsule().fill(isOn ? tint.opacity(0.28) : StrandPalette.surfaceInset))
                    .overlay(Capsule().stroke(isOn ? tint : .clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
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
