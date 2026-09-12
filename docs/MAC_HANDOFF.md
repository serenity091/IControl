# IControl iOS handoff

Prepared 2026-09-12. **Historical development brief.** The native app and motion bridge have since been implemented; see [ios/README.md](../ios/README.md), [IOS_VALIDATION.md](IOS_VALIDATION.md), and [WINDOWS_REBUILD.md](WINDOWS_REBUILD.md) for current status. The sections below describe the original handoff.

## Goal

Build a native iPhone controller app for the existing IControl Windows server and Eden emulator. Keep the classic gray/black Xbox-style controls with green A, red B, blue X, yellow Y. Preserve simultaneous touches, adjustable button positions/sizes, separate portrait/landscape layouts, and up to four connected phones. Add native button-press haptics and phone motion for compatible Eden games.

The Windows computer still runs the emulator and IControl.exe. The Mac builds/signs the iPhone app. GitHub is only for transferring source; controller traffic stays on the local network. Moving development to a Mac does not port the Windows virtual gamepad output to macOS.

## What already works

- `server.py`: aiohttp LAN HTTP/WebSocket server, pairing tokens, four player slots, Xbox/XInput output through vgamepad and ViGEmBus on Windows.
- `desktop.py`: native Tk QR/status window owns the server; closing it stops the server and removes controllers.
- `static/controller.js`, `play.html`, `classic.css`: working classic controller, saved layout editor, reference control placement and input safety.
- `tests/test_server.py`, `tests/test_desktop.py`, `tests/controller.test.cjs`: 32 tests passed at handoff. Existing Windows XInput check verified four independent pads and removal.
- `build_exe.py`: Windows-only packaging. Run this to regenerate the machine-specific PyInstaller spec; do not reuse a spec from another checkout.

No native iOS code, haptic implementation, sensor streaming, or DSU motion server exists yet. The current server ignores unknown message types and has no motion output; an iOS-only gyro implementation would not be enough.

## Transfer and Mac setup

1. Clone `https://github.com/serenity091/IControl.git` on the Mac and open the `IControl` folder as the project in Codex. The repository is public at the owner's request. Keep device pairing secrets, Apple signing files, and local build output out of Git.
2. Install Xcode from Apple, launch it to finish installing components, and sign in with your Apple Account. Choose an Xcode version supported by that Mac and the test iPhone's iOS version.
3. Connect a physical iPhone to the Mac. Complete device trust and Developer Mode prompts when Xcode requires them. Set the iOS target's signing team and a unique bundle identifier in Xcode. Do not commit signing secrets.
4. Start the Mac Codex task using `docs/IOS_TASK.md` below. No transcript from the Windows task is required.
5. Test first against a preview server on the Mac, then the live Windows server on the same LAN. A simulator can validate layout/networking but cannot establish real phone haptic/sensor quality.

With Python 3.12 installed, a preview server can run without the Windows driver:

```sh
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python server.py --simulate --port 8080
```

Open `http://localhost:8080` on the Mac for the QR dashboard. Use the Mac's LAN address for the iPhone, not localhost. Preview mode creates no OS controllers. If port 8080 is occupied choose another port; the QR includes that port.

```sh
python -m unittest discover -s tests -p test_server.py -v
node --test tests/controller.test.cjs
```

The desktop lifecycle tests additionally import Tkinter; install a Python build with Tk support before running full discovery on the Mac. `tests/check_xinput.py` is Windows-only and requires an idle live server with no physical XInput controllers.

## iOS implementation

Use Swift and SwiftUI for screens, with UIKit multi-touch handling if needed for reliable independent control contacts. Do not rely on a WebView for haptics/motion or replace the controls with ordinary tap-only buttons. Create a checked-in, buildable Xcode project under `ios/` and document exact build/run steps.

First milestone: QR scan/manual pairing URL, player name, WebSocket client, both sticks/all buttons, cancellation/reconnection safeguards, layout editing/persistence, and a haptics toggle. Use UIImpactFeedbackGenerator for short local press feedback, or Core Haptics if there is a concrete need. Haptic work must not block input transmission. Check hardware capability and handle interruptions. Continuous game-driven rumble is a separate feature from button-press feedback.

