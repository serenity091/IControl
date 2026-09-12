import XCTest
@testable import IControl

@MainActor final class DeviceMotionTests: XCTestCase {
    func testPhysicalMotionThroughNativeConnection() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone required")
        #else
        guard let url = ProcessInfo.processInfo.environment["ICONTROL_TEST_PAIR_URL"] else {
            throw XCTSkip("Run tests/run_device_motion.py with a preview server for end-to-end motion")
        }
        let model = ControllerModel()
        defer { model.disconnect() }
        model.join(url: url, name: "Physical motion validation")
        for _ in 0..<100 {
            if model.acceptsTouches { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.acceptsTouches, model.status)
        XCTAssertTrue(model.motionAvailable, model.motionMessage)
        model.motionEnabled = true
        // Keep the real native stream active while the Mac harness receives DSU.
        try await Task.sleep(for: .seconds(5))
        XCTAssertNotNil(model.motion.sample(), model.motion.status)
        XCTAssertGreaterThan(model.subscribers, 0, "Mac harness must subscribe to the bridge")
        model.motionEnabled = false
        try await Task.sleep(for: .seconds(1))
        XCTAssertNil(model.motion.sample())
        #endif
    }
    func testPhysicalSensorAcquisitionAndCleanup() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone required; simulator cannot validate Core Motion")
        #else
        let source = MotionSource()
        XCTAssertTrue(source.manager.isDeviceMotionAvailable)
        source.start()
        defer { source.stop() }
        var samples: [MotionFrame] = []
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(30))
            if let sample = source.sample() { samples.append(sample) }
        }
        XCTAssertGreaterThan(samples.count, 50, source.status)
        XCTAssertTrue(samples.allSatisfy { ($0.accel + $0.gyro).allSatisfy(\.isFinite) })
        if let first = samples.first, let last = samples.last {
            XCTAssertGreaterThan(last.timestamp, first.timestamp)
            XCTAssertGreaterThan(last.seq, first.seq)
        }
        source.stop()
        XCTAssertNil(source.sample())
        XCTAssertFalse(source.manager.isDeviceMotionActive)
        #endif
    }
}
