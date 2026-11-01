import SwiftUI
import StrandDesign
import TrainerKit

/// Where you train (D90, D91, D132): each place's unit, its kit and how much phone it allows. Plans
/// read this to pick exercises, round weights and decide how much to ask mid-session.
struct PlacesView: View {
    @ObservedObject private var store = RegimenStore.shared
    @State private var editing: Place?

    var body: some View {
        ScreenScaffold(title: "Places", subtitle: "What each place has, and how much you can use your phone there.") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.places) { place in
                    Button { editing = place } label: { card(place) }
                        .buttonStyle(.plain)
                }
                NoopButton("Add a place", systemImage: "plus", kind: .secondary, fullWidth: true) {
                    editing = Place(id: UUID().uuidString, name: "", unit: store.places.first?.unit ?? .kg,
                                    phone: .full, equipment: [])
                }
            }
        }
        .sheet(item: $editing) { place in
            PlaceEditor(place: place, isNew: store.place(id: place.id) == nil,
                        onSave: { store.save($0) }, onDelete: { store.deletePlace(place.id) })
        }
    }

    private func card(_ place: Place) -> some View {
        StrandCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(place.name)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    StatePill(LocalizedStringKey("Phone: \(place.phone.label)"), tone: place.phone == .full ? .neutral : .accent, showsDot: false)
                }
                Text(place.equipment.isEmpty ? "No equipment: bodyweight and running"
                     : place.equipment.map(\.kind.label).joined(separator: ", "))
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text("Weights in \(place.unit.label)")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PlaceEditor: View {
    let isNew: Bool
    let onSave: (Place) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var place: Place
    @State private var confirmDelete = false

    init(place: Place, isNew: Bool, onSave: @escaping (Place) -> Void, onDelete: @escaping () -> Void) {
        _place = State(initialValue: place)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Name") {
                        TextField("Gym, home, the club…", text: $place.name)
                            .font(StrandFont.body)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(StrandPalette.surfaceOverlay))
                    }
                    section("Weights in") {
                        Picker("Weights in", selection: $place.unit) {
                            ForEach(WeightUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    section("Phone during a session") {
                        VStack(spacing: 8) {
                            ForEach(PhoneAccess.allCases, id: \.self) { access in
                                choice(access.label, detail: access.detail, on: place.phone == access) {
                                    place.phone = access
                                }
                            }
                        }
                    }
                    section("Equipment") {
                        VStack(spacing: 8) {
                            ForEach(Equipment.Kind.allCases, id: \.self) { kind in
                                equipmentRow(kind)
                            }
                        }
                    }
                    if !isNew {
                        NoopButton("Delete this place", systemImage: "trash", kind: .tertiary) { confirmDelete = true }
                    }
                }
                .padding(20)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle(isNew ? "New place" : place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        place.name = place.name.trimmingCharacters(in: .whitespaces)
                        onSave(place)
                        dismiss()
                    }
                    .disabled(place.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(place.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
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

    private func choice(_ title: String, detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(on ? StrandPalette.accent : StrandPalette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Text(detail).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(StrandPalette.surfaceOverlay))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func equipmentRow(_ kind: Equipment.Kind) -> some View {
        let index = place.equipment.firstIndex { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { index != nil },
                set: { on in
                    if on { place.equipment.append(Equipment(kind)) } else { place.equipment.removeAll { $0.kind == kind } }
                })) {
                Text(kind.label).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            }
            .tint(StrandPalette.accent)
            if let index, kind.isWeighted {
                HStack(spacing: 8) {
                    weightField("Lightest", $place.equipment[index].lightest)
                    weightField("Heaviest", $place.equipment[index].heaviest)
                    weightField("Step", $place.equipment[index].step)
                }
                Text("Leave blank if you don't know; a \"Not on this machine\" tap during a set fills it in.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(StrandPalette.surfaceOverlay))
    }

    private func weightField(_ title: String, _ value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) (\(place.unit.label))")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
            TextField("–", value: value, format: .number)
                .keyboardType(.decimalPad)
                .font(StrandFont.bodyNumber)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(StrandPalette.surfaceBase))
        }
    }
}
