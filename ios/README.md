# Phone Controller native iPhone companion

Open `ios/IControl.xcodeproj`. This is a SwiftUI app with a UIKit multi-touch
surface, AVFoundation QR scanner, native haptics and optional Core Motion. It
uses the existing gray/black Xbox layout and speaks the existing LAN protocol.
There are no package dependencies, accounts, analytics or cloud runtime services.

App Store preparation, archive/export commands, metadata and remaining release
requirements are in [APP_STORE_RELEASE.md](../docs/APP_STORE_RELEASE.md). The visible
app name and product are **Phone Controller**; the Xcode project, module, bundle-ID
setting and saved preference keys retain their internal names for compatibility.

## Build and install

This checkout was built with **Xcode 26.0.1 (17A400)** and the iOS 26 SDK after
inspecting the Mac and paired phones. Deployment target is **iOS 17.0**. iOS 17
is the API floor; iOS 17 hardware/runtime behavior has not been validated here.
The Mac's `xcode-select` currently points to CommandLineTools, so use:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
open ios/IControl.xcodeproj
```

1. In Xcode Settings → Accounts, sign in with your Apple Account if needed.
2. Select target **IControl** → Signing & Capabilities → your development Team.
   Leave **Automatically manage signing** enabled. Set the **ICONTROL_BUNDLE_ID**
   build setting to **`com.jakejin.IControl`**, the registered App Store Connect
   identifier confirmed by the owner (now the project default). Tests derive a
   `.tests` identifier from it. Use a different ID only for an intentional separate
   development install.
3. Connect/unlock the iPhone, accept Trust prompts, and enable Developer Mode
   when requested. Select that iPhone as the run destination, then Product → Run.
4. Allow Camera when scanning and Local Network when connecting. In the app,
   Scan QR from the running Phone Controller dashboard, then Join game. Alternatively
   paste the complete `http://host:port/play#key=…` URL. System Camera scanning
   still opens the browser client; it is not a native deep link.
5. For permissions denied earlier, Settings → Open app Settings provides a
   recovery path. Manual pairing works without camera access. If the host
   restarted, scan its new QR. Rejoin retains the previous pairing only in memory.

Command-line simulator build (no signing):

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project ios/IControl.xcodeproj -scheme IControl \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/icontrol-derived CODE_SIGNING_ALLOWED=NO build
```

Signed device build using your local team and identifier:

```sh
xcodebuild -project ios/IControl.xcodeproj -scheme IControl \
  -destination 'generic/platform=iOS' -configuration Debug \
  -derivedDataPath /tmp/icontrol-device \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID ICONTROL_BUNDLE_ID=com.jakejin.IControl \
  -allowProvisioningUpdates build
xcrun devicectl list devices
xcrun devicectl device install app --device YOUR_DEVICE_ID \
  "/tmp/icontrol-device/Build/Products/Debug-iphoneos/Phone Controller.app"
xcrun devicectl device process launch --device YOUR_DEVICE_ID com.jakejin.IControl
```

No team ID, certificate, provisioning profile or pairing token is stored in this
project. For a free Personal Team, provisioning expires after seven days; rebuild
and reinstall through Xcode. See [Apple's account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Controls

Use the Controller menu to choose Full controller, Left Joy-Con, or Right Joy-Con.
Each standalone Joy-Con has Upright and Sideways holding layouts, Nintendo
identities and independent SL/SR carriers. See [JOYCON_SETUP.md](../docs/JOYCON_SETUP.md)
for exact Eden bindings, stick/motion transforms and supported scope. No two-phone
Joy-Con Pair setup is included.

Both sticks and every button own independent touches until release/cancellation.
Editing, resizing, rotation, leaving the app, watchdog resets and reconnection
cancel old contacts. Lift and touch again after an interruption. A healthy held
control is sustained by keepalives, not expired by a hold-duration timer.

Edit layout → drag a control → adjust its size; tap empty space to resize all.
Done saves. Reset restores classic defaults. Mode/holding/orientation combinations use separate
UserDefaults keys; old Full layouts migrate without changing their original keys; layout and installation UUID persist between launches. Pairing
secrets do not. The screen stays awake while connected in the foreground.

Settings provides haptics (off initially) with adjustable strength: heavy button
press impacts and rigid pulses as joystick position changes, capped at 12.5 Hz.
Stationary sticks and held buttons do not repeat. Turning haptics off disables
both. This is local tactile feedback, not game-driven rumble.

Motion is off initially and requires a v1-capable server with a working DSU bind.
Enable it, calibrate while still, and select the player's motion source in Eden.
The status distinguishes sensors, bridge readiness and DSU subscriptions. It
never interprets sensor acquisition as proof of emulator support. See
[MOTION_PROTOCOL.md](../docs/MOTION_PROTOCOL.md) for units, axes and cleanup.

## Networking and privacy

Only `http` pairing URLs with `/play`, a valid host/port, one bounded fragment key
and no credentials/query are accepted. The key is retained in memory and is never
written to preferences or logged. All network and input state transitions are
serialized on the main actor; late socket and motion callbacks are rejected by
generation. One send may be outstanding; newer state is coalesced rather than
queued. Fatal pairing/policy errors and host release stop automatic retries.

Info.plist declares Camera, Local Network and Motion usage descriptions and only
`NSAllowsLocalNetworking` in ATS. It does not enable global arbitrary loads.
No Bonjour browsing, multicast entitlement or background execution is used. See
[Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
and [local networking ATS](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).
Use the computer's LAN address on the phone, not localhost. Traffic is unencrypted
and intended for trusted local Wi-Fi only, as with the existing browser client.

## Tests

From the repository root:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path ios
.venv/bin/python -m unittest discover -s tests -v
node --test tests/controller.test.cjs
```

For the native networking tests, run the fixture in another terminal. It binds
**loopback only**, adds one test-only expiry endpoint, and must never be shipped:

```sh
.venv/bin/python tests/native_fixture.py
```

Then run Product → Test with an iPhone simulator, or:

```sh
xcrun simctl list devices available
xcodebuild -project ios/IControl.xcodeproj -scheme IControl \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/icontrol-derived CODE_SIGNING_ALLOWED=NO test
```

`CoreTests` covers pairing validation, simultaneous touch state, stick clamps,
neutral generations, haptic movement cadence, layout serialization and motion
axis conversion. `NetworkTests` runs the actual native URLSession client against
Python and checks stationary holds, resets, editing, background/reconnection and
host release. It requires the simulator and the fixture on ports 8089 and 8090 (legacy endpoint).
`DeviceMotionTests` skips in a simulator; run only this class on a physical phone
with `-only-testing:IControlTests/DeviceMotionTests` to check real sensor sample
acquisition and stop cleanup. The optional physical network test needs the
`tests/run_device_motion.py` harness described in the validation record. It does not validate haptic feel or in-game aiming.

The Python tests include independent CRC/payload fixtures, real UDP/WebSocket
integration, four mixed clients, replay/epoch isolation, stale output,
subscriptions and UDP lifecycle conflicts. See the dated
[validation record](../docs/IOS_VALIDATION.md) for actual results and remaining
physical/Windows acceptance checks.
