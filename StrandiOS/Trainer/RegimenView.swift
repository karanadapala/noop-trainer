import SwiftUI
import StrandDesign
import TrainerKit

/// Screens the Regimen links to, pushed as values so the tab's re-tap pops them (#198).
enum RegimenRoute: Hashable {
    case c25k, c25kHistory, places, health
}

/// The Regimen tab (D139): every active plan for today, under the goals they serve (D124). The goal
/// rail across the top shows which goals have a plan and what each one asks of today; the card below
/// it is the one thing to do next.
struct RegimenView: View {
    @ObservedObject private var runner = C25KRunner.shared
    @ObservedObject private var store = RegimenStore.shared

    /// The active plans, the main goal's plan first (D86: it wins a clash).
    private var plans: [any TrainingPlan] { [runner.plan] }
    private var day: RegimenDay { RegimenDay(plans: plans, now: Date()) }

    var body: some View {
        ScreenScaffold(title: "Regimen", subtitle: "Every plan, one day at a time.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                GoalRail(plans: plans, day: day)
                nextCard
                plansSection
                setupSection
            }
        }
        .onAppear { runner.applyRestartIfReady() }
        .navigationDestination(for: RegimenRoute.self) { route in
            Group {
                switch route {
                case .c25k: C25KView()
                case .c25kHistory: C25KHistoryView()
                case .places: PlacesView()
                case .health: HealthProfileView()
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: Next

    @ViewBuilder
    private var nextCard: some View {
        if let next = day.next, let plan = plans.first(where: { $0.id == next.planID }) {
            StrandCard(padding: 20, tint: StrandPalette.effortColor) {
                VStack(alignment: .leading, spacing: 14) {
                    RegimenOverline(text: "Next · \(plan.title)", color: StrandPalette.effortColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(next.headline)
                            .font(StrandFont.rounded(30))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(next.detail)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    NavigationLink(value: route(for: plan.id)) {
                        Label("Go to the session", systemImage: "play.fill")
                    }
                    .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                }
            }
        } else if let held = day.plans.first(where: { $0.status == .hold }),
                  let plan = plans.first(where: { $0.id == held.planID }) {
            StrandCard(padding: 20, tint: StrandPalette.statusWarning) {
                VStack(alignment: .leading, spacing: 10) {
                    RegimenOverline(text: "On hold · \(plan.title)", color: StrandPalette.statusWarning)
                    Text(held.headline)
                        .font(StrandFont.rounded(26))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(held.detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink(value: route(for: plan.id)) {
                        Label("Open \(plan.title)", systemImage: "arrow.right")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            StrandCard(padding: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    RegimenOverline(text: "Today", color: StrandPalette.restColor)
                    Text(day.plans.contains { $0.status == .done } ? "Done for today" : "A rest day")
                        .font(StrandFont.rounded(26))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Nothing else is due. Recovery is part of the plan.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private func route(for planID: String) -> RegimenRoute {
        switch planID {
        default: return .c25k
        }
    }

    // MARK: Plans

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plans").strandOverline()
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(zip(plans.indices, day.plans)), id: \.0) { i, today in
                        let plan = plans[i]
                        NavigationLink(value: route(for: plan.id)) {
                            PlanRow(title: plan.title, goals: plan.goals, today: today)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Setup

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup").strandOverline()
            NoopCard(padding: 0) {
                VStack(spacing: 0) {
                    SetupRow(title: "Places", detail: placesDetail, icon: "mappin.and.ellipse", route: .places)
                    Divider().overlay(StrandPalette.hairline).padding(.leading, 56)
                    SetupRow(title: "Health profile", detail: healthDetail, icon: "cross.case", route: .health)
                    Divider().overlay(StrandPalette.hairline).padding(.leading, 56)
                    SetupRow(title: "C25K history", detail: "Change or delete any answer",
                             icon: "clock.arrow.circlepath", route: .c25kHistory)
                }
            }
        }
    }

    private var placesDetail: String {
        store.places.map(\.name).joined(separator: ", ")
    }

    private var healthDetail: String {
        let n = store.health.injuries.count
        return n == 0 ? "Injuries and what to watch for" : n == 1 ? "1 injury on file" : "\(n) injuries on file"
    }
}

/// The four goals side by side (D124). Each column is lit by what its plan asks of today: a session,
/// rest, done, a hold, or no plan yet. Read left to right it's the whole regime at a glance.
private struct GoalRail: View {
    let plans: [any TrainingPlan]
    let day: RegimenDay

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Goal.allCases, id: \.self) { goal in
                column(goal)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func column(_ goal: Goal) -> some View {
        let plan = plans.first { $0.goals.contains(goal) }
        let today = plan.flatMap { p in day.plans.first { $0.planID == p.id } }
        let tone = Self.tone(today?.status)
        return VStack(alignment: .leading, spacing: 6) {
            Capsule()
                .fill(plan == nil ? StrandPalette.textTertiary.opacity(0.22) : tone)
                .frame(height: 4)
            Text(goal.label)
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(plan == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
            if let plan {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.title)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Text(Self.word(today?.status))
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(tone)
                }
            } else {
                Text("No plan yet")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func tone(_ status: PlanToday.Status?) -> Color {
        switch status {
        case .session: return StrandPalette.effortColor
        case .rest: return StrandPalette.restColor
        case .done, .finished: return StrandPalette.statusPositive
        case .hold: return StrandPalette.statusWarning
        case nil: return StrandPalette.hairlineStrong
        }
    }

    static func word(_ status: PlanToday.Status?) -> String {
        switch status {
        case .session: return "Today"
        case .rest: return "Rest day"
        case .done: return "Done"
        case .finished: return "Complete"
        case .hold: return "On hold"
        case nil: return ""
        }
    }
}

private struct PlanRow: View {
    let title: String
    let goals: [Goal]
    let today: PlanToday

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(GoalRail.tone(today.status))
                .frame(width: 10, height: 10)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(StrandFont.body.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(goals.map(\.label).joined(separator: " · "))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Text(today.status == .session || today.status == .hold ? today.headline : today.detail)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SetupRow: View {
    let title: LocalizedStringKey
    let detail: String
    let icon: String
    let route: RegimenRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 26, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(detail)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The small uppercase label at the top of a Regimen card.
struct RegimenOverline: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking * 4)
            .foregroundStyle(color)
    }
}

/// The Regimen on Today (D139): the goal rail and today's next action; a tap opens the Regimen tab.
/// Removable like any Today card, in Customise.
struct RegimenTodayCard: View {
    @EnvironmentObject private var router: NavRouter
    @ObservedObject private var runner = C25KRunner.shared

    private var plans: [any TrainingPlan] { [runner.plan] }

    var body: some View {
        let day = RegimenDay(plans: plans, now: Date())
        let held = day.plans.first { $0.status == .hold }
        let shown = day.next ?? held
        let plan = shown.flatMap { s in plans.first { $0.id == s.planID } }
        Button { router.requestedDestination = .regimen } label: {
            StrandCard(padding: 18, tint: day.next != nil ? StrandPalette.effortColor : nil) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        RegimenOverline(text: "Regimen", color: day.next != nil ? StrandPalette.effortColor : StrandPalette.textTertiary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if let shown, let plan {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(shown.status == .hold ? "\(plan.title) on hold" : "\(plan.title) · \(shown.headline)")
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(shown.detail)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text(day.plans.contains { $0.status == .done } ? "Done for today" : "A rest day: nothing due")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    GoalRail(plans: plans, day: day)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Regimen")
    }
}
