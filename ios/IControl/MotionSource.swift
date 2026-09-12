import CoreMotion
import Foundation

@MainActor final class MotionSource: ObservableObject {
    @Published var status = "Motion off"
    let manager = CMMotionManager()
    var rotation = ScreenRotation.portrait
    var sensitivity = 1.0
    private var bias = [0.0, 0.0, 0.0]
    private var calibration: [[Double]]? = nil
    private var sequence = 0
    private var lastTimestamp = -1.0
    private var started = 0.0
    private var failed = false
    private var generation = 0
    private(set) var latest: MotionFrame?
    private var latestAt = 0.0

    func start() {
        guard !manager.isDeviceMotionActive, !failed else { return }
        guard manager.isDeviceMotionAvailable, manager.isGyroAvailable, manager.isAccelerometerAvailable else {
            status = "Motion sensors unavailable on this device"; return
        }
        generation += 1
        let current = generation
        started = ProcessInfo.processInfo.systemUptime
        manager.deviceMotionUpdateInterval = 1.0 / 60
        status = "Starting sensors…"
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, error in
            MainActor.assumeIsolated {
                guard let self, current == self.generation else { return }
                if error != nil {
                    self.stop(); self.failed = true
                    self.status = "Motion unavailable. Check Motion & Fitness in Settings, then toggle motion to retry."
                } else if let data { self.consume(data) }
            }
        }
    }
    func stop() {
        generation += 1; manager.stopDeviceMotionUpdates(); latest = nil; calibration = nil
        lastTimestamp = -1; status = "Motion off"
    }
    func retry() { failed = false }
    func calibrate() {
        guard manager.isDeviceMotionActive else { return }
        calibration = []; latest = nil; status = "Keep phone still for one second…"
    }
    func sample() -> MotionFrame? {
        let now = ProcessInfo.processInfo.systemUptime
        if manager.isDeviceMotionActive && now - max(started, latestAt) > 2 {
            stop(); failed = true; status = "No sensor samples. Check motion access in Settings and toggle to retry."
        }
        return now - latestAt <= 0.2 ? latest : nil
    }
    private func consume(_ data: CMDeviceMotion) {
        guard data.timestamp > lastTimestamp else { return }
        lastTimestamp = data.timestamp
        let r = [data.rotationRate.x, data.rotationRate.y, data.rotationRate.z]
        let a = [data.userAcceleration.x + data.gravity.x, data.userAcceleration.y + data.gravity.y,
                 data.userAcceleration.z + data.gravity.z]
        guard (r+a).allSatisfy(\.isFinite) else { latest = nil; return }
        latestAt = ProcessInfo.processInfo.systemUptime
        if calibration != nil {
            let acceleration = hypot(hypot(data.userAcceleration.x, data.userAcceleration.y), data.userAcceleration.z)
            guard r.allSatisfy({ abs($0) < 0.15 }), acceleration < 0.08 else {
                calibration = []; status = "Phone moved. Keep still to calibrate…"; return
            }
            calibration!.append(r)
            if calibration!.count >= 60 {
                bias = (0..<3).map { axis in calibration!.map { $0[axis] }.reduce(0,+) / Double(calibration!.count) }
                calibration = nil; status = "Calibrated · streaming sensors"
            }
            return
        }
        sequence += 1
        latest = MotionFrame(seq: sequence, timestamp: Int(data.timestamp * 1_000_000),
                             accel: MotionAxes.screen(a, rotation).map { min(16, max(-16, $0)) },
                             gyro: MotionAxes.gyro(r, rotation: rotation, bias: bias, sensitivity: sensitivity))
        if status == "Starting sensors…" { status = "Streaming sensors · calibrate while still" }
    }
}
