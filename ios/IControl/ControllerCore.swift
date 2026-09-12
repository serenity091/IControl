import Foundation

struct Pairing {
    let socketURL: URL
    let key: String
    init(_ text: String) throws {
        guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "http", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.path == "/play", c.query == nil,
              (1...65535).contains(c.port ?? 80), let fragment = c.fragment,
              let parts = URLComponents(string: "?" + fragment)?.queryItems,
              parts.count == 1, parts[0].name == "key", let key = parts[0].value,
              (8...256).contains(key.count), key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { throw PairingError.invalid }
        self.key = key
        c.scheme = "ws"; c.path = "/ws"; c.fragment = nil
        guard let url = c.url else { throw PairingError.invalid }
        socketURL = url
    }
    enum PairingError: LocalizedError {
        case invalid
        var errorDescription: String? { "Use the complete http://host:port/play#key=… URL from the IControl QR code." }
    }
}

struct InputState: Codable, Equatable {
    var buttons: [String] = []
    var lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0, zl = 0.0, zr = 0.0
    static let neutral = InputState()
}

// Shared with tests: all contacts are owned by their original touch until release.
struct ContactState {
    var contacts: [Int: String] = [:]
    var axes: [String: [Double]] = [:]
    mutating func begin(_ token: Int, control: String) -> Bool {
        guard !contacts.values.contains(control) else { return false }
        contacts[token] = control; return true
    }
    mutating func move(_ token: Int, x: Double, y: Double) {
        guard let id = contacts[token], id == "LS" || id == "RS", x.isFinite, y.isFinite else { return }
        let length = max(1, hypot(x, y))
        axes[id] = [abs(x / length) < 0.06 ? 0 : x / length, abs(y / length) < 0.06 ? 0 : y / length]
    }
    mutating func end(_ token: Int) {
        if let id = contacts.removeValue(forKey: token) { axes[id] = nil }
    }
    mutating func clear() { contacts.removeAll(); axes.removeAll() }
    var state: InputState {
        var result = InputState()
        for id in contacts.values {
            switch id {
            case "LS": result.lx = axes[id]?[0] ?? 0; result.ly = axes[id]?[1] ?? 0
            case "RS": result.rx = axes[id]?[0] ?? 0; result.ry = axes[id]?[1] ?? 0
            case "ZL": result.zl = 1
            case "ZR": result.zr = 1
            default: result.buttons.append(id)
            }
        }
        result.buttons.sort(); return result
    }
}

struct InputGate {
    private(set) var epoch = 0
    private(set) var revision = 0
    private(set) var accepting = false
    mutating func reset(epoch: Int? = nil) {
        if let epoch { self.epoch = epoch }
        revision += 1; accepting = false
    }
    mutating func acknowledge(revision: Int) {
        if revision == self.revision { accepting = true }
    }
}

