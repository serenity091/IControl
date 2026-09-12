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
    func testPhysicalJoyConHoldingChangesAndMotion() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone required")
        #else
        guard let url = ProcessInfo.processInfo.environment["ICONTROL_TEST_PAIR_URL"] else {
            throw XCTSkip("Physical preview harness required")
        }
        let suite = "PhysicalJoyCon-" + UUID().uuidString
        let preferences = UserDefaults(suiteName:suite)!
        defer { preferences.removePersistentDomain(forName:suite) }
        let model = ControllerModel(preferences:preferences)
        defer { model.disconnect() }
        model.join(url:url,name:"Standalone Joy-Con validation")
        for _ in 0..<100 {
            if model.acceptsTouches { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        XCTAssertTrue(model.acceptsTouches,model.status)
        XCTAssertTrue(model.motionAvailable)
        model.motionEnabled = true
        var previousSequence = -1
        for mode in [ControllerMode.left,.right] {
            for holding in HoldingLayout.allCases {
                let config = ControllerConfiguration(mode:mode,holding:holding)
                model.selectConfiguration(config)
                XCTAssertNil(model.motion.sample())
                XCTAssertFalse(model.acceptsTouches)
                try await Task.sleep(for:.milliseconds(1200))
                let frame = try XCTUnwrap(model.motion.sample(),model.motion.status)
                XCTAssertGreaterThan(frame.seq,previousSequence)
                previousSequence = frame.seq
                XCTAssertEqual(model.motion.configuration,config)
                XCTAssertTrue((frame.accel+frame.gyro).allSatisfy(\.isFinite))
                var contacts = ContactState()
                _ = contacts.begin(1,control:"SL"); _ = contacts.begin(2,control:"SR")
                _ = contacts.begin(3,control:mode == .left ? "LS" : "RS")
                contacts.move(3,x:0.5,y:0.5); model.changedContacts(contacts)
                try await Task.sleep(for:.milliseconds(300))
                print("Real sensor stream verified: \(config.title)")
            }
        }
        model.motionEnabled = false
        XCTAssertNil(model.motion.sample())
        try await Task.sleep(for:.seconds(1))
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
