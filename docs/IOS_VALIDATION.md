# iOS / motion validation — 2026-09-12

Implementation branch: `codex/native-ios-motion`. This is a source implementation
and local validation record, not a claim of completed Windows/Eden acceptance.

## Build environment and installation

- Xcode **26.0.1**, build **17A400**, iOS 26 SDK; iOS deployment target **17.0**.
  The system developer selection pointed to CommandLineTools; commands explicitly
  used `/Applications/Xcode.app/Contents/Developer` without changing that selection.
- Both simulator architectures built. Signed physical-device builds succeeded
  using the existing local Apple development account and automatic provisioning.
  Signing credentials/profiles were not copied into the repository.
- Debug and final Release builds installed and launched on **iPhone 16 Pro Max, iOS 26.6.1 (23G83)** via USB after
  the user connected/unlocked it. The iPhone 11 Pro Max was detected but not used.
- The user scanned the preview QR and joined from the native app. The Mac observed
  the authenticated phone connection, validating camera pairing and local HTTP/WS
  access on that phone with `NSAllowsLocalNetworking` and no global ATS bypass.

## Automated results

| Check | Result |
| --- | --- |
| Python unittest discovery (desktop, base server, motion) | 28 passed |
| Existing browser controller tests | 17 passed |
| Swift package core tests on Mac | 8 passed |
| iOS simulator XCTest | 10 passed, 2 physical tests intentionally skipped |
| Physical sensor acquisition and cleanup | Passed on iPhone 16 Pro Max |
| Physical native WebSocket → Python → DSU integration | Passed on iPhone 16 Pro Max |

The native networking tests cover actual `ControllerModel`/URLSession pairing,
stationary hold beyond 750 ms, neutral epoch recovery, editing release,
background/reconnection, explicit host release stopping retries, and legacy
server operation without a motion capability. Core tests cover independent
multi-touch state, stick clamping, pairing validation, stale neutral completion,
layout persistence, orientation axis transforms and bounded joystick haptic pulses.

Python tests include independent published payload offsets and a bitwise CRC
reference, a known CRC check vector, real UDP output from WebSocket frames,
four mixed clients, sample replay rejection, epoch acknowledgements that must
clear motion, old-connection slot isolation, timeout neutralization, registration
modes/expiry/bounds, port conflict reporting and cleanup. Existing browser and
desktop lifecycle tests remain passing.

Physical end-to-end validation used `tests/run_device_motion.py` against a Mac
preview server. A real `ControllerModel` on the phone joined the LAN server,
enabled its real `MotionSource`, streamed for five seconds, then disabled motion.
The Mac observed **5,069 DSU packets**, including **281 active player-1 motion
packets**, **zero CRC failures**, and **neutral output after active motion**.
A separate physical test received >50 finite fresh samples with increasing
sequence/timestamps and verified sensor stop and sample cleanup. These are real
sensor acquisition/transport results; no simulator or mock generated those data.

The simulator's portrait and landscape editor were visually inspected. The
classic gray body, black controls and Xbox face colors are retained. Editing
uses the available control area without the disconnected pairing form.

## Haptic feedback and follow-up

The user felt the initial light button feedback on the physical phone and reported
that it was too weak, requesting joystick feedback too. The implementation was
updated to heavy button impacts, adjustable 30–100% strength (default 100%), and
rigid joystick movement pulses (minimum 0.18 normalized travel, maximum 12.5 Hz).
Held buttons/sticks stay quiet. Tests verify movement/cadence logic. Final physical
feel of the stronger setting and joystick pulses still needs user confirmation;
no simulator test establishes haptic quality.

## Still requiring acceptance validation

- **Windows:** rebuild `IControl.exe`, verify actual ViGEmBus/XInput output for four
  players, mixed browser/native gameplay, controller removal and UDP shutdown.
- **Eden:** record emulator version/game; bind the matching DSU slot and verify
  real pitch/yaw/roll direction, sensitivity, drift and aiming in portrait and
  both landscapes. Unit-tested axis mapping and real DSU packets do not establish
  in-game correctness. No Eden version/game was tested on this Mac.
- **Physical interaction:** extended simultaneous two-stick/multiple-button use,
  final haptic strength/pulses/off behavior, layout persistence across app relaunch,
  both landscape rotations, calibration while moving/still, lock/unlock, Wi-Fi
  loss and recovery, permission denial/retry, and two moving phones at once.
  Core/native integration tests cover these mechanisms in part, not all real-world
  event sequences or human interaction quality.