struct Placement: Codable, Equatable {
    var x: Double, y: Double, scale: Double = 1
    var bounded: Placement {
        guard x.isFinite, y.isFinite, scale.isFinite else { return Placement(x: 50, y: 50) }
        return Placement(x: min(100, max(0, x)), y: min(100, max(0, y)), scale: min(1.6, max(0.6, scale)))
    }
}
struct ControlDefinition {
    let id: String, label: String, size: Double
    let landscape: Placement, portrait: Placement
    var stick: Bool { id == "LS" || id == "RS" }
    static let all: [ControlDefinition] = [
        .init(id: "L", label: "LB", size: 0.9, landscape: .init(x:12,y:13), portrait:.init(x:14,y:9)),
        .init(id: "ZL", label: "LT", size: 0.9, landscape: .init(x:26,y:13), portrait:.init(x:35,y:9)),
        .init(id: "ZR", label: "RT", size: 0.9, landscape: .init(x:74,y:13), portrait:.init(x:65,y:9)),
        .init(id: "R", label: "RB", size: 0.9, landscape: .init(x:88,y:13), portrait:.init(x:86,y:9)),
        .init(id: "MINUS", label: "−", size: 0.5, landscape: .init(x:44,y:20), portrait:.init(x:43,y:21)),
        .init(id: "PLUS", label: "+", size: 0.5, landscape: .init(x:56,y:20), portrait:.init(x:57,y:21)),
        .init(id: "LS", label: "L", size: 1.7, landscape: .init(x:16,y:44), portrait:.init(x:24,y:36)),
        .init(id: "RS", label: "R", size: 1.7, landscape: .init(x:67,y:75), portrait:.init(x:73,y:71)),
        .init(id: "UP", label: "▲", size: 0.65, landscape: .init(x:30,y:61), portrait:.init(x:25,y:64.5)),
        .init(id: "DOWN", label: "▼", size: 0.65, landscape: .init(x:30,y:87), portrait:.init(x:25,y:75.5)),
        .init(id: "LEFT", label: "◀", size: 0.65, landscape: .init(x:25,y:74), portrait:.init(x:15,y:70)),
        .init(id: "RIGHT", label: "▶", size: 0.65, landscape: .init(x:35,y:74), portrait:.init(x:35,y:70)),
        .init(id: "Y", label: "Y", size: 0.85, landscape: .init(x:84,y:30), portrait:.init(x:75,y:29)),
        .init(id: "B", label: "B", size: 0.85, landscape: .init(x:90,y:47), portrait:.init(x:88,y:36)),
        .init(id: "A", label: "A", size: 0.85, landscape: .init(x:84,y:64), portrait:.init(x:75,y:43)),
        .init(id: "X", label: "X", size: 0.85, landscape: .init(x:78,y:47), portrait:.init(x:62,y:36)),
        .init(id: "L3", label: "L3", size: 0.55, landscape: .init(x:12,y:85), portrait:.init(x:17,y:91)),
        .init(id: "R3", label: "R3", size: 0.55, landscape: .init(x:89,y:85), portrait:.init(x:84,y:91)),
        .init(id: "HOME", label: "⌂", size: 0.5, landscape: .init(x:50,y:80), portrait:.init(x:50,y:91))
    ]
}

struct MotionFrame: Encodable {
    let v = 1
    let seq: Int, timestamp: Int
    let accel: [Double], gyro: [Double]
}
enum ScreenRotation: Int { case portrait, upsideDown, landscapeLeft, landscapeRight }
enum MotionAxes {
    // UIInterfaceOrientation (opposite landscape names from UIDeviceOrientation).
    // Right-handed screen frame: X right, Y toward top, Z out of glass.
    static func screen(_ v: [Double], _ orientation: ScreenRotation) -> [Double] {
        switch orientation {
        case .portrait: return v
        case .upsideDown: return [-v[0], -v[1], v[2]]
        case .landscapeLeft: return [v[1], -v[0], v[2]]
        case .landscapeRight: return [-v[1], v[0], v[2]]
        }
    }
    static func gyro(_ radians: [Double], rotation: ScreenRotation, bias: [Double], sensitivity: Double) -> [Double] {
        let value = screen(zip(radians, bias).map { $0.0 - $0.1 }, rotation)
        return value.map { min(4000, max(-4000, $0 * 180 / .pi * sensitivity)) }
    }
}


struct StickFeedback {
    private var previous = InputState.neutral
    private var lastTime = -Double.infinity
    mutating func reset() { previous = .neutral; lastTime = -.infinity }
    mutating func shouldPulse(_ state: InputState, time: Double) -> Bool {
        let leftTravel = hypot(state.lx - previous.lx, state.ly - previous.ly)
        let rightTravel = hypot(state.rx - previous.rx, state.ry - previous.ry)
        guard max(leftTravel, rightTravel) >= 0.18, time - lastTime >= 0.08 else { return false }
        previous = state; lastTime = time
        return true
    }
}
