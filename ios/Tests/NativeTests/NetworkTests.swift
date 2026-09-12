import XCTest
@testable import IControl

@MainActor final class NetworkTests: XCTestCase {
    let base = URL(string: "http://127.0.0.1:8089")!
    func json(_ path: String, method: String = "GET", token: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        if let token { request.setValue(token, forHTTPHeaderField: "X-Admin-Token") }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func waitFor(_ condition: @escaping () async throws -> Bool) async throws {
        for _ in 0..<80 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Condition did not become true within four seconds")
    }
    func state() async throws -> [String: Any] {
        let response = try await json("api/status")
        let players = try XCTUnwrap(response["players"] as? [[String: Any]])
        return try XCTUnwrap(players.first?["state"] as? [String: Any])
    }
    func testJoyConSwitchNeutralBarrierAndWireMappings() async throws {
        let bootstrap = try await json("api/bootstrap")
        let token = try XCTUnwrap(bootstrap["adminToken"] as? String)
        for index in 1...4 { _ = try await json("api/players/\(index)/release",method:"POST",token:token) }
        let addresses = try XCTUnwrap(bootstrap["addresses"] as? [[String:String]])
        let pairing = try Pairing(XCTUnwrap(addresses.first?["url"]))
        let suite = "JoyConModel-" + UUID().uuidString
        let preferences = UserDefaults(suiteName:suite)!
        defer { preferences.removePersistentDomain(forName:suite) }
        let model = ControllerModel(preferences:preferences)
        defer { model.disconnect() }
        model.join(url:"http://127.0.0.1:8089/play#key=\(pairing.key)",name:"Joy-Con test")
        try await waitFor { model.acceptsTouches }
        var contacts = ContactState()
        model.cancelContacts = { contacts.clear() }
        for mode in [ControllerMode.left,.right] {
            for holding in HoldingLayout.allCases {
                model.selected = "old-selection"
                model.selectConfiguration(.init(mode:mode,holding:holding))
                XCTAssertFalse(model.acceptsTouches)
                XCTAssertNil(model.selected)
                XCTAssertEqual(contacts.state,.neutral)
                XCTAssertNil(model.motion.sample())
                // Attempting old input during the neutral barrier must be ignored.
                var old = InputState(); old.buttons = ["HOME"]; old.lx = 1
                model.changed(old)
                try await waitFor { model.acceptsTouches }
                let reset = try await state()
                XCTAssertEqual(reset["buttons"] as? [String],[])
                XCTAssertEqual(reset["lx"] as? Double,0)
                _ = contacts.begin(1,control:"SL"); _ = contacts.begin(2,control:"SR")
                _ = contacts.begin(3,control:mode == .left ? "L3" : "R3")
                _ = contacts.begin(4,control:mode == .left ? "LS" : "RS"); contacts.move(4,x:0,y:1)
                model.changedContacts(contacts)
                let expected = mode == .left ? ["L3","X","Y"] : ["L","R3"]
                try await waitFor { try await self.state()["buttons"] as? [String] == expected }
                let active = try await state()
                XCTAssertEqual(active["zl"] as? Double,mode == .left ? 0 : 1)
                let history = try await json("test/frames")["frames"] as! [[String:Any]]
                let activeIndex = try XCTUnwrap(history.lastIndex { $0["buttons"] as? [String] == expected })
                XCTAssertGreaterThan(activeIndex,0)
                XCTAssertEqual(history[activeIndex-1]["buttons"] as? [String],[], "Neutral must precede new mode input")
            }
        }
        XCTAssertEqual(ControllerModel(preferences:preferences).configuration,.init(mode:.right,holding:.sideways))
        model.setActive(false)
        try await waitFor { try await self.state()["buttons"] as? [String] == [] }
    }
    func testOlderServerKeepsButtonsButDisablesMotion() async throws {
        let model = ControllerModel()
        model.selectConfiguration(.full)
        defer { model.disconnect() }
        model.join(url: "http://127.0.0.1:8090/play#key=legacy-test-key", name: "Legacy test")
        try await waitFor { model.acceptsTouches }
        XCTAssertFalse(model.motionAvailable)
        XCTAssertTrue(model.motionMessage.contains("newer"))
        var input = InputState(); input.buttons = ["X"]; input.rx = -0.5
        model.changed(input)
        try await waitFor {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8090/state")!)
            let state = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return state?["rx"] as? Double == -0.5 && state?["buttons"] as? [String] == ["X"]
        }
    }
    func testNativePairInputResetBackgroundReconnectAndHostRelease() async throws {
        let bootstrap = try await json("api/bootstrap")
        let token = try XCTUnwrap(bootstrap["adminToken"] as? String)
        for index in 1...4 { _ = try await json("api/players/\(index)/release", method:"POST", token:token) }
        let addresses = try XCTUnwrap(bootstrap["addresses"] as? [[String:String]])
        let scanned = try Pairing(XCTUnwrap(addresses.first?["url"]))
        let model = ControllerModel()
        model.selectConfiguration(.full)
        defer { model.disconnect() }
        model.join(url: "http://127.0.0.1:8089/play#key=\(scanned.key)", name: "Native XCTest")
        try await waitFor { model.acceptsTouches }
        XCTAssertTrue(model.motionAvailable)
        var active = InputState(); active.buttons = ["A", "L"]; active.lx = 0.7
        model.changed(active, press:true)
        try await waitFor { try await self.state()["buttons"] as? [String] == ["A", "L"] }
        // Stationary holds must survive for longer than the server watchdog.
        try await Task.sleep(for: .milliseconds(1100))
        let held = try await state()
        XCTAssertEqual(held["lx"] as? Double, 0.7)
        _ = try await json("test/expire", method: "POST")
        try await waitFor { try await self.state()["lx"] as? Double == 0 }
        try await Task.sleep(for: .milliseconds(300))
        let cleared = try await state()
        XCTAssertEqual(cleared["buttons"] as? [String], [])
        try await waitFor { model.acceptsTouches }
        model.changed(active)
        try await waitFor { try await self.state()["lx"] as? Double == 0.7 }
        model.setEditing(true)
        try await waitFor { try await self.state()["lx"] as? Double == 0 }
        XCTAssertFalse(model.acceptsTouches)
        model.setEditing(false)
        try await waitFor { model.acceptsTouches }
        model.changed(active)
        model.setActive(false)
        try await waitFor { try await self.state()["lx"] as? Double == 0 }
        model.setActive(true)
        try await waitFor { model.acceptsTouches }
        let rejoined = try await state()
        XCTAssertEqual(rejoined["buttons"] as? [String], [])
        _ = try await json("api/players/1/release", method:"POST", token:token)
        try await waitFor { !model.connected }
        try await Task.sleep(for: .milliseconds(1600))
        XCTAssertFalse(model.connected, "Host release must not automatically rejoin")
    }
}
