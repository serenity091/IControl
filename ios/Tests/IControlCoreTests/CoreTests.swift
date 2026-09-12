import XCTest
#if canImport(IControlCore)
@testable import IControlCore
#else
@testable import IControl
#endif
final class CoreTests: XCTestCase {
    func testPairingPreservesHostPortAndDecodesKey() throws {
        let pairing = try Pairing("http://192.168.1.10:8081/play#key=abcdefgh%5F123")
        XCTAssertEqual(pairing.socketURL.absoluteString, "ws://192.168.1.10:8081/ws")
        XCTAssertEqual(pairing.key, "abcdefgh_123")
        XCTAssertEqual(try Pairing("http://[::1]:8080/play#key=abcdefgh").socketURL.absoluteString, "ws://[::1]:8080/ws")
    }
    func testRejectsUntrustedPairingShapes() {
        for url in ["javascript:alert(1)", "https://host/play#key=abcdefgh", "http://a@host/play#key=abcdefgh", "http://host:0/play#key=abcdefgh", "http://host:99999/play#key=abcdefgh", "http://host/ws#key=abcdefgh", "http://host/play?key=abcdefgh", "http://host/play#key=abcdefgh&key=ijklmnop", "http://host/play#key=a", "http://host/play#key=abcd%0Aefgh"] {
            XCTAssertThrowsError(try Pairing(url), url)
        }
    }
    func testSimultaneousContactsAndIndependentRelease() {
        var contacts = ContactState()
        XCTAssertTrue(contacts.begin(1, control: "LS"))
        XCTAssertTrue(contacts.begin(2, control: "A"))
        XCTAssertTrue(contacts.begin(3, control: "ZR"))
        XCTAssertTrue(contacts.begin(4, control: "RS"))
        XCTAssertFalse(contacts.begin(5, control: "A"))
        contacts.move(1, x: 1, y: 0); contacts.move(4, x: 0, y: -0.5)
        XCTAssertEqual(contacts.state.buttons, ["A"])
        XCTAssertEqual(contacts.state.lx, 1); XCTAssertEqual(contacts.state.zr, 1)
        contacts.end(2)
        XCTAssertTrue(contacts.state.buttons.isEmpty)
        XCTAssertEqual(contacts.state.lx, 1); XCTAssertEqual(contacts.state.ry, -0.5)
        contacts.end(1); XCTAssertEqual(contacts.state.lx, 0)
        contacts.clear(); XCTAssertEqual(contacts.state, .neutral)
    }
    func testStickClampsDeadzoneAndRejectsNonfinite() {
        var contacts = ContactState(); _ = contacts.begin(1, control: "LS")
        contacts.move(1, x: 2, y: 2)
        XCTAssertEqual(hypot(contacts.state.lx, contacts.state.ly), 1, accuracy: 1e-10)
        contacts.move(1, x: 0.01, y: 0.02); XCTAssertEqual(contacts.state.lx, 0)
        contacts.move(1, x: .nan, y: .infinity); XCTAssertEqual(contacts.state.ly, 0)
    }
    func testResetRequiresMatchingNeutralCompletion() {
        var gate = InputGate(); gate.reset(epoch: 3)
        let previous = gate.revision
        gate.reset(epoch: 4)
        gate.acknowledge(revision: previous); XCTAssertFalse(gate.accepting)
        gate.acknowledge(revision: gate.revision); XCTAssertTrue(gate.accepting)
        XCTAssertEqual(gate.epoch, 4)
        gate.reset(); XCTAssertFalse(gate.accepting)
    }
    func testOrientationAxesAndPhysicalUnits() {
        XCTAssertEqual(MotionAxes.screen([1,2,3], .landscapeLeft), [2,-1,3])
        XCTAssertEqual(MotionAxes.screen([1,2,3], .landscapeRight), [-2,1,3])
        XCTAssertEqual(MotionAxes.screen([1,2,3], .upsideDown), [-1,-2,3])
        let g = MotionAxes.gyro([.pi/2, 0, 0], rotation: .portrait, bias: [0,0,0], sensitivity: 1)
        XCTAssertEqual(g[0], 90, accuracy: 1e-10)
        let calibrated = MotionAxes.gyro([0.1,0.2,0.3], rotation: .landscapeRight, bias: [0.1,0.2,0.3], sensitivity: 2)
        XCTAssertEqual(calibrated, [0,0,0])
    }
    func testStickFeedbackMovementCadenceAndStationaryHold() {
        var feedback = StickFeedback()
        var state = InputState()
        XCTAssertFalse(feedback.shouldPulse(state, time: 0))
        state.lx = 0.3; XCTAssertTrue(feedback.shouldPulse(state, time: 0.1))
        XCTAssertFalse(feedback.shouldPulse(state, time: 60), "Stationary holds must not buzz")
        state.lx = 0.6; XCTAssertFalse(feedback.shouldPulse(state, time: 0.12))
        XCTAssertTrue(feedback.shouldPulse(state, time: 0.2))
        state.rx = -0.4; XCTAssertTrue(feedback.shouldPulse(state, time: 0.3))
        feedback.reset(); XCTAssertFalse(feedback.shouldPulse(.neutral, time: 0.4))
    }
    func testLayoutPersistenceAndBounds() throws {
        let original = Dictionary(uniqueKeysWithValues: ControlDefinition.all.map { ($0.id, $0.portrait) })
        let decoded = try JSONDecoder().decode([String: Placement].self, from: JSONEncoder().encode(original))
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(Placement(x: -4,y: 300,scale: 20).bounded, Placement(x:0,y:100,scale:1.6))
        XCTAssertEqual(ControlDefinition.all.count, 19)
        XCTAssertNotEqual(ControlDefinition.all[0].portrait, ControlDefinition.all[0].landscape)
    }
}
