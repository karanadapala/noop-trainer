import SwiftUI
import StrandDesign
import TrainerKit

/// Which goals you're training for (D124, D191). Only the goals picked here, plus any an active plan
/// serves, show on the Regimen. A goal with a running plan stays on until that plan is stopped.
struct GoalsView: View {
    @ObservedObject private var store = RegimenStore.shared
    @ObservedObject private var runner = C25KRunner.shared
    @ObservedObject private var heavyDuty = HeavyDutyStore.shared

    private var plans: [any TrainingPlan] { ActivePlans.all() }

    var body: some View {
        ScreenScaffold(title: "Goals", subtitle: "Pick what you're training for. The Regimen shows only these.") {
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(Goal.allCases.enumerated()), id: \.element) { i, goal in
                        if i > 0 { Divider().overlay(StrandPalette.hairline).padding(.leading, 16) }
                        row(goal)
                    }
                }
            }
        }
    }

    private func row(_ goal: Goal) -> some View {
        let serving = plans.filter { $0.goals.contains(goal) }.map(\.title)
        return Toggle(isOn: Binding(
            get: { !serving.isEmpty || store.goals.contains(goal) },
            set: { on in
                if on { store.goals.append(goal) } else { store.goals.removeAll { $0 == goal } }
            })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.label)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(serving.isEmpty ? Self.covers(goal) : "\(serving.joined(separator: ", ")) is under this goal")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(StrandPalette.accent)
        .disabled(!serving.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    static func covers(_ goal: Goal) -> String {
        switch goal {
        case .cardio: return "Running, the bike, the rower"
        case .strength: return "Lifting"
        case .mobility: return "Back care and stretching"
        case .combat: return "Boxing, Muay Thai and other club classes"
        }
    }
}