Second milestone: Core Motion acquisition, calibration/recenter, motion enable/sensitivity controls, a versioned wire extension, and the matching Python DSU/Cemuhook server for Eden. Use rotation rate and acceleration with documented units and coordinate transforms. Do not send Euler angles as gyro angular velocity. Account for portrait/landscape and screen rotation; test each axis. Core Motion rotationRate is radians/second; check the target DSU conventions before conversion. Native motion access avoids the browser HTTPS-only sensor restriction, but local network transport still needs correct iOS configuration.

Request camera and local network access with clear usage descriptions. Audit required motion usage descriptions for the chosen APIs. Handle permission denial with a useful retry/settings message and manual pairing fallback. Configure only the local-network ATS allowance needed for this local ws/http protocol; verify it on a physical iPhone and supported OS versions. Do not disable ATS globally or invent a trusted HTTPS setup. Scanning the existing QR inside the app is enough for v1; opening a plain HTTP QR with the system Camera will still open the website unless a separate deep-link design is added.

## Motion server integration

The existing virtual Xbox pads provide buttons/sticks only. Add a DSU/Cemuhook UDP endpoint alongside them, preferably bound to loopback (Eden runs on the same PC). Use port 26760 if available; report conflicts clearly. Integrate UDP start/stop into the same server lifecycle, including preview mode, without leaving a background process. Support one independent motion source per player, no more than four. One phone is one physical motion source, not two independently moving Joy-Cons.

Keep the current browser client working. Negotiate/advertise new motion capability so the app can say that motion requires a newer server when used with the current EXE. Define validated, bounded motion data and stale-sample behavior. Consider coalescing motion with input frames to stay below the server's 180-message/second limit. Extend timeout/reconnect generation protections to motion, reset on disconnect/background/release, and prevent an old connection from modifying a reused player slot.

Implement protocol version, length, CRC32, controller metadata/subscriptions, packet counters, timestamps, and DSU payload layouts from primary protocol references. Add independent fixtures/tests, not only encoder/decoder round trips. Document Eden setup and verify actual motion binding with the Windows build. Changes to Python must return to Windows for rebuilding/testing the EXE; a Mac cannot validate ViGEmBus/XInput output.

## Acceptance checks

- Real iPhone scans the existing QR, joins, and drives its own Windows pad; four phones remain independent, including mixed browser/native clients.
- Holding a stick plus multiple buttons works; press haptics can be disabled and do not retrigger continuously while held.
- Missed releases, app backgrounding, screen lock, network loss, reconnect, stale frames, layout changes, and host release cannot leave input pressed.
- Healthy stationary holds are not cleared by an arbitrary hold-duration timer. Neutral reset acknowledgement follows the existing epoch protocol.
- Layout position/size changes persist across launches and orientations. Keep the simple classic appearance.
- Sensor hardware/permissions/capability failures are shown honestly; the app does not claim motion is working just because it can read sensors.
- DSU packets pass protocol checks and an actual iPhone can aim/tilt in Eden. Record the tested phone, iOS version, Eden version, axis mapping, and limitations.
- Windows EXE still starts its server on launch and stops all outputs on close. Existing tests pass alongside meaningful new iOS/server motion tests.

## References

- [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Apple local networking ATS setting](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)
- [Core Motion](https://developer.apple.com/documentation/coremotion)
- [Core Haptics](https://developer.apple.com/documentation/corehaptics)
- [Apple account and Personal Team limitations](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [Eden DSU motion consumer](https://github.com/eden-emulator/mirror/blob/master/src/input_common/drivers/udp_client.cpp)

Use current primary documentation when implementing. A free Personal Team can install development builds on your own phone, but provisioning expires after seven days. TestFlight/App Store distribution requires Apple Developer Program membership. Verify current requirements before choosing distribution.
