import SwiftUI
import UIKit

struct TouchSurface: UIViewRepresentable {
    @ObservedObject var model: ControllerModel
    func makeUIView(context: Context) -> ControlCanvas { ControlCanvas(model: model) }
    func updateUIView(_ view: ControlCanvas, context: Context) {
        view.editing = model.editing
        view.setNeedsDisplay()
    }
    static func dismantleUIView(_ view: ControlCanvas, coordinator: ()) { view.clear() }
}

@MainActor final class ControlCanvas: UIView {
    weak var model: ControllerModel?
    var editing = false
    private var layout: [String: Placement] = [:]
    private var portrait = false
    private var oldSize = CGSize.zero
    private var frames: [String: CGRect] = [:]
    private var touchIDs: [ObjectIdentifier: Int] = [:]
    private var nextID = 0
    private var inputs = ContactState()
    private var origins: [Int: (CGPoint, Placement)] = [:]
    private var storageKey: String { "icontrol-native-layout-v1-\(portrait ? "portrait" : "landscape")" }
    init(model: ControllerModel) {
        self.model = model
        super.init(frame: .zero)
        isMultipleTouchEnabled = true; backgroundColor = UIColor(white: 0.84, alpha: 1)
        layer.cornerRadius = 30; clipsToBounds = true
        model.cancelContacts = { [weak self] in self?.clear() }
        model.applySize = { [weak self] value in self?.resizeControls(value) }
        isAccessibilityElement = true
        accessibilityLabel = "Xbox controller touch surface"
        accessibilityHint = "Supports independent simultaneous contacts. Use Edit layout to move or resize controls."
        accessibilityIdentifier = "controllerSurface"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let orientation = window?.windowScene?.interfaceOrientation ?? .unknown
        model?.setRotation(orientation)
        guard bounds.size != oldSize else { return }
        model?.clear(); save()
        oldSize = bounds.size; portrait = orientation == .unknown ? bounds.height > bounds.width : orientation.isPortrait
        load(); calculateFrames()
        setNeedsDisplay()
    }
    func clear() {
        touchIDs.removeAll(); inputs.clear(); origins.removeAll(); setNeedsDisplay()
    }
    private func load() {
        layout = Dictionary(uniqueKeysWithValues: ControlDefinition.all.map { ($0.id, portrait ? $0.portrait : $0.landscape) })
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: Placement].self, from: data) {
            for (id, placement) in saved where layout[id] != nil { layout[id] = placement.bounded }
        }
    }
    private func save() {
        guard !layout.isEmpty, let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    func resetLayout() {
        clear(); UserDefaults.standard.removeObject(forKey: storageKey); load(); calculateFrames(); setNeedsDisplay()
    }
    private func resizeControls(_ scale: Double) {
        if scale == 0 { resetLayout(); return }
        for id in layout.keys where model?.selected == nil || model?.selected == id {
            layout[id]!.scale = min(1.6, max(0.6, scale))
        }
        calculateFrames(); save(); setNeedsDisplay()
    }
    private func calculateFrames() {
        let unit = portrait ? min(bounds.width / 5.5, bounds.height / 9) : min(bounds.width / 12, bounds.height / 4.8)
        for definition in ControlDefinition.all {
            let p = layout[definition.id] ?? definition.landscape
            let diameter = max(22, unit * definition.size * p.scale)
            let width = ["L","R","ZL","ZR"].contains(definition.id) ? diameter * 1.4 : diameter
            let x = min(bounds.width - width/2, max(width/2, bounds.width * p.x / 100))
            let y = min(bounds.height - diameter/2, max(diameter/2, bounds.height * p.y / 100))
            frames[definition.id] = CGRect(x: x-width/2, y: y-diameter/2, width: width, height: diameter)
        }
    }
    override func draw(_ rect: CGRect) {
        let colors: [String: UIColor] = ["A":UIColor(red:0.2,green:0.52,blue:0.16,alpha:1),
                                       "B":UIColor(red:0.74,green:0.16,blue:0.15,alpha:1),
                                       "X":UIColor(red:0.14,green:0.4,blue:0.7,alpha:1),
                                       "Y":UIColor(red:0.88,green:0.71,blue:0.13,alpha:1)]
        for d in ControlDefinition.all {
            guard let frame = frames[d.id] else { continue }
            let pressed = inputs.contacts.values.contains(d.id) && !editing
            let path = UIBezierPath(roundedRect: frame, cornerRadius: d.stick || colors[d.id] != nil ? frame.height / 2 : 9)
            (pressed ? UIColor(white:0.32,alpha:1) : UIColor(white:0.12,alpha:1)).setFill(); path.fill()
            if editing {
                (model?.selected == d.id ? UIColor.systemBlue : UIColor.gray).setStroke()
                path.lineWidth = 2; path.stroke()
            }
            var labelRect = frame
            if d.stick {
                let axes = inputs.axes[d.id] ?? [0,0]
                labelRect = frame.insetBy(dx: frame.width*0.2, dy: frame.height*0.2)
                    .offsetBy(dx: axes[0]*frame.width*0.22, dy: -axes[1]*frame.height*0.22)
                UIColor(white:0.23,alpha:1).setFill(); UIBezierPath(ovalIn: labelRect).fill()
            }
            let font = UIFont.systemFont(ofSize: min(26, frame.height * 0.43), weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font:font, .foregroundColor:colors[d.id] ?? UIColor(white:0.85,alpha:1)]
            let size = (d.label as NSString).size(withAttributes: attributes)
            (d.label as NSString).draw(at: CGPoint(x:labelRect.midX-size.width/2,y:labelRect.midY-size.height/2), withAttributes: attributes)
        }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard editing || model?.acceptsTouches == true else { return }
        for touch in touches {
            let location = touch.location(in: self)
            guard let d = ControlDefinition.all.reversed().first(where: { frames[$0.id]?.contains(location) == true }) else {
                if editing { model?.selected = nil; model?.size = 1 }; continue
            }
            nextID += 1; let token = nextID
            guard inputs.begin(token, control: d.id) else { continue }
            touchIDs[ObjectIdentifier(touch)] = token
            origins[token] = (location, layout[d.id]!)
            if editing { model?.selected = d.id; model?.size = layout[d.id]!.scale }
            else {
                move(touch, token: token)
                model?.changed(inputs.state, press: !d.stick)
            }
        }
        setNeedsDisplay()
    }
    private func move(_ touch: UITouch, token: Int) {
        guard let id = inputs.contacts[token], let frame = frames[id] else { return }
        let point = touch.location(in: self)
        if editing, let (start, original) = origins[token] {
            layout[id] = Placement(x: original.x + (point.x-start.x)/bounds.width*100,
                                   y: original.y + (point.y-start.y)/bounds.height*100, scale: original.scale).bounded
            calculateFrames()
        } else {
            inputs.move(token, x: (point.x-frame.midX)/(frame.width*0.32), y: (frame.midY-point.y)/(frame.height*0.32))
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { if let token = touchIDs[ObjectIdentifier(touch)] { move(touch, token: token) } }
        if !editing { model?.changed(inputs.state, immediate: false) }
        setNeedsDisplay()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    private func end(_ touches: Set<UITouch>) {
        for touch in touches {
            if let token = touchIDs.removeValue(forKey: ObjectIdentifier(touch)) { inputs.end(token); origins[token] = nil }
        }
        if editing { save() } else { model?.changed(inputs.state) }
        setNeedsDisplay()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { model?.clear() }
    }
}
