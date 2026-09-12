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
    func testOlderServerKeepsButtonsButDisablesMotion() async throws {
        let model = ControllerModel()
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
