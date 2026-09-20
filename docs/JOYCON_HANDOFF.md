# Native iOS Joy-Con mode handoff

Requested 2026-09-12. These are implementation requirements, not completed features.

## Start from the current branch

Use `codex/native-ios-motion`, including the Windows fixes through `ff06a6e` and
this handoff. Fetch and fast-forward on the Mac before editing; preserve any
uncommitted Mac work and resolve divergence without resetting it away.

```sh
git fetch origin
git switch codex/native-ios-motion
git pull --ff-only
```

Native iOS controls, editable layouts, haptics and Core Motion streaming already
exist. Extend those implementations; do not recreate the app from the original
`IOS_TASK.md`. Read `ios/README.md`, `CONTROLLER_PROTOCOL.md`, `MOTION_PROTOCOL.md`
and `IOS_VALIDATION.md` before making changes.

Recent fixes that must remain:

- `485b46f`: await actual UDP transport/socket shutdown before closing the loop.
- `613ef9f`: repair conflicting private-network Windows TCP application blocks.
- `ff06a6e`: suppress per-socket Windows UDP connection-reset reporting so a
  departed DSU subscriber cannot stop the shared receive loop.

The latest Windows EXE contains these fixes. Thirty Python server tests and
seventeen browser tests passed across the recent validation runs. The EXE was
verified to answer a new DSU client after a previous subscriber disconnected.
Physical motion binding/gameplay has not yet been verified in Eden.

## Product behavior

Add a simple controller-mode selection in the native app:

1. **Full controller** — preserve the existing classic Xbox layout and mapping.
2. **Left Joy-Con** — one stick, four directional buttons, L, ZL, SL, SR, minus,
   and a separately usable stick-click control.
3. **Right Joy-Con** — one stick, Nintendo-arranged A/B/X/Y, R, ZR, SL, SR, plus,
   Home, and a separately usable stick-click control.

Provide **Upright** and **Sideways** holding layouts within each Joy-Con mode.
Portrait should be comfortable for one-handed upright use; landscape should be
comfortable for a sideways single Joy-Con. Make the selected mode and holding
layout clear without a setup wizard. Distinguish this logical holding choice
from physical screen orientation and retain a usable layout in either screen
orientation. Support both landscape rotations.

Keep the design simple: flat gray/black controls, clear labels, generous spacing.
The existing full controller retains its Xbox colors and arrangement. Joy-Con
mode uses Nintendo labels and arrangement, not the full controller's Xbox
positions. Avoid ornamental graphics, complex menus, or neon effects.

Allow button position/size customization in every mode. Save layouts separately
by controller mode, holding layout and screen orientation. Preserve existing
`icontrol-native-layout-v1-*` full-controller layouts via a tested migration or
fallback. Reset affects only the selected layout. Persist the chosen mode.

Do not show a functional-looking Capture/NFC/IR/HD-rumble control without an
implemented path. Capture is currently unsupported by the Windows bridge; omit
it or explicitly disable it. Native button/joystick haptics remain available,
including strength and off settings; these are not game-driven HD rumble.

## One phone, one physical motion source

A single phone represents one independently moving Joy-Con. Do not claim a mode
switch creates two independent motion sources from one sensor.

Support and document these use cases:

- One phone as a standalone left or right Joy-Con for one player, where the game
  supports that controller type. This is the simplest/default setup.
- Two phones, one in Left Joy-Con mode and one in Right Joy-Con mode, as two
  independent sources. Evaluate Eden's Joy-Con Pair configuration to bind both
  sources to one emulated player. Use Eden's existing per-control bindings if
  sufficient; do not claim paired gameplay until verified on Windows.

Keep **four simultaneous phones total**. With the existing transport, each phone
uses one server slot, one virtual Xbox device and one DSU slot. Two phones for a
pair consume two of these slots. A server slot number identifies a phone source;
it is not necessarily the same as Eden's player number when two phones share an
emulated player. Do not introduce an eight-phone limit or silently merge slots.

If Eden cannot combine these sources as required, document the concrete limitation
and propose the smallest compatible server extension. Do not fabricate working
pair support or silently map both emulated Joy-Cons to the same phone motion.
No separate accounts, cloud service or in-app pairing protocol is needed unless
testing establishes that the existing Eden mapping cannot provide the workflow.

## Input identity and transport

Treat visible Joy-Con control identity separately from the Xbox transport used
by the Windows server. Merely changing labels is not a complete implementation.
Use one tested mapping table to connect each visible control to its wire output.
The server currently filters unknown button names, so adding `SL` or `SR` to a
JSON button array without a server implementation would silently drop them.

Prefer the current protocol when it can provide distinct outputs. A proposed
collision-free transport mapping is below; verify it against Eden's actual
binding behavior and document any justified changes:

