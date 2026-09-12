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
    var state: InputState { state(for: .full) }
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
    static func gyro(_ radians: [Double], rotation: ScreenRotation, bias: [Double], sensitivity: Double, configuration: ControllerConfiguration = .full) -> [Double] {
        let value = configuration.holdingVector(screen(zip(radians, bias).map { $0.0 - $0.1 }, rotation))
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

// Visible control identity is separate from its Xbox carrier. No SL/SR wire names.
enum ControllerMode: String, CaseIterable, Codable {
    case full, left, right
    var title: String {
        switch self { case .full: return "Full controller"; case .left: return "Left Joy-Con"; case .right: return "Right Joy-Con" }
    }
}
enum HoldingLayout: String, CaseIterable, Codable {
    case upright, sideways
    var title: String { self == .upright ? "Upright" : "Sideways" }
}
enum ControlCarrier: Equatable {
    case button(String), trigger(String), stick(String)
}
struct ControllerConfiguration: Codable, Equatable {
    var mode: ControllerMode = .full
    var holding: HoldingLayout = .upright
    static let full = ControllerConfiguration()
    var title: String { mode.title + (mode == .full ? "" : " · " + holding.title) }
    var carriers: [String: ControlCarrier] {
        switch mode {
        case .full:
            return Dictionary(uniqueKeysWithValues: ControlDefinition.all.map { d in
                (d.id, d.stick ? .stick(d.id) : d.id == "ZL" ? .trigger("zl") : d.id == "ZR" ? .trigger("zr") : .button(d.id))
            })
        case .left:
            return ["LS":.stick("LS"), "L3":.button("L3"), "UP":.button("UP"), "DOWN":.button("DOWN"),
                    "LEFT":.button("LEFT"), "RIGHT":.button("RIGHT"), "L":.button("L"), "ZL":.trigger("zl"),
                    "SL":.button("X"), "SR":.button("Y"), "MINUS":.button("MINUS")]
        case .right:
            return ["RS":.stick("RS"), "R3":.button("R3"), "A":.button("A"), "B":.button("B"),
                    "X":.button("X"), "Y":.button("Y"), "R":.button("R"), "ZR":.trigger("zr"),
                    "SL":.button("L"), "SR":.trigger("zl"), "PLUS":.button("PLUS"), "HOME":.button("HOME")]
        }
    }
    // Screen-frame -> upright Joy-Con hardware frame. Sideways left is held
    // counterclockwise, right clockwise. UIKit rotation is applied separately.
    func holdingVector(_ v: [Double]) -> [Double] {
        guard holding == .sideways else { return v }
        switch mode {
        case .full: return v
        case .left: return [v[1], -v[0], v[2]]
        case .right: return [-v[1], v[0], v[2]]
        }
    }
    var definitions: [ControlDefinition] {
        guard mode != .full else { return ControlDefinition.all }
        let left = mode == .left
        func control(_ id: String, _ label: String, _ size: Double, _ px: Double, _ py: Double, _ lx: Double, _ ly: Double) -> ControlDefinition {
            .init(id: id, label: label, size: size, landscape: .init(x:lx,y:ly), portrait:.init(x:px,y:py))
        }
        let stickID = left ? "LS" : "RS"
        var result: [ControlDefinition]
        if holding == .upright {
            // Narrow vertical groups stay upright even on a landscape screen.
            result = [control(stickID, "Stick", 1.8, 50, left ? 32 : 64, 32, left ? 34 : 72),
                      control(left ? "L" : "R", left ? "L" : "R", 0.8, 28, 10, 15, 12),
                      control(left ? "ZL" : "ZR", left ? "ZL" : "ZR", 0.8, 72, 10, 48, 12),
                      control("SL", "SL", 0.8, 14, 47, 77, 35), control("SR", "SR", 0.8, 86, 47, 77, 66),
                      control(left ? "MINUS" : "PLUS", left ? "−" : "+", 0.65, 50, 11, 60, 22),
                      control(left ? "L3" : "R3", "Click", 0.8, 50, 88, 59, 87)]
            let ids = left ? ["UP","RIGHT","DOWN","LEFT"] : ["X","A","B","Y"]
            let labels = left ? ["▲","▶","▼","◀"] : ids
            let cy = left ? 65.0 : 34.0, ly = left ? 73.0 : 33.0
            for (i, delta) in [(0,(0.0,-9.0)),(1,(15.0,0.0)),(2,(0.0,9.0)),(3,(-15.0,0.0))] {
                result.append(control(ids[i], labels[i], 0.8, 50+delta.0, cy+delta.1, 32+delta.0*0.65, ly+delta.1*1.3))
            }
            if !left { result.append(control("HOME", "⌂", 0.65, 80, 88, 83, 88)) }
        } else {
            // Rail is on top. Nintendo identities rotate with the physical half:
            // left clockwise ordering RIGHT, DOWN, LEFT, UP; right Y, X, A, B.
            result = [control(stickID, "Stick", 1.8, 27, 43, 23, 53),
                      control("SL", "SL", 0.8, 27, 14, 26, 12), control("SR", "SR", 0.8, 73, 14, 74, 12),
                      control(left ? "L" : "R", left ? "L" : "R", 0.8, 27, 73, 20, 86),
                      control(left ? "ZL" : "ZR", left ? "ZL" : "ZR", 0.8, 73, 73, 80, 86),
                      control(left ? "MINUS" : "PLUS", left ? "−" : "+", 0.65, 50, 27, 50, 26),
                      control(left ? "L3" : "R3", "Click", 0.8, 50, 89, 47, 85)]
            let ids = left ? ["RIGHT","DOWN","LEFT","UP"] : ["Y","X","A","B"]
            // Arrows indicate screen direction; carrier keeps upright identity.
            let labels = left ? ["▲","▶","▼","◀"] : ids
            for (i, delta) in [(0,(0.0,-10.0)),(1,(13.0,0.0)),(2,(0.0,10.0)),(3,(-13.0,0.0))] {
                result.append(control(ids[i], labels[i], 0.8, 73+delta.0, 43+delta.1, 75+delta.0*0.7, 53+delta.1*1.7))
            }
            if !left { result.append(control("HOME", "⌂", 0.65, 80, 89, 59, 85)) }
        }
        return result
    }
}

extension ContactState {
    func state(for configuration: ControllerConfiguration) -> InputState {
        var result = InputState()
        let carriers = configuration.carriers
        for id in contacts.values {
            switch carriers[id] {
            case .button(let button): result.buttons.append(button)
            case .trigger(let trigger): if trigger == "zl" { result.zl = 1 } else { result.zr = 1 }
            case .stick(let stick):
                let axes = axes[id] ?? [0,0]
                let v = configuration.holdingVector([axes[0], axes[1], 0])
                if stick == "LS" { result.lx = v[0]; result.ly = v[1] }
                else { result.rx = v[0]; result.ry = v[1] }
            case nil: break // Old/foreign control identifiers can never leak to wire.
            }
        }
        result.buttons.sort(); return result
    }
}

struct ControllerLayoutStore {
    var defaults: UserDefaults = .standard
    func key(_ configuration: ControllerConfiguration, portrait: Bool) -> String {
        "icontrol-native-layout-v2-\(configuration.mode.rawValue)-\(configuration.mode == .full ? "upright" : configuration.holding.rawValue)-\(portrait ? "portrait" : "landscape")"
    }
    func initial(_ configuration: ControllerConfiguration, portrait: Bool) -> [String: Placement] {
        Dictionary(uniqueKeysWithValues: configuration.definitions.map { ($0.id, portrait ? $0.portrait : $0.landscape) })
    }
    func load(_ configuration: ControllerConfiguration, portrait: Bool) -> [String: Placement] {
        let currentKey = key(configuration, portrait: portrait)
        let legacyKey = "icontrol-native-layout-v1-\(portrait ? "portrait" : "landscape")"
        let current = defaults.data(forKey: currentKey)
        let data = current ?? (configuration.mode == .full ? defaults.data(forKey: legacyKey) : nil)
        var result = initial(configuration, portrait: portrait)
        if let data, let saved = try? JSONDecoder().decode([String:Placement].self, from: data) {
            for (id, value) in saved where result[id] != nil { result[id] = value.bounded }
            if current == nil { save(result, configuration: configuration, portrait: portrait) }
        }
        return result
    }
    func save(_ layout: [String:Placement], configuration: ControllerConfiguration, portrait: Bool) {
        if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: key(configuration, portrait: portrait)) }
    }
    func reset(_ configuration: ControllerConfiguration, portrait: Bool) -> [String:Placement] {
        let result = initial(configuration, portrait: portrait)
        // Write defaults, rather than deleting the key and resurrecting legacy data.
        save(result, configuration: configuration, portrait: portrait); return result
    }
}
