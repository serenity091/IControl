import SwiftUI

@main struct IControlApp: App {
    @StateObject private var model = ControllerModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.light)
                .onChange(of: phase) { _, value in model.setActive(value == .active) }
        }
    }
}
struct ContentView: View {
    @ObservedObject var model: ControllerModel
    @State private var url = ""
    @State private var name = UserDefaults.standard.string(forKey: "playerName") ?? "iPhone"
    @State private var scanner = false
    @State private var settings = false
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("ICONTROL").font(.headline)
                Text(model.status).font(.caption).lineLimit(2).accessibilityIdentifier("connectionStatus")
                Spacer(minLength: 4)
                Button(model.editing ? "Done" : "Edit layout") { model.setEditing(!model.editing) }
                Button { model.clear(); settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
            }.font(.subheadline)
            HStack {
                Picker("Controller", selection: Binding(get: { model.configuration.mode }, set: {
                    model.selectConfiguration(.init(mode: $0, holding: .upright))
                })) {
                    ForEach(ControllerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("controllerMode")
                if model.configuration.mode != .full {
                    Picker("Holding", selection: Binding(get: { model.configuration.holding }, set: {
                        model.selectConfiguration(.init(mode: model.configuration.mode, holding: $0))
                    })) {
                        ForEach(HoldingLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("holdingLayout")
                }
            }.font(.subheadline)
            if !model.connected && !model.editing {
                VStack(spacing: 8) {
                    TextField("Player name", text: $name).textContentType(.nickname).accessibilityIdentifier("playerName")
                    SecureField("Pairing URL: http://host:port/play#key=…", text: $url)
                        .textContentType(.none).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("pairingURL")
                    HStack {
                        Button("Scan QR") { model.disconnect(); scanner = true }
                        Button(url.isEmpty && model.hasPairing ? "Rejoin game" : "Join game") {
                            if url.isEmpty && model.hasPairing { model.rejoin(name: name) }
                            else { model.join(url: url, name: name); url = "" }
                        }.accessibilityIdentifier("joinGame")
                    }.buttonStyle(.borderedProminent).tint(Color(white:0.2))
                }.textFieldStyle(.roundedBorder).font(.body)
            }
            if model.editing {
                HStack {
                    Text(model.selected ?? "All controls").font(.caption)
                    Slider(value: Binding(get: { model.size }, set: { model.size = $0; model.applySize?($0) }), in: 0.6...1.6)
                    Button("Reset") { model.applySize?(0) }
                }
                Text("Drag a control to move it. Tap empty space to resize all.").font(.caption)
            }
            TouchSurface(model: model)
        }
        .padding(12).background(Color(white:0.92)).tint(Color(white:0.2))
        .sheet(isPresented: $scanner) {
            NavigationStack {
                QRScanner { value in url = value; scanner = false }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { scanner = false } } }
            }
        }
        .sheet(isPresented: $settings, onDismiss: { model.clear() }) {
            SettingsView(model: model, motion: model.motion)
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: ControllerModel
    @ObservedObject var motion: MotionSource
    @Environment(\.dismiss) private var dismiss
    @State private var sensitivity = 1.0
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Button and joystick haptics", isOn: $model.haptics).disabled(!model.supportsHaptics)
                if model.haptics && model.supportsHaptics {
                    Text("Haptic strength: \(Int(model.hapticStrength * 100))%")
                    Slider(value: $model.hapticStrength, in: 0.3...1)
                    Text("Strong button impacts and short pulses as a stick moves. Held controls stay quiet.").font(.caption)
                }
                if !model.supportsHaptics { Text("Haptic hardware unavailable on this device").font(.caption) }
                Toggle("Motion", isOn: $model.motionEnabled).disabled(!model.motionAvailable)
                Text(model.motionMessage)
                Text(motion.status)
                Text(model.subscribers > 0 ? "DSU client subscribed · verify motion in Eden" : "No DSU client subscribed yet")
                Text("Motion sensitivity: \(sensitivity, specifier: "%.2f")×")
                Slider(value: $sensitivity, in: 0.25...3).onChange(of: sensitivity) { _, value in motion.sensitivity = value }
                Button("Calibrate gyro bias / recenter") { motion.calibrate() }.disabled(!model.motionEnabled || !model.motionAvailable)
                Text("Keep the phone still for one second. This removes rotation-rate bias; use Eden to recenter game aim. One phone supplies one motion source.").font(.caption)
                Button("Open app Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("Disconnect") { model.disconnect(); dismiss() }
            }.navigationTitle("Controller settings")
                .onAppear { sensitivity = motion.sensitivity }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
