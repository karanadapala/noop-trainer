import SwiftUI
import StrandDesign
import TrainerKit

/// The full-screen rest-day routine player (D39, D40): what to do now, a big count, the one-line
/// how-to and a link, with Pause, Skip exercise and Stop. The voice carries it; the screen is for a
/// glance from the mat.
struct RoutinePlayerView: View {
    @ObservedObject private var runner = RoutineRunner.shared
    @State private var confirmStop = false

    var body: some View {
        ZStack {
            StrandPalette.surfaceBase.ignoresSafeArea()
            if runner.state == .finished {
                finished
            } else {
                playing
            }
        }
        .confirmationDialog("Stop the routine?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { runner.stop() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("What you've done is saved. Exercises you didn't reach hold their level for now.")
        }
    }

    private var playing: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                overline("\(runner.routine?.variant.label ?? "") routine", StrandPalette.restColor)
                Spacer()
                if let n = runner.exerciseNumber {
                    Text("Exercise \(n) of \(runner.exerciseCount)")
                        .font(StrandFont.subhead.monospacedDigit())
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            ProgressView(value: min(runner.elapsed, Double(runner.timeline?.totalSeconds ?? 1)),
                         total: Double(max(1, runner.timeline?.totalSeconds ?? 1)))
                .tint(StrandPalette.restColor)

            Spacer(minLength: 0)

            if let step = runner.currentStep {
                VStack(alignment: .leading, spacing: 8) {
                    overline(stepLabel(step), color(step))
                    Text(step.title)
                        .font(StrandFont.rounded(34))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.detail)
                        .font(StrandFont.body)
                        .foregroundStyle(StrandPalette.textSecondary)
                }

                bigCount(step)
                    .frame(maxWidth: .infinity)

                if let ex = exercise(step), step.kind == .change || step.kind == .work {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ex.howTo)
                            .font(StrandFont.body)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let link = ex.link {
                            Link(destination: link) {
                                Label("How to (NHS)", systemImage: "arrow.up.right.square")
                                    .font(StrandFont.subhead.weight(.semibold))
                                    .foregroundStyle(StrandPalette.accent)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(StrandPalette.surfaceRaised))
                }
            }

            Spacer(minLength: 0)

            if let said = runner.lastSpoken {
                Text("“\(said)”")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                if runner.state == .running {
                    NoopButton("Pause", systemImage: "pause.fill", kind: .secondary, fullWidth: true) { runner.pause() }
                } else {
                    NoopButton("Resume", systemImage: "play.fill", kind: .primary, fullWidth: true) { runner.resume() }
                }
                NoopButton("Skip exercise", systemImage: "forward.fill", kind: .secondary, fullWidth: true) {
                    runner.skipExercise()
                }
            }
            Button("Stop routine") { confirmStop = true }
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.statusCritical)
                .frame(maxWidth: .infinity)
            Text("The screen stays on while the routine plays.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            overline("Rest day done", StrandPalette.accent)
            Text("\(runner.routine?.variant.label ?? "") routine complete")
                .font(StrandFont.rounded(34))
                .foregroundStyle(StrandPalette.textPrimary)
            Text("Saved. Rest well; the coach checks in again tomorrow morning.")
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textSecondary)
            Spacer()
            NoopButton("Done", kind: .primary, fullWidth: true) { runner.dismissFinished() }
        }
        .padding(20)
    }

    @ViewBuilder
    private func bigCount(_ step: RoutineStep) -> some View {
        if let rep = runner.currentRep {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(rep)")
                    .font(StrandFont.display(96))
                    .tracking(StrandFont.displayTracking(96))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("of \(step.reps)")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        } else {
            Text(clock(runner.stepRemaining))
                .font(StrandFont.display(96))
                .tracking(StrandFont.displayTracking(96))
                .foregroundStyle(StrandPalette.textPrimary)
        }
    }

    private func stepLabel(_ step: RoutineStep) -> String {
        switch step.kind {
        case .walk: return "Walk"
        case .change: return "Get ready"
        case .work: return runner.currentRep == nil && step.reps > 0 ? "Get set" : "Go"
        case .rest: return "Rest"
        }
    }

    private func color(_ step: RoutineStep) -> Color {
        switch step.kind {
        case .work: return StrandPalette.effortColor
        case .walk, .rest, .change: return StrandPalette.restColor
        }
    }

    private func exercise(_ step: RoutineStep) -> Exercise? {
        step.exerciseID.flatMap { id in RestDayCatalogue.all.first { $0.id == id } }
    }

    private func overline(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking * 4)
            .foregroundStyle(color)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