| Joy-Con control | Left mode wire output | Right mode wire output |
| --- | --- | --- |
| Stick | `lx`, `ly` | `rx`, `ry` |
| Stick click | `L3` | `R3` |
| Directional buttons | `UP`, `DOWN`, `LEFT`, `RIGHT` | not present |
| A/B/X/Y | not present | matching `A`, `B`, `X`, `Y` wire identity |
| L / R outer shoulder | `L` | `R` |
| ZL / ZR outer trigger | numeric `zl` | numeric `zr` |
| SL | `X` (unused face output in left mode) | `L` (unused left shoulder in right mode) |
| SR | `Y` (unused face output in left mode) | numeric `zl` (unused left trigger in right mode) |
| Minus / Plus | `MINUS` | `PLUS` |
| Home | not present | `HOME` |

These are carrier outputs, not a promise that Eden's automatic Xbox mapping will
match Nintendo labels. Provide exact per-mode Eden binding instructions/tables.
SL/SR must remain independent of every other visible button, including when held
together. All unused outputs must stay neutral. Keep the old full-controller and
browser wire mappings unchanged.

Define how sideways directional controls and stick movement correspond to Eden's
single-Joy-Con axes. A correct UI rotation must not accidentally rotate the stick
twice. Verify native Joy-Con layout/orientation against primary Nintendo/Eden
references rather than guessing the rotated A/B/X/Y positions.

## Motion and input safety

Retain optional Core Motion, calibration, sensitivity and per-phone DSU identity.
Continue sending finite acceleration including gravity in g and gyro angular
velocity in degrees/second using the documented protocol. Do not send attitude
angles as rotation rate or create fake absolute position tracking.

Define and test the transform from device axes to the selected Joy-Con holding
frame. Keep UI screen rotation, logical upright/sideways holding and the DSU/Eden
axis remap separate so each transform is applied exactly once. Use basis-vector
tests and a physical iPhone; verify all three rotation axes in both landscapes.
Any mapping change must preserve full-controller motion behavior.

Changing controller mode or holding layout must cancel all contacts, stop/clear
motion, send neutral through the existing InputGate acknowledgement path, rebuild
the layout, and resume only from new touches/fresh samples. Do not reuse a held
button, stale sensor sample or queued send from the previous mode. Clear an
invalid editor selection and stick haptic history when the mode changes.

Preserve multi-touch, normal indefinite holds with keepalives, epoch resets,
bounded sends, reconnect protection, screen lock/background release, geometry
change cancellation and host-release behavior. Do not recreate the Windows
connection issues by undoing recent fixes.

## Code entry points

- `ios/IControl/ControllerCore.swift`: modes, definitions, mappings, contact state,
  saved layout keys/migration, orientation/holding transforms and core tests.
- `ios/IControl/TouchSurface.swift`: mode-specific rendering/hit-testing, editor,
  simultaneous contacts and safe geometry transitions.
- `ios/IControl/ControllerModel.swift`: persisted mode, neutral transitions,
  transport mapping and haptic state; preserve send generation protections.
- `ios/IControl/IControlApp.swift`: compact settings/mode selection and useful
  connection/motion status.
- `ios/IControl/MotionSource.swift`: holding-frame transform integration if needed.
- `ios/Tests/`, `tests/`: meaningful regression tests; extend Python only if the
  wire protocol or bridge changes.

## Acceptance and return handoff

- Build both simulator and physical-device targets with the Mac's signing setup.
- Test every mode/control against the documented output mapping, especially
  simultaneous SL+SR, stick clicks and buttons while moving a stick.
- Test mode/holding changes while input is held; the server must see neutral
  before new input. Test disconnect, background, screen rotation and recovery.
- Test separate layout persistence, Reset scope and full-controller migration.
- Verify short haptics/off/strength behavior with the user's real phone.
- Verify motion acquisition and transport for left/right independently. Mark
  two-phone/Eden checks pending if the hardware or emulator is unavailable.
- Run existing relevant Swift/native, Python and browser tests. Do not claim
  physical aiming quality or game compatibility from packet tests alone.
- Add `docs/JOYCON_SETUP.md` with exact iPhone and Eden setup, mode-to-wire mapping,
  screenshots if useful, slot examples and supported/untested limitations.
- Update the validation record with tested phone/iOS and emulator/game versions,
  physical axis results, one-phone vs two-phone results and remaining checks.
- Commit and push the implementation and docs to the shared branch. If server
  changes are necessary, update `WINDOWS_REBUILD.md` and explicitly tell the
  Windows task to rebuild/test the EXE. Otherwise state that the current Windows
  EXE is compatible and only the iOS build needs updating.

Do not publish signing files, pairing URLs, raw device logs or generated builds.
Do not change `main` or force-push to resolve cross-computer divergence.
