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

final class JoyConCoreTests: XCTestCase {
    func testEveryVisibleControlHasUniqueExistingCarrier() {
        let expected: [ControllerMode: [String:String]] = [
            .left: ["LS":"LS", "L3":"L3", "UP":"UP", "DOWN":"DOWN", "LEFT":"LEFT", "RIGHT":"RIGHT", "L":"L", "ZL":"zl", "SL":"X", "SR":"Y", "MINUS":"MINUS"],
            .right: ["RS":"RS", "R3":"R3", "A":"A", "B":"B", "X":"X", "Y":"Y", "R":"R", "ZR":"zr", "SL":"L", "SR":"zl", "PLUS":"PLUS", "HOME":"HOME"]]
        for mode in [ControllerMode.left, .right] {
            for holding in HoldingLayout.allCases {
                let config = ControllerConfiguration(mode:mode, holding:holding)
                XCTAssertEqual(Set(config.definitions.map(\.id)), Set(expected[mode]!.keys))
                var outputs = Set<String>()
                for definition in config.definitions {
                    var contact = ContactState(); _ = contact.begin(1, control:definition.id)
                    contact.move(1, x:0.4, y:0.8)
                    let actual = contact.state(for:config)
                    let carrier = expected[mode]![definition.id]!
                    XCTAssertTrue(outputs.insert(carrier).inserted, "Every output must be independent")
                    if carrier == "LS" || carrier == "RS" {
                        XCTAssertEqual(hypot(carrier == "LS" ? actual.lx : actual.rx, carrier == "LS" ? actual.ly : actual.ry), hypot(0.4,0.8), accuracy:1e-8)
                        XCTAssertTrue(actual.buttons.isEmpty); XCTAssertEqual(actual.zl + actual.zr, 0)
                    } else if carrier == "zl" || carrier == "zr" {
                        XCTAssertEqual(carrier == "zl" ? actual.zl : actual.zr, 1); XCTAssertTrue(actual.buttons.isEmpty)
                    } else { XCTAssertEqual(actual.buttons, [carrier]) }
                    contact.end(1); XCTAssertEqual(contact.state(for:config), .neutral)
                }
            }
        }
    }
    func testSimultaneousRailsClicksTriggersAndSticksStayDistinct() {
        for mode in [ControllerMode.left, .right] {
            let config = ControllerConfiguration(mode:mode)
            var contacts = ContactState()
            for (i, d) in config.definitions.enumerated() { XCTAssertTrue(contacts.begin(i, control:d.id)); contacts.move(i, x:1, y:0) }
            let state = contacts.state(for:config)
            if mode == .left {
                XCTAssertEqual(state.buttons, ["DOWN","L","L3","LEFT","MINUS","RIGHT","UP","X","Y"])
                XCTAssertEqual(state.lx, 1); XCTAssertEqual(state.zl, 1)
                XCTAssertEqual(state.rx + state.ry + state.zr, 0)
            } else {
                XCTAssertEqual(state.buttons, ["A","B","HOME","L","PLUS","R","R3","X","Y"])
                XCTAssertEqual(state.rx, 1); XCTAssertEqual(state.zl, 1); XCTAssertEqual(state.zr, 1)
                XCTAssertEqual(state.lx + state.ly, 0)
            }
            contacts.clear(); XCTAssertEqual(contacts.state(for:config), .neutral)
            _ = contacts.begin(99, control:mode == .left ? "A" : "MINUS")
            XCTAssertEqual(contacts.state(for:config), .neutral, "Foreign/old controls are filtered")
        }
    }
    func testNintendoFacePositionsAndSidewaysDirections() {
        func center(_ config: ControllerConfiguration, _ id: String) -> Placement { config.definitions.first { $0.id == id }!.landscape }
        let rightUp = ControllerConfiguration(mode:.right)
        XCTAssertLessThan(center(rightUp,"X").y, center(rightUp,"A").y)
        XCTAssertGreaterThan(center(rightUp,"A").x, center(rightUp,"Y").x)
        XCTAssertGreaterThan(center(rightUp,"B").y, center(rightUp,"A").y)
        let rightSide = ControllerConfiguration(mode:.right,holding:.sideways)
        XCTAssertLessThan(center(rightSide,"Y").y, center(rightSide,"X").y)
        XCTAssertGreaterThan(center(rightSide,"X").x, center(rightSide,"B").x)
        XCTAssertGreaterThan(center(rightSide,"A").y, center(rightSide,"X").y)
        let leftSide = ControllerConfiguration(mode:.left,holding:.sideways)
        XCTAssertLessThan(center(leftSide,"UP").x, center(leftSide,"DOWN").x)
        XCTAssertLessThan(center(leftSide,"RIGHT").y, center(leftSide,"LEFT").y)
        for config in [leftSide,rightSide] {
            var c = ContactState(); _ = c.begin(1,control:config.mode == .left ? "LS" : "RS")
            c.move(1,x:0,y:1)
            let s = c.state(for:config)
            if config.mode == .left { XCTAssertEqual(s.lx,1); XCTAssertEqual(s.ly,0) }
            else { XCTAssertEqual(s.rx,-1); XCTAssertEqual(s.ry,0) }
        }
    }
    func testAllMotionBasisVectorsInEveryOrientationAndHoldingFrame() {
        let rotations: [ScreenRotation] = [.portrait,.upsideDown,.landscapeLeft,.landscapeRight]
        let basis = [[1.0,0,0],[0,1,0],[0,0,1]]
        for mode in ControllerMode.allCases {
            for holding in HoldingLayout.allCases {
                let config = ControllerConfiguration(mode:mode,holding:holding)
                for rotation in rotations {
                    for vector in basis {
                        let screen = MotionAxes.screen(vector,rotation)
                        let expected: [Double]
                        if holding == .upright || mode == .full { expected = screen }
                        else if mode == .left { expected = [screen[1],-screen[0],screen[2]] }
                        else { expected = [-screen[1],screen[0],screen[2]] }
                        XCTAssertEqual(config.holdingVector(screen),expected)
                        let actual = MotionAxes.gyro(vector.map { $0 * .pi / 2 }, rotation:rotation,bias:[0,0,0],sensitivity:1,configuration:config)
                        for i in 0..<3 { XCTAssertEqual(actual[i],expected[i]*90,accuracy:1e-8) }
                    }
                }
            }
        }
    }
    func testLayoutMigrationIsolationAndResetScope() throws {
        let suite = "JoyConLayouts-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let store = ControllerLayoutStore(defaults:defaults)
        let legacy = ["LS":Placement(x:22,y:33,scale:1.3)]
        defaults.set(try JSONEncoder().encode(legacy),forKey:"icontrol-native-layout-v1-portrait")
        XCTAssertEqual(store.load(.full,portrait:true)["LS"],legacy["LS"])
        var keys = Set<String>()
        let configs = [ControllerConfiguration.full] + [ControllerMode.left,.right].flatMap { mode in HoldingLayout.allCases.map { ControllerConfiguration(mode:mode,holding:$0) } }
        for config in configs {
            for portrait in [true,false] {
                XCTAssertTrue(keys.insert(store.key(config,portrait:portrait)).inserted)
                var layout = store.load(config,portrait:portrait)
                let id = config.definitions[0].id
                layout[id] = Placement(x:18,y:27,scale:1.2)
                store.save(layout,configuration:config,portrait:portrait)
                XCTAssertEqual(store.load(config,portrait:portrait)[id],layout[id])
            }
        }
        let right = ControllerConfiguration(mode:.right,holding:.sideways)
        let other = store.load(right,portrait:false)
        _ = store.reset(.full,portrait:true)
        XCTAssertEqual(store.load(.full,portrait:true),store.initial(.full,portrait:true))
        XCTAssertEqual(store.load(right,portrait:false),other)
        XCTAssertNotNil(defaults.data(forKey:"icontrol-native-layout-v1-portrait"))
        XCTAssertEqual(keys.count,10)
    }
}
