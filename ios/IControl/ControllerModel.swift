import SwiftUI
import UIKit
import CoreHaptics

@MainActor final class ControllerModel: ObservableObject {
    @Published var status = "Scan the server QR or paste its pairing URL"
    @Published var connected = false
    @Published var editing = false
    @Published var motionAvailable = false
    @Published var motionMessage = "Motion requires a compatible server"
    @Published var subscribers = 0
    @Published var selected: String?
    @Published var size = 1.0
    @Published var layoutRevision = 0
    @Published private(set) var configuration: ControllerConfiguration
    private let preferences: UserDefaults
    var rebuildLayout: (() -> Void)?
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let saved = preferences.data(forKey: "controllerConfiguration")
            .flatMap { try? JSONDecoder().decode(ControllerConfiguration.self, from: $0) } ?? .full
        configuration = saved.mode == .full ? .full : saved
        motion.configuration = configuration
    }
    func selectConfiguration(_ next: ControllerConfiguration) {
        let next = next.mode == .full ? ControllerConfiguration.full : next
        guard next != configuration else { return }
        clear() // Cancel old contacts and samples before changing their identity.
        configuration = next; motion.configuration = next
        selected = nil; size = 1; layoutRevision += 1
        rebuildLayout?()
        if let data = try? JSONEncoder().encode(next) { preferences.set(data, forKey: "controllerConfiguration") }
    }
    func changedContacts(_ contacts: ContactState, press: Bool = false, immediate: Bool = true) {
        changed(contacts.state(for: configuration), press: press, immediate: immediate)
    }
    @Published var haptics = UserDefaults.standard.bool(forKey: "haptics") {
        didSet { UserDefaults.standard.set(haptics, forKey: "haptics") }
    }
    @Published var hapticStrength = UserDefaults.standard.object(forKey: "hapticStrength") as? Double ?? 1.0 {
        didSet { UserDefaults.standard.set(hapticStrength, forKey: "hapticStrength") }
    }
    @Published var motionEnabled = false {
        didSet { motion.retry(); clear(); updateMotion() }
    }
    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    let motion = MotionSource()
    var cancelContacts: (() -> Void)?
    var applySize: ((Double) -> Void)?
    private var feedback: UIImpactFeedbackGenerator?
    private var stickGenerator: UIImpactFeedbackGenerator?
    private var stickFeedback = StickFeedback()
    private var state = InputState.neutral
    private var gate = InputGate()
    private var socket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .ephemeral)
    private var generation = 0
    private var pairing: Pairing?
    private var name = "iPhone"
    private var retryTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var retryDelay = 0.8
    private var active = true
    private var wantsConnection = false
    private var inFlight = false
    private var sendStarted = 0.0
    private var lastSent = 0.0
    private var lastTick = 0.0
    private var lastPong = 0.0
    private var lastPing = 0.0
    private var opened = 0.0
    private var dirty = true
    private var client: String {
        if let id = UserDefaults.standard.string(forKey: "installation") { return id }
        let id = UUID().uuidString; UserDefaults.standard.set(id, forKey: "installation"); return id
    }
    var acceptsTouches: Bool { connected && gate.accepting && active && !editing }
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func join(url: String, name: String) {
        do {
            let parsed = try Pairing(url)
            disconnect(); pairing = parsed; self.name = String(name.prefix(32))
            UserDefaults.standard.set(name, forKey: "playerName")
            wantsConnection = true; retryDelay = 0.8; connect()
        } catch { status = error.localizedDescription }
    }
    var hasPairing: Bool { pairing != nil }
    func rejoin(name: String) {
        guard pairing != nil else { return }
        self.name = String(name.prefix(32))
        wantsConnection = true; retryDelay = 0.8; connect()
    }
    func disconnect() {
        wantsConnection = false; retryTask?.cancel(); retryTask = nil
        close(); status = "Disconnected · join to play"
    }
    func setActive(_ value: Bool) {
        active = value
        if value { if wantsConnection { connect() } }
        else { close(); status = "Paused while app is inactive" }
    }
    func setEditing(_ value: Bool) { editing = value; clear(); updateMotion() }
    func clear() {
        gate.reset(); state = .neutral; dirty = true
        cancelContacts?(); motion.stop(); stickFeedback.reset(); pump()
    }
    func changed(_ newState: InputState, press: Bool = false, immediate: Bool = true) {
        guard acceptsTouches else { return }
        state = newState; dirty = true
        if immediate { pump() }
        if haptics && supportsHaptics {
            let strength = min(1, max(0.3, hapticStrength))
            if press {
                if feedback == nil { feedback = UIImpactFeedbackGenerator(style: .heavy) }
                feedback?.impactOccurred(intensity: strength)
                feedback?.prepare()
            } else if stickFeedback.shouldPulse(newState, time: now) {
                if stickGenerator == nil { stickGenerator = UIImpactFeedbackGenerator(style: .rigid) }
                stickGenerator?.impactOccurred(intensity: strength)
                stickGenerator?.prepare()
            }
        }
    }
    func setRotation(_ orientation: UIInterfaceOrientation) {
        let rotation: ScreenRotation
        switch orientation {
        case .landscapeLeft: rotation = .landscapeLeft
        case .landscapeRight: rotation = .landscapeRight
        case .portraitUpsideDown: rotation = .upsideDown
        default: rotation = .portrait
        }
        if motion.rotation != rotation { clear(); motion.rotation = rotation; updateMotion() }
    }
    private func updateMotion() {
        if acceptsTouches && motionEnabled && motionAvailable { motion.start() }
        else { motion.stop() }
    }
    private func close() {
        generation += 1; receiveTask?.cancel(); ticker?.cancel(); retryTask?.cancel()
        receiveTask = nil; ticker = nil
        // Closing is authoritative; the server neutralizes even if the network lost the final frame.
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        connected = false; motionAvailable = false; subscribers = 0; inFlight = false
        gate.reset(); state = .neutral; cancelContacts?(); motion.stop(); feedback = nil; stickGenerator = nil; stickFeedback.reset()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    private func connect() {
        guard active, wantsConnection, let pairing else { return }
        close(); let current = generation
        status = "Connecting… Check Local Network access if this fails."
        let task = session.webSocketTask(with: pairing.socketURL); task.maximumMessageSize = 4096
        socket = task; task.resume(); opened = now; lastPong = now; lastTick = now; lastSent = 0; lastPing = now
        inFlight = true; sendStarted = now
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let join: [String: Any] = ["type":"join", "key":pairing.key, "client":client, "name":name]
                try await task.send(.string(String(data: JSONSerialization.data(withJSONObject: join), encoding: .utf8)!))
                guard current == generation else { return }; inFlight = false
                while !Task.isCancelled {
                    let message = try await task.receive()
                    guard current == generation else { return }
                    guard case .string(let text) = message, let data = text.data(using: .utf8),
                          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        fail("Invalid server response", fatal: true); return
                    }
                    handle(object)
                }
            } catch {
                guard current == generation else { return }
                let code = task.closeCode.rawValue
                fail(code == 4003 ? "Host released this player. Join again when ready." :
                     code == 1008 ? "Server rejected the connection. Check pairing and rejoin." :
                     "Connection lost. Check Wi-Fi and Local Network permission; retrying…",
                     fatal: code == 4003 || code == 1008)
            }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled, let self, current == self.generation else { return }
                self.tick()
            }
        }
    }
    private func fail(_ message: String, fatal: Bool) {
        close(); status = message
        if fatal { wantsConnection = false }
        guard wantsConnection && active else { return }
        let current = generation, delay = retryDelay
        retryDelay = min(5, retryDelay * 1.5)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, current == self.generation else { return }
            self.connect()
        }
    }
    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "joined":
            guard let player = message["player"] as? Int, (1...4).contains(player),
                  let epoch = message["epoch"] as? Int, epoch >= 0 else {
                fail("Invalid join response", fatal: true); return
            }
            connected = true; retryDelay = 0.8
            status = "Player \(player) · \(message["mode"] as? String == "preview" ? "Preview only" : "Connected")"
            let capability = (message["capabilities"] as? [String: Any])?["motion"] as? [String: Any]
            motionAvailable = capability?["version"] as? Int == 1 && capability?["available"] as? Bool == true
            motionMessage = motionAvailable ? "DSU bridge ready" : capability?["error"] as? String ?? "Motion requires a newer IControl server"
            gate.reset(epoch: epoch); clear(); UIApplication.shared.isIdleTimerDisabled = true
        case "reset":
            guard let epoch = message["epoch"] as? Int, epoch >= gate.epoch else { return }
            gate.reset(epoch: epoch); clear()
        case "pong":
            lastPong = now; subscribers = message["motionSubscribers"] as? Int ?? 0
        case "error":
            fail(message["message"] as? String ?? "Server error", fatal: message["fatal"] as? Bool ?? true)
        default: break
        }
    }
    private func tick() {
        if now - lastTick > 0.75 { clear() }
        lastTick = now
        if inFlight && now - sendStarted > 0.5 { fail("Network stalled; reconnecting from neutral…", fatal: false); return }
        if !connected && now - opened > 5 { fail("Join timed out. Check Wi-Fi and Local Network access.", fatal: false); return }
        if connected && now - lastPong > 6 { fail("Server stopped responding; reconnecting…", fatal: false); return }
        pump()
    }
    private func pump() {
        guard connected, let socket, !inFlight, now - lastSent >= 1.0/120 else { return }
        let mustClear = !gate.accepting
        let sample = !mustClear && !editing && motionEnabled && motionAvailable ? motion.sample() : nil
        let ping = gate.accepting && now - lastPing >= 2
        guard mustClear || dirty || now - lastSent >= 0.18 || sample != nil || ping else { return }
        var object: [String: Any]
        if ping { object = ["type":"ping", "time":now]; lastPing = now }
        else {
            let sentState = mustClear || editing ? InputState.neutral : state
            guard let stateData = try? JSONEncoder().encode(sentState),
                  let dictionary = try? JSONSerialization.jsonObject(with: stateData) else { return }
            object = ["type":"input", "epoch":gate.epoch, "state":dictionary]
            if let sample, let data = try? JSONEncoder().encode(sample), let value = try? JSONSerialization.jsonObject(with: data) {
                object["motion"] = value
            }
            dirty = false
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return }
        let current = generation, revision = gate.revision
        inFlight = true; sendStarted = now; lastSent = now
        Task { [weak self] in
            do {
                try await socket.send(.string(text))
                guard let self, current == self.generation else { return }
                self.inFlight = false
                if mustClear && !ping { self.gate.acknowledge(revision: revision); self.updateMotion() }
            } catch {
                guard let self, current == self.generation else { return }
                self.fail("Send failed; reconnecting from neutral…", fatal: false)
            }
        }
    }
}
