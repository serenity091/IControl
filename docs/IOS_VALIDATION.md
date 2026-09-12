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
