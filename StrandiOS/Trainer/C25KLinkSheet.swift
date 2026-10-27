import SwiftUI
import StrandDesign
import WhoopStore
import TrainerKit

/// Lists recent workouts recorded by NOOP or imported from Apple Health so a C25K day done before the
/// coach existed (or without it) can be linked and counted as done.
struct C25KLinkSheet: View {
    let session: GuidedSession
    let onLink: (C25KLogEntry) -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Candidate] = []
    @State private var loaded = false

    /// How far back to look. C25K is 9 weeks, so a little more than that.
    private static let lookbackDays = 70

    struct Candidate: Identifiable {
        let row: WorkoutRow
        let source: C25KLogEntry.Source
        var id: String { "\(source.rawValue)-\(row.startTs)-\(row.sport)" }
        var durationS: Int { Int(row.durationS ?? Double(row.endTs - row.startTs)) }
        var isRunOrWalk: Bool {
            let s = row.sport.lowercased()
            return s.contains("run") || s.contains("walk") || s.contains("jog")
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView()
                } else if rows.isEmpty {
                    Text("No workouts in the last \(Self.lookbackDays) days.")
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding()
                } else {
                    List(rows) { c in
                        Button { link(c) } label: { row(c) }
                    }
                }
            }
            .navigationTitle("Week \(session.week), day \(session.day)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func row(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(c.row.sport)
                    .font(StrandFont.headline)
                    .foregroundStyle(c.isRunOrWalk ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                Spacer()
                Text(c.source.label)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Text(Self.summary(start: c.row.startTs, durationS: c.durationS, avgHr: c.row.avgHr,
                              distanceM: c.row.distanceM))
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func link(_ c: Candidate) {
        onLink(C25KLogEntry(startTs: c.row.startTs, durationS: c.durationS, avgHr: c.row.avgHr,
                            distanceM: c.row.distanceM, source: c.source))
        dismiss()
    }

    private func load() async {
        defer { loaded = true }
        guard let store = await model.repo.storeHandle() else { return }
        let now = Int(Date().timeIntervalSince1970)
        let from = now - Self.lookbackDays * 86_400
        let strap = (try? await store.workouts(deviceId: model.repo.deviceId, from: from, to: now, limit: 500)) ?? []
        let health = (try? await store.workouts(deviceId: "apple-health", from: from, to: now, limit: 500)) ?? []
        let all = strap.map { Candidate(row: $0, source: WorkoutSource.isAppleHealth($0.source) ? .appleHealth : .noop) }
            + health.map { Candidate(row: $0, source: .appleHealth) }
        // Runs and walks first, then everything else, newest first within each.
        rows = all.sorted {
            if $0.isRunOrWalk != $1.isRunOrWalk { return $0.isRunOrWalk }
            return $0.row.startTs > $1.row.startTs
        }
    }

    /// "Fri 24 Oct, 18:05 · 31 min · 142 bpm · 3.1 km"
    static func summary(start: Int, durationS: Int, avgHr: Int?, distanceM: Double?) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(start))
        var parts = [date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()),
                     "\(max(1, durationS / 60)) min"]
        if let avgHr, avgHr > 0 { parts.append("\(avgHr) bpm") }
        if let distanceM, distanceM > 50 { parts.append(String(format: "%.1f km", distanceM / 1000)) }
        return parts.joined(separator: " · ")
    }
}