- **Older OS:** deployment/API compatibility is set to iOS 17, but iOS 17–25
  physical permission/network and sensor behavior has not been tested.
- No NFC, capture, game-driven rumble, App Store/TestFlight distribution, or
  two-independent-Joy-Con motion per phone is claimed.

## Windows follow-up — 2026-09-12

Follow-up during Eden setup: a closed DSU subscriber could trigger Windows ICMP
port-unreachable handling and stop Python 3.12's shared UDP receive loop. The
bridge now disables `SIO_UDP_CONNRESET` reporting on its own UDP socket. This
does not modify Windows Firewall. A real closed-peer/new-client regression test
failed before the fix and passed afterward. Existing subscriptions still expire
normally; new clients and Eden's Test can continue to receive responses.

- Pulled Mac implementation commit `b18e688` on `codex/native-ios-motion` and
  rebuilt `dist/IControl.exe` with Python 3.12.10 and PyInstaller 6.22.2.
- Host: Windows 11 Pro build 26200; installed ViGEmBus driver 1.17.333.0.
- Found and fixed Windows asynchronous UDP teardown: `transport.close()` can
  return with queued datagrams and an occupied socket. Shutdown now awaits
  `connection_lost`, with a bounded flush period and abort fallback. A regression
  test reproduced WinError 10048 before the fix and passed afterward.
- **29 Python tests and 17 browser tests passed** on Windows. The Python rerun
  completed without the UDP ResourceWarnings seen before the fix.
- The actual packaged EXE passed `tests/check_packaged_motion.py`: four synthetic
  mixed clients (two motion-enabled, two button-only), independent DSU slots,
  packet CRC/axis payload verification, stale motion neutralization, and desktop
  shutdown while clients/subscriptions exist. Both TCP and UDP ports were
  reusable after exit. Input is streamed at phone cadence for the fresh-sample
  check; a one-shot sample can expire during unrelated connection setup.
- The live EXE passed `tests/check_xinput.py`: four separate Windows controllers,
  matching ABXY, both sticks and triggers, and controller count 0 -> 4 -> 0.
- The final live server reported motion available on **127.0.0.1:26760**, no
  output error, and zero controllers while idle. The UDP binding was verified
  as loopback-only.
- Eden **v0.2.1** was running at its main window; no game or motion bindings were
  changed during these tests. **Physical iPhone -> this Windows PC -> Eden
  gameplay remains unverified**, including axis direction, sensitivity, drift,
  haptic feel, and two moving phones. The packaged test uses synthetic sensor
  values and is not a claim of physical motion acceptance.

## Reproduce physical transport test

Start the preview server and disconnect other preview clients:

```sh
.venv/bin/python server.py --simulate --port 8088
```

With an unlocked/trusted phone, build tests using your team and bundle identifier:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project ios/IControl.xcodeproj -scheme IControl \
  -destination 'platform=iOS,id=YOUR_DEVICE_UDID' \
  -derivedDataPath /tmp/icontrol-device DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ICONTROL_BUNDLE_ID=com.yourname.icontrol.companion \
  -allowProvisioningUpdates build-for-testing
.venv/bin/python tests/run_device_motion.py \
  --xctestrun /tmp/icontrol-device/Build/Products/IControl_iphoneos26.0-arm64.xctestrun \
  --device YOUR_DEVICE_UDID --port 8088
