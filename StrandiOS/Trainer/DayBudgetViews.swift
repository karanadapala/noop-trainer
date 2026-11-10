import Combine
import SwiftUI
import StrandDesign
import TrainerKit

/// Today's time settings (D230, D235) under `trainer.budget.options`.
@MainActor
final class DayBudgetStore: ObservableObject {
    static let shared = DayBudgetStore()

    @Published var options: DayBudgetOptions {
        didSet { if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: Self.key) } }
    }

    private static let key = "trainer.budget.options"

    private init() {
        options = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(DayBudgetOptions.self, from: $0) } ?? DayBudgetOptions()
    }
}

extension ActivePlans {
    /// How long today takes, from the same funnel as everything else on the Regimen.
    static func budget(now: Date = Date()) -> DayBudget {
        DayBudget(plans: all(), day: day(now: now), options: DayBudgetStore.shared.options)
    }
}

/// Today's whole regimen as one length, before anything starts (D235): the user wants to know up front,
/// because finding out mid-way is what turns into "tomorrow". One bar, a segment per session in the order
/// they come, then the time to get going; done sessions drop out of the total.
struct DayBudgetBanner: View {
    let budget: DayBudget
    @ObservedObject private var store = DayBudgetStore.shared

    var body: some View {
        if budget.clear {
            if !budget.items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(StrandPalette.statusPositive)
                    Text("Today's regimen is done")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(budget.items.contains(where: \.done) ? "Left today" : "Today")
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                        Text("About \(DayBudget.spoken(budget.minutes))")
                            .font(StrandFont.rounded(24))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Keep free")
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                        Text(DayBudget.spoken(budget.keepFree))
                            .font(StrandFont.rounded(24))
                            .foregroundStyle(StrandPalette.effortColor)
                    }
                }
                bar
                WrapLayout(spacing: 12) {
                    ForEach(budget.items, id: \.planID) { item in
                        legend(item.title, item.minutes.map { "\($0)" } ?? "done", done: item.done)
                    }
                    legend("Getting going", "\(budget.buffer)", done: false, muted: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(StrandPalette.surfaceInset))
            .accessibilityElement(children: .combine)
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let parts = budget.items.compactMap(\.minutes) + [budget.buffer]
            let gap: CGFloat = 3
            let total = CGFloat(max(1, parts.reduce(0, +)))
            let width = geo.size.width - gap * CGFloat(max(0, parts.count - 1))
            HStack(spacing: gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, m in
                    Capsule()
                        .fill(i == parts.count - 1 ? StrandPalette.hairlineStrong : StrandPalette.effortColor.opacity(i % 2 == 0 ? 1 : 0.6))
                        .frame(width: max(4, width * CGFloat(m) / total))
                }
            }
        }
        .frame(height: 8)
    }

    private func legend(_ title: String, _ value: String, done: Bool, muted: Bool = false) -> some View {
        HStack(spacing: 4) {
            if done {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(StrandPalette.statusPositive)
            }
            Text(title)
                .foregroundStyle(muted ? StrandPalette.textTertiary : StrandPalette.textSecondary)
            Text(done ? "" : value)
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .font(StrandFont.caption)
        .strikethrough(done, color: StrandPalette.textTertiary)
    }
}

/// Settings for today's time: how long it takes to get going at each place, and the rounding (D230).
struct DayBudgetSettingsView: View {
    @ObservedObject private var store = DayBudgetStore.shared
    @ObservedObject private var regimen = RegimenStore.shared

    var body: some View {
        ScreenScaffold(title: "Time", subtitle: "How long today's regimen takes, worked out before you start.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Getting going, per place").strandOverline()
                    NoopCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Changing, the walk there, setting up. Counted once for each place you train at that day.")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(regimen.places) { place in
                                Stepper(value: Binding(get: { store.options.buffer(at: place.id) },
                                                       set: { store.options.buffers[place.id] = $0 }), in: 0...90, step: 5) {
                                    row(place.name, "\(store.options.buffer(at: place.id)) min")
                                }
                            }
                            Stepper(value: $store.options.otherBuffer, in: 0...90, step: 5) {
                                row("Anywhere else", "\(store.options.otherBuffer) min")
                            }
                            Divider().overlay(StrandPalette.hairline)
                            Stepper(value: $store.options.roundTo, in: 5...30, step: 5) {
                                row("\"Keep free\" rounds up to", "\(store.options.roundTo) min")
                            }
                        }
                    }
                }
            }
        }
        .fadesNavigationBarOnScroll()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Text(value).font(StrandFont.subhead.monospacedDigit()).foregroundStyle(StrandPalette.textSecondary)
        }
    }
}
