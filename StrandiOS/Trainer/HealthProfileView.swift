import SwiftUI
import StrandDesign
import TrainerKit

/// One health profile for every plan (D136): injuries in your own words, what clinicians said, and the
/// signs that mean stop and get checked for each part of the body on file. Stored on the phone only.
struct HealthProfileView: View {
    @ObservedObject private var store = RegimenStore.shared
    @State private var editing: Injury?

    var body: some View {
        ScreenScaffold(title: "Health profile",
                       subtitle: "Injuries and what clinicians said. Every plan reads this; it stays on your phone.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    if store.health.injuries.isEmpty {
                        Text("Nothing on file yet. Add past and current injuries so every plan can take them into account.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(store.health.active + store.health.injuries.filter { $0.status == .settled }) { injury in
                        Button { editing = injury } label: { card(injury) }
                            .buttonStyle(.plain)
                    }
                    NoopButton("Add an injury", systemImage: "plus", kind: .secondary, fullWidth: true) {
                        editing = Injury(region: .lowerBack, title: "")
                    }
                }
                if !store.health.regions.isEmpty { watchFor }
            }
        }
        .fadesNavigationBarOnScroll()
        .sheet(item: $editing) { injury in
            InjuryEditor(injury: injury, isNew: !store.health.injuries.contains { $0.id == injury.id },
                         onSave: { store.save($0) }, onDelete: { store.deleteInjury(injury.id) })
        }
    }

    private func card(_ injury: Injury) -> some View {
        StrandCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(injury.title)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    StatePill(LocalizedStringKey(injury.status.label), tone: injury.status == .active ? .warning : .neutral)
                }
                Text([injury.region.label, injury.side?.label, injury.since.isEmpty ? nil : "since \(injury.since)"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                if !injury.cliniciansSaid.isEmpty {
                    Text(injury.cliniciansSaid)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var watchFor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What to watch for").strandOverline()
            ForEach(store.health.regions, id: \.self) { region in
                let flags = RedFlags.for(region)
                StrandCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(region.label)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        flagList("Get urgent help (your local emergency number)", flags.urgent, tint: StrandPalette.statusCritical)
                        flagList("Stop that kind of training and see a GP or physio", flags.soon, tint: StrandPalette.statusWarning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Advice to show, not a diagnosis.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func flagList(_ title: String, _ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(tint).frame(width: 5, height: 5)
                    Text(item)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct InjuryEditor: View {
    let isNew: Bool
    let onSave: (Injury) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var injury: Injury
    @State private var confirmDelete = false

    init(injury: Injury, isNew: Bool, onSave: @escaping (Injury) -> Void, onDelete: @escaping () -> Void) {
        _injury = State(initialValue: injury)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool { !injury.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("What it is") {
                        field("Disc bulge, shin pain, sprained ankle…", text: $injury.title)
                    }
                    section("Where") {
                        Picker("Where", selection: $injury.region) {
                            ForEach(BodyRegion.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(StrandPalette.accent)
                        Picker("Side", selection: $injury.side) {
                            Text("Not one side").tag(PainSide?.none)
                            ForEach(PainSide.allCases, id: \.self) { Text($0.label).tag(PainSide?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                    section("Since") {
                        field("2019, Oct 2026…", text: $injury.since)
                    }
                    section("Now") {
                        Picker("Now", selection: $injury.status) {
                            ForEach(Injury.Status.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    section("What a GP, physio or scan said") {
                        field("Diagnosis, advice, what to avoid", text: $injury.cliniciansSaid, multiline: true)
                    }
                    section("Notes") {
                        field("What sets it off, what helps", text: $injury.notes, multiline: true)
                    }
                    if !isNew {
                        NoopButton("Delete this injury", systemImage: "trash", kind: .tertiary) { confirmDelete = true }
                    }
                }
                .padding(20)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle(isNew ? "Add an injury" : "Edit injury")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        injury.title = injury.title.trimmingCharacters(in: .whitespaces)
                        onSave(injury)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this injury?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete(); dismiss() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).strandOverline()
            content()
        }
    }

    private func field(_ prompt: String, text: Binding<String>, multiline: Bool = false) -> some View {
        TextField(prompt, text: text, axis: multiline ? .vertical : .horizontal)
            .lineLimit(multiline ? 3...8 : 1...1)
            .font(StrandFont.body)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(StrandPalette.surfaceOverlay))
    }
}
