import SwiftUI
import StrandDesign
import TrainerKit

/// Everything C25K has logged, each answer changeable or deletable (D151). Holds, trends and the way
/// back are worked out from the log, so they follow the correction by themselves. A restart that has
/// already moved the plan stays where it is; the history says so before deleting what caused it.
struct C25KHistoryView: View {
    @ObservedObject private var runner = C25KRunner.shared

    /// The pain answer whose 0–10 value is being changed.
    @State private var changing: PainEntry?
    @State private var pendingDelete: PendingDelete?

    private enum PendingDelete: Identifiable {
        case stop(RunStop), gate(GateEntry)

        var id: String {
            switch self {
            case .stop(let s): return "stop\(s.date.timeIntervalSince1970)"
            case .gate(let g): return "gate\(g.date.timeIntervalSince1970)\(g.step.rawValue)"
            }
        }
    }

    var body: some View {
        ScreenScaffold(title: "C25K history",
                       subtitle: "Change or delete any answer. Holds and the way back are worked out again from what's left.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                painSection
                if !runner.stops.isEmpty { stopsSection }
                if !runner.gates.isEmpty { gatesSection }
                runsSection
            }
        }
        .confirmationDialog("This already moved your plan", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete it anyway", role: .destructive) {
                switch pendingDelete {
                case .stop(let s): runner.deleteStop(s)
                case .gate(let g): runner.deleteGate(g)
                case nil: break
                }
                pendingDelete = nil
            }
            Button("Keep it", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("The restart it led to stays as it is. If the plan should move forward again, mark the days done on the C25K screen.")
        }
    }

    // MARK: Pain

    private var painSection: some View {
        section("Pain answers", empty: runner.pain.isEmpty ? "No pain answers." : nil) {
            ForEach(Array(runner.pain.enumerated().reversed()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 10) {
                    row(title: "\(entry.area.label) · \(Self.painText(entry))",
                        detail: Self.when(entry.date)) {
                        if entry.kind != .spot {
                            Button("Change the number", systemImage: "slider.horizontal.3") { changing = entry }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { runner.deletePain(entry) }
                    }
                    if changing == entry {
                        PainScaleRow(selected: entry.value) { score in
                            runner.changePain(entry, to: score)
                            changing = nil
                        }
                        Button("Keep it as it was") { changing = nil }
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.accent)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    static func painText(_ e: PainEntry) -> String {
        switch e.kind {
        case .report(let level): return level.label
        case .rating(let n): return "\(n)/10"
        case .spot: return "Sharp, one spot"
        case .trend(let t): return [e.score.map { "\($0)/10" }, t.label].compactMap { $0 }.joined(separator: " · ")
        }
    }

    // MARK: Stops and checks

    private var stopsSection: some View {
        section("Stopped runs") {
            ForEach(Array(runner.stops.enumerated().reversed()), id: \.offset) { _, stop in
                let reason = [stop.reason.label, stop.area?.label, stop.painScore.map { "\($0)/10" }]
                    .compactMap { $0 }.joined(separator: " · ")
                row(title: "Week \(stop.week) · Day \(stop.day): \(reason)", detail: Self.when(stop.date)) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if runner.appliedRestartStop == stop { pendingDelete = .stop(stop) } else { runner.deleteStop(stop) }
                    }
                }
            }
        }
    }

    private var gatesSection: some View {
        section("Getting back to running") {
            ForEach(Array(runner.gates.enumerated().reversed()), id: \.offset) { _, gate in
                row(title: "\(Self.stepText(gate.step)): \(gate.passed ? "passed" : "not yet")", detail: Self.when(gate.date)) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        if let applied = runner.appliedRestartStop, gate.date > applied.date {
                            pendingDelete = .gate(gate)
                        } else {
                            runner.deleteGate(gate)
                        }
                    }
                }
            }
        }
    }

    static func stepText(_ step: GateEntry.Step) -> String {
        switch step {
        case .basics: return "Morning basics"
        case .walk: return "Brisk walk"
        case .hopAndHeel: return "Hops and heel raises"
        }
    }

    // MARK: Runs

    private var runsSection: some View {
        let done = runner.log.sorted { $0.value.date > $1.value.date }
        return section("Runs", empty: done.isEmpty && runner.archivedRuns.isEmpty ? "No runs yet." : nil) {
            ForEach(done, id: \.key) { key, entry in
                row(title: Self.runTitle(key), detail: Self.runDetail(entry)) {
                    if let s = C25KRunner.session(fromKey: key) {
                        Button("Mark not done", systemImage: "arrow.uturn.backward") { runner.setCompleted(s, false) }
                    }
                }
            }
            ForEach(runner.archivedRuns, id: \.key) { key, entry in
                row(title: Self.runTitle(key) + " (earlier time through)", detail: Self.runDetail(entry), menu: nil as EmptyView?)
            }
        }
    }

    static func runTitle(_ key: String) -> String {
        guard let s = C25KRunner.session(fromKey: key) else { return key }
        return "Week \(s.week) · Day \(s.day)"
    }

    static func runDetail(_ e: C25KLogEntry) -> String {
        [when(e.date), "\(e.durationS / 60) min", e.source.label].joined(separator: " · ")
    }

    // MARK: Layout

    static func when(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    private func section<Content: View>(_ title: String, empty: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        let rows = content()
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).strandOverline()
            NoopCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    if let empty {
                        Text(empty).font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    }
                    rows
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row<M: View>(title: String, detail: String, @ViewBuilder menu: () -> M) -> some View {
        row(title: title, detail: detail, menu: Optional(menu()))
    }

    private func row<MenuContent: View>(title: String, detail: String, menu: MenuContent?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 8)
            if let menu {
                Menu { menu } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Change or delete")
            }
        }
    }
}