```

Adjust the generated `.xctestrun` filename to your SDK. The harness requires
preview mode, reads pairing only from localhost, injects it into a mode-0600
**temporary** test configuration and deletes that file afterward. It does not
print the pairing URL. Do not share raw Xcode result bundles, device logs or
build products, which can contain development environment details. Only source
and summarized test results belong in the Windows handoff.


## Standalone Joy-Con implementation — Mac update, 2026-09-12

Pulled shared branch through `87557e9`; Windows fixes `485b46f`, `613ef9f` and
`ff06a6e` remain ancestors and their implementation files are unchanged. The
user narrowed this task to **standalone Left/Right Joy-Con** and explicitly
excluded a two-phone setup. No pair workflow or paired-gameplay claim is included.
The existing four-source limit remains. The current Windows EXE is compatible;
only the iOS app needs updating. See [JOYCON_SETUP.md](JOYCON_SETUP.md).

Implemented visible Nintendo identities with one tested carrier table, distinct
SL/SR, separate stick clicks, upright/sideways defaults, ten independent saved
layouts, Full v1 migration, persisted mode/holding, and mode transitions through
the existing neutral InputGate. Motion applies the selected holding transform
once after the existing screen transform. Haptic settings and all network safety
mechanisms remain in place.

Completed before the user's request to stop running tests:

- Swift core: **13 passed**, including exhaustive control carriers, simultaneous
  rails/clicks/triggers/stick, Nintendo positions, axis basis vectors for every
  mode/holding/screen transform, saved-layout isolation and migration/reset scope.
- Simulator native XCTest: **16 passed, 3 physical-only tests skipped**. Actual
  native WebSocket tests observed neutral before new-mode input while contacts
  were held, rejected an attempted input during the barrier, verified persistent
  selection, distinct left/right SL/SR carriers and background release. Existing
  Full and legacy-server networking tests passed.
- Python: **30 passed**, including recent Windows UDP regression tests; browser:
  **17 passed**. No production Python, firewall or browser changes were required.
- Signed physical test build succeeded with Xcode **26.0.1 (17A400)** on the
  **iPhone 16 Pro Max, iOS 26.6.1**. The queued physical run waited for unlock and
  had already completed when cancellation was processed: **3 tests passed**.
  Real sensor streaming was observed in Left Upright, Left Sideways, Right
  Upright and Right Sideways, with fresh sequence numbers after transitions,
  finite data and motion stop cleanup. The harness observed **612 active DSU
  packets**, **zero CRC failures**, and neutral after active motion. These were
  sequential modes on one phone, not a two-phone test or feature.
- Simulator mode selection/editor rendering was inspected. A final small spacing
  adjustment moved the upright minus/plus button to the top row so it does not
  touch the stick/face cluster. That adjustment is included in the Release build;
  no tests were rerun after the user requested testing stop.

Further automated and physical interaction tests were stopped at the user's
request. Still unverified: hand-driven rotation direction for all three axes in
both physical landscapes; haptic strength/off behavior in the new modes;
extended real multi-touch/layout editing across app relaunch; actual standalone
Joy-Con movement, rails and motion aiming in Eden. The previous Windows record
lists Eden **v0.2.1**, but no new game/emulator session was tested on the Mac.
Basis/transport tests do not establish physical aiming quality or compatibility
with games that require a different controller style. No two-phone setup is
planned as part of this change.

The final signed Release build succeeded and was installed on the iPhone 16 Pro
Max. Installation is not an additional interaction or gameplay test. No further
tests were run after the stop request.


## Phone Controller rename and App Store preparation — 2026-09-12

The owner confirmed **`com.jakejin.IControl`** as the existing App Store Connect
bundle ID. The shared project now defaults to that exact ID and displays
**Phone Controller**, version **1.0 (2)**. The previously installed development
ID `com.jakejin.icontrol.companion` is a different app; it was not removed.

The final signed Release archive and local App Store distribution IPA export
succeeded using Xcode 26.0.1 / iOS 26 SDK. Archive inspection confirmed the name,
registered bundle ID, version/build, bundled privacy policy and privacy manifest.
The existing 1024 × 1024 app icon is opaque. Static syntax inspection of the
changed Python files and archive shell script completed without errors.

No tests, simulator interaction or physical-device runs were performed, in
accordance with the user's no-tests instruction. In particular, the new support/
privacy screens and longer branding have not received runtime visual acceptance.
The native ping now uses a constant echo field and sensor timestamps are relative
to the first usable sample rather than device boot; these privacy changes compiled
but were not exercised in a new transport test. Protocol formats remain unchanged.

The Windows EXE was not built on macOS. Windows must pull this revision and run
**Build Phone Controller.cmd** to produce **dist/Phone Controller.exe**. See
[WINDOWS_REBUILD.md](WINDOWS_REBUILD.md) for updated launchers, firewall upgrade
behavior and later Windows validation. App Store public URLs, screenshots and
review metadata still need completion; no upload or submission was performed.
See [APP_STORE_RELEASE.md](APP_STORE_RELEASE.md) for the artifacts and release steps.
