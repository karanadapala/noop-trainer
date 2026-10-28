import SwiftUI
import StrandDesign
import TrainerKit

/// A session drawn to scale: one block per segment, width = duration, runs tall in the Effort colour,
/// walks low in the Rest colour. While running, everything ahead of the playhead dims.
struct SessionStrip: View {
    let session: GuidedSession
    /// Active session time; nil draws the plan without a playhead.
    var elapsed: TimeInterval? = nil
    var height: CGFloat = 36

    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let widths = blockWidths(total: geo.size.width)
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(session.segments.enumerated()), id: \.offset) { i, seg in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(seg.kind).opacity(opacity(i, seg)))
                            .frame(width: widths[i], height: blockHeight(seg.kind))
                    }
                }
                if let elapsed {
                    Capsule()
                        .fill(StrandPalette.textPrimary)
                        .frame(width: 3, height: height + 8)
                        .offset(x: playheadX(elapsed, widths: widths) - 1.5, y: 4)
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .bottomLeading)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private func blockWidths(total: CGFloat) -> [CGFloat] {
        let n = session.segments.count
        let usable = max(0, total - gap * CGFloat(n - 1))
        let seconds = Double(max(1, session.totalSeconds))
        return session.segments.map { usable * CGFloat(Double($0.seconds) / seconds) }
    }

    private func playheadX(_ t: TimeInterval, widths: [CGFloat]) -> CGFloat {
        guard let i = session.segmentIndex(at: t) else { return widths.reduce(0, +) + gap * CGFloat(widths.count - 1) }
        let before = widths.prefix(i).reduce(0, +) + gap * CGFloat(i)
        let into = (t - Double(session.segmentStarts[i])) / Double(session.segments[i].seconds)
        return before + widths[i] * CGFloat(min(max(into, 0), 1))
    }

    private func blockHeight(_ kind: Segment.Kind) -> CGFloat {
        kind.isRun ? height : height * 0.38
    }

    private func color(_ kind: Segment.Kind) -> Color {
        kind.isRun ? StrandPalette.effortColor : StrandPalette.restColor
    }

    private func opacity(_ i: Int, _ seg: Segment) -> Double {
        let base = (seg.kind == .warmUp || seg.kind == .coolDown) ? 0.55 : 1
        guard let elapsed else { return base }
        // Done and current segments stay lit; the ones still ahead dim.
        return elapsed >= Double(session.segmentStarts[i]) ? base : base * 0.3
    }

    private var accessibilitySummary: String {
        "\(session.runCount) runs, \(session.totalSeconds / 60) minutes in total"
    }
}

/// The whole program as 27 bars, one per session, grouped by week. A bar's height is that session's
/// longest continuous run (square-root scale, so the early 1–5 minute weeks still read as a climb).
/// A small dot after a bar is a rest-day routine done before the next run (D45): run, rest, run.
struct PlanLadder: View {
    let isDone: (GuidedSession) -> Bool
    let next: GuidedSession
    let selectedWeek: Int
    /// Rest days with a routine after each run, by session key ("w2d1").
    var restAfter: [String: Int] = [:]
    var attempt: (Int) -> Int = { _ in 1 }
    let onSelectWeek: (Int) -> Void

    private let barArea: CGFloat = 64
    private static let longestInPlan = Double(C25K.all.map(longestRun).max() ?? 1800)

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(1...C25K.weeks, id: \.self) { w in
                Button { onSelectWeek(w) } label: { week(w) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weekLabel(w))
            }
        }
    }

    private func week(_ w: Int) -> some View {
        let isSelected = w == selectedWeek
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(1...C25K.daysPerWeek, id: \.self) { d in
                    if let s = C25K.session(week: w, day: d) {
                        bar(s)
                        restDots(restAfter["w\(w)d\(d)"] ?? 0)
                    }
                }
            }
            .frame(height: barArea, alignment: .bottom)
            Text("\(w)")
                .font(StrandFont.captionNumber)
                .foregroundStyle(isSelected ? StrandPalette.textPrimary : StrandPalette.textTertiary)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? StrandPalette.textPrimary.opacity(0.06) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? StrandPalette.hairlineStrong : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func bar(_ s: GuidedSession) -> some View {
        let isNext = s.week == next.week && s.day == next.day && !isDone(s)
        let fill: Color = isDone(s) ? StrandPalette.accent
            : isNext ? StrandPalette.effortColor
            : StrandPalette.textTertiary.opacity(0.28)
        let h = 6 + (barArea - 6) * CGFloat((Double(Self.longestRun(s)) / Self.longestInPlan).squareRoot())
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fill)
            .frame(maxWidth: .infinity)
            .frame(height: h)
    }

    /// Up to two stacked dots: one or two rest days with a routine after this run.
    private func restDots(_ count: Int) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<min(count, 2), id: \.self) { _ in
                Circle().fill(StrandPalette.restColor).frame(width: 3, height: 3)
            }
        }
        .frame(width: 3)
    }

    private func weekLabel(_ w: Int) -> String {
        let done = (1...C25K.daysPerWeek).compactMap { C25K.session(week: w, day: $0) }.filter(isDone).count
        let rest = (1...C25K.daysPerWeek).map { restAfter["w\(w)d\($0)"] ?? 0 }.reduce(0, +)
        var label = "Week \(w), \(done) of \(C25K.daysPerWeek) done"
        if rest > 0 { label += ", \(rest) rest-day routine\(rest == 1 ? "" : "s")" }
        if let again = WeekRestart.label(attempt: attempt(w)) { label += ", \(again)" }
        return label
    }

    static func longestRun(_ s: GuidedSession) -> Int {
        s.segments.filter(\.kind.isRun).map(\.seconds).max() ?? 0
    }
}
