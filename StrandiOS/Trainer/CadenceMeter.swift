import CoreMotion
import Foundation

/// Live steps per minute from the iPhone's step counter during a run (D120). Uses the same motion
/// permission NOOP already asks for to count workout steps. Silent when motion data isn't available.
@MainActor
final class CadenceMeter {
    private let pedometer = CMPedometer()
    private(set) var stepsPerMinute: Double?

    func start() {
        stepsPerMinute = nil
        guard CMPedometer.isCadenceAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            // CoreMotion reports steps per second, and only while you're moving.
            let spm = data?.currentCadence.map { $0.doubleValue * 60 }
            Task { @MainActor in self?.stepsPerMinute = spm }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        stepsPerMinute = nil
    }
}
