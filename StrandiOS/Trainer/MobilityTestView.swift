import SwiftUI
import StrandDesign
import TrainerKit

/// The Mobility test day (D148, D199; research 07 §5), one test per page: how to do it alone with a
/// phone, then the number. Any test can be skipped. Angles come from the Measure app's Level, with the
/// phone strapped to the shin or thigh.
struct MobilityTestView: View {
    let isBaseline: Bool
    let shinCleared: Bool
    let onSave: (MobilityTestResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var values: [MobilityMetric: Double] = [:]
    @State private var heelsDown = false
    @State private var hipsBelowKnees = false
    @State private var support = false
    @State private var nerveSign = false
    @State private var confidence: Int?

    private static let pages = 9

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Step \(page + 1) of \(Self.pages)")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                    content
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle(isBaseline ? "Baseline test day" : "Test day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if page > 0 {
                NoopButton("Back", kind: .secondary, fullWidth: true) { page -= 1 }
            }
            if page < Self.pages - 1 {
                NoopButton(page == 0 ? "Warm-up done" : "Next", kind: .primary, fullWidth: true) { page += 1 }
            } else {
                NoopButton("Save the test day", kind: .primary, fullWidth: true) {
                    onSave(MobilityTestResult(date: Date(), values: values,
                                              squatHeelsDown: values[.squatSeconds] != nil ? heelsDown : nil,
                                              squatHipsBelowKnees: values[.squatSeconds] != nil ? hipsBelowKnees : nil,
                                              squatSupport: values[.squatSeconds] != nil ? support : nil,
                                              confidence: confidence, nerveSign: nerveSign))
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(StrandPalette.surfaceBase)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case 0:
            test("Warm up first, the same way every time",
                 steps: ["A 5-minute easy walk.", "5 slow cat–camels.", "10 leg swings each side."],
                 note: "Barefoot, same floor, same phone. Three tries at each test; enter the best. Stop any test that brings something below the knee or into the big toe.")
        case 1:
            test("Fingertips to floor",
                 steps: ["Stand barefoot, feet together, knees straight.",
                         "Roll down slowly, arms and head hanging, breathing out. No bouncing.",
                         "Hold 2 seconds at the bottom and measure from your middle fingertip to the floor."],
                 note: "Past the floor? Stand on a step and enter it as a minus number.")
            field(.fingertips)
        case 2:
            test("Straight-leg raise",
                 steps: ["Lie on your back on the floor, other leg straight.",
                         "Strap the phone to the front of the shin; open Measure → Level and zero it lying flat.",
                         "Lift the straight leg slowly until the back of the thigh pulls or the knee starts to bend. Read the angle."],
                 note: "Right leg first.")
            field(.slrRight)
            field(.slrLeft)
            Toggle(isOn: $nerveSign) {
                Text("Pain, tingling or numbness below the knee or in the big toe")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .tint(StrandPalette.statusWarning)
            if nerveSign {
                Text("Don't push that leg further. Saving logs it as a back flare, so bending drills rest for 48 hours.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case 3:
            test("Seated hip rotation",
                 steps: ["Sit tall on the end of the bench, knees bent and together, hands on the bench.",
                         "Phone strapped to the shin just above the ankle, Level zeroed with the shin upright.",
                         "Turn-in: swing the foot outwards as far as it goes without the hip lifting. Turn-out: swing it inwards."],
                 note: "A mirror or a video from the front helps keep the hips level.")
            field(.hipInRight)
            field(.hipInLeft)
            field(.hipOutRight)
            field(.hipOutLeft)
        case 4:
            test("Hip-flexor length (Thomas test)",
                 steps: ["Sit on the very end of the bench, hug one knee to your chest and roll back; low back flat.",
                         "Let the other leg hang, relaxed. Phone on the front of the hanging thigh.",
                         "Read the thigh's angle above level (0 if it's level, a minus number if it drops below)."],
                 note: "Roll onto your side to get up.")
            field(.thomasRight)
            field(.thomasLeft)
        case 5:
            if shinCleared {
                test("Deep-squat hold",
                     steps: ["Feet shoulder-width, heels down. Sit as deep as you can, arms forward.",
                             "Hold up to 30 seconds; hold the cable column if you need to."],
                     note: nil)
                StopwatchField(title: "Hold", unit: "s", cap: 30, value: binding(.squatSeconds))
                Toggle("Heels stayed down", isOn: $heelsDown).tint(StrandPalette.accent)
                Toggle("Hips below the knees", isOn: $hipsBelowKnees).tint(StrandPalette.accent)
                Toggle("Held on to something", isOn: $support).tint(StrandPalette.accent)
            } else {
                test("Deep-squat hold", steps: [], note: "Skipped for now: it waits until the shin's getting-back-to-running checks are passed.")
            }
        case 6:
            test("Knee to wall",
                 steps: ["Face the wall, one foot forward, heel down.",
                         "Bend the knee to touch the wall. Move the foot back until the knee only just touches with the heel down.",
                         "Measure from the big toe to the wall."],
                 note: nil)
            field(.kneeWallRight)
            field(.kneeWallLeft)
        case 7:
            test("Sitting cross-legged",
                 steps: ["Sit cross-legged on the floor and start the timer.",
                         "Stop when the back gets tight or you need to move. Stop at 10 minutes either way."],
                 note: nil)
            StopwatchField(title: "Time", unit: "min", cap: 600, value: binding(.crossLegged), minutes: true)
        default:
            test("How confident did bending feel?", steps: [], note: "0 is not at all, 10 is completely. Tomorrow morning the app asks how your back feels after the tests.")
            PainScaleRow(selected: confidence) { confidence = $0 }
        }
    }

    private func test(_ title: String, steps: [String], note: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(StrandFont.rounded(26))
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(StrandFont.subhead.weight(.semibold).monospacedDigit())
                        .foregroundStyle(StrandPalette.accent)
                    Text(step)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let note {
                Text(note)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func binding(_ m: MobilityMetric) -> Binding<Double?> {
        Binding(get: { values[m] }, set: { values[m] = $0 })
    }

    private func field(_ m: MobilityMetric) -> some View {
        HStack {
            Text(m.label)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            TextField("–", value: binding(m), format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(StrandFont.bodyNumber)
                .frame(width: 80)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(StrandPalette.surfaceOverlay))
            Text(m.unit)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(width: 30, alignment: .leading)
        }
    }
}

/// A start/stop timer that fills in a hold or a sit, capped.
private struct StopwatchField: View {
    let title: String
    let unit: String
    let cap: Int
    @Binding var value: Double?
    var minutes = false

    @State private var started: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let running = started.map { min(Double(cap), context.date.timeIntervalSince($0)) }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Text(Self.text(running ?? (value.map { minutes ? $0 * 60 : $0 } ?? 0)))
                        .font(StrandFont.display(40).monospacedDigit())
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                Spacer()
                NoopButton(started == nil ? (value == nil ? "Start" : "Again") : "Stop",
                           systemImage: started == nil ? "play.fill" : "stop.fill",
                           kind: started == nil ? .secondary : .primary) {
                    if let s = started {
                        let secs = min(Double(cap), Date().timeIntervalSince(s)).rounded()
                        value = minutes ? (secs / 60 * 10).rounded() / 10 : secs
                        started = nil
                    } else {
                        started = Date()
                    }
                }
            }
            .onChange(of: running.map { $0 >= Double(cap) } ?? false) { _, capped in
                if capped, started != nil {
                    value = minutes ? Double(cap) / 60 : Double(cap)
                    started = nil
                }
            }
        }
    }

    static func text(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
