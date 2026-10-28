import SwiftUI
import StrandDesign
import TrainerKit

/// The single-leg calf-raise test every 3 weeks (D57): you count, the app keeps the numbers so the
/// next test shows whether the calves got stronger (Hébert-Losier et al., Physiotherapy 2017).
struct CalfTestSheet: View {
    let last: CalfBenchmark?
    /// Calves or feet logged as hurting: the test waits until they're clear.
    let painful: Bool
    let onSave: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var left: Int
    @State private var right: Int

    init(last: CalfBenchmark?, painful: Bool, onSave: @escaping (Int, Int) -> Void) {
        self.last = last
        self.painful = painful
        self.onSave = onSave
        _left = State(initialValue: last?.left ?? 15)
        _right = State(initialValue: last?.right ?? 15)
    }

    private static let steps = [
        "Stand on one leg on the floor, fingertips on the wall for balance.",
        "Rise as high as you can, then lower. One rise every 2 seconds.",
        "Count until you can't rise as high or keep the pace.",
        "Rest a minute, then the other leg.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Every 3 weeks. Comparing the counts shows whether your calves are getting stronger, and whether one side lags.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if painful {
                        Label("Your calves or feet are logged as hurting. Do the test once they're clear; the coach will remind you.",
                              systemImage: "exclamationmark.triangle")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.statusWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(StrandFont.captionNumber)
                                    .foregroundStyle(StrandPalette.restColor)
                                    .frame(width: 14, alignment: .leading)
                                Text(step)
                                    .font(StrandFont.body)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        counter("Left leg", value: $left, previous: last?.left)
                        counter("Right leg", value: $right, previous: last?.right)
                    }

                    if let last {
                        Text("Last test: \(last.date.formatted(.dateTime.day().month(.abbreviated))).")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .padding(20)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle("Calf-raise test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(left, right)
                        dismiss()
                    }
                }
            }
        }
    }

    private func counter(_ title: String, value: Binding<Int>, previous: Int?) -> some View {
        VStack(spacing: 10) {
            Text(title.uppercased())
                .font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking * 4)
                .foregroundStyle(StrandPalette.textTertiary)
            Text("\(value.wrappedValue)")
                .font(StrandFont.display(56))
                .tracking(StrandFont.displayTracking(56))
                .foregroundStyle(StrandPalette.textPrimary)
                .contentTransition(.numericText())
            HStack(spacing: 10) {
                stepButton("minus", label: "One fewer") { value.wrappedValue = max(0, value.wrappedValue - 1) }
                stepButton("plus", label: "One more") { value.wrappedValue += 1 }
            }
            Text(previous.map { "Last time \($0)" } ?? " ")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(StrandPalette.surfaceRaised))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(value.wrappedValue) raises")
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 44, height: 36)
                .background(Capsule().fill(StrandPalette.surfaceInset))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
