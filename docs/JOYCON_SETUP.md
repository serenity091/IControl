# Standalone Joy-Con modes

One iPhone can now act as a **Left Joy-Con** or **Right Joy-Con** source, alongside
its existing **Full controller** mode. This implements standalone use only. The
user explicitly excluded a two-phone Joy-Con Pair setup; no pairing workflow,
slot merging, or two-phone configuration is implemented or documented here.

The older Windows EXE from `ff06a6e` remains protocol-compatible with Joy-Con
input. Rebuild Windows for the **Phone Controller** branding as described in
[WINDOWS_REBUILD.md](WINDOWS_REBUILD.md); there are no changes to the server protocol, virtual
controller output, DSU bridge, firewall rules, or Windows packaging. Keep the
recent Windows UDP shutdown and departed-subscriber fixes.

## iPhone setup

1. Install the updated iOS build using [ios/README.md](../ios/README.md). Scan the
   running Windows Phone Controller QR from inside the app and tap Join game, or paste
   the complete pairing URL. Use the newest QR after a server restart.
2. Use the **Controller** menu above the touch surface to choose Full controller,
   Left Joy-Con, or Right Joy-Con. Joy-Con modes show an **Upright / Sideways**
   holding selector. The current choices remain visible and persist on relaunch.
3. Upright is a vertical one-stick layout. Sideways puts the stick left and the
   four-button cluster right, with SL/SR above. The logical holding selector is
   independent of phone portrait/landscape rotation; all combinations work, and
   both landscape rotations are supported. It does not configure the game's grip
   mode or change Eden's controller type automatically.
4. Edit layout, select/drag a control and adjust its size. Tap empty space to
   resize all controls. Done saves. There are ten independent saved layouts:
   Full portrait/landscape plus both holdings/orientations for each Joy-Con half.
   Reset affects only the current layout. Existing Full v1 layouts migrate on
   first use; their original preference keys remain intact. Reset writes defaults
   so a reset Full layout cannot unexpectedly resurrect the older saved layout.
5. Settings → Button and joystick haptics retains the existing off/strength
   controls. These are local tactile pulses, not Nintendo HD rumble or game rumble.
6. For motion, enable Motion and calibrate while still. The app reports sensor
   status and DSU subscriber status separately. Bind motion in Eden as below.

Changing mode or holding cancels all current contacts, clears the editor selection
and stick-haptic history, stops/discards motion, and sends neutral through the
existing InputGate. Input resumes only after that neutral send completes; lift
and touch again. It neither reconnects nor allocates another phone slot. The
same safety applies to backgrounding, screen lock, layout/geometry changes,
watchdog resets and reconnects. Healthy held controls still use keepalives.

## Exact button carriers and Eden bindings

The labels are Nintendo identities; the server still exposes an Xbox/XInput
controller. **Bind each input manually in Eden. Do not rely on Xbox auto-mapping**
for Nintendo A/B/X/Y or SL/SR. The app never sends unknown `SL` or `SR` wire names.
The button mapping stays the same in either holding layout.

| Visible control / Eden binding | Left Joy-Con wire → Xbox carrier | Right Joy-Con wire → Xbox carrier |
| --- | --- | --- |
| Stick | `lx,ly` → Left stick | `rx,ry` → Right stick |
| Stick click (separate **Click** button) | `L3` → Left stick click | `R3` → Right stick click |
| Directional Up / Down / Left / Right | `UP/DOWN/LEFT/RIGHT` → D-pad | — |
| Nintendo A / B / X / Y | — | `A/B/X/Y` → Xbox A/B/X/Y |
| L / R | `L` → LB | `R` → RB |
| ZL / ZR | numeric `zl` → LT | numeric `zr` → RT |
| SL | `X` → Xbox X | `L` → LB |
| SR | `Y` → Xbox Y | numeric `zl` → LT |
| Minus / Plus | `MINUS` → Back | `PLUS` → Start |
| Home | — | `HOME` → Guide |

SL, SR, outer shoulder, outer trigger, stick click and every other visible button
have distinct carrier outputs within that mode. Simultaneous SL+SR is supported.
Unused outputs stay neutral. Full controller and browser Xbox mappings do not
change. Capture, IR and NFC controls are omitted because there is no output path.

Right upright face positions are **X top, A right, B bottom, Y left**. A physical
right Joy-Con rotates clockwise for sideways use, yielding **Y top, X right,
A bottom, B left**. A physical left rotates counterclockwise: its original
**Right** directional button is at the top, **Down** at the right, **Left** at the
bottom and **Up** at the left. Sideways arrow glyphs point in their screen direction;
the wire identity remains the original upright directional button.

This arrangement follows Nintendo's [controller diagram](https://www.nintendo.com/au/support/articles/joy-con-controller-diagram/)
and [solo holding illustrations](https://www.nintendo.com/sg/support/switch/controller/joycon/joycon_useage.html).
Button text remains readable rather than rotating the text itself.

## Eden configuration: one phone, one standalone Joy-Con

These steps are based on Eden's current configuration source. The previous
Windows validation used **Eden v0.2.1**, but actual Joy-Con gameplay has **not** been
verified on that Windows build. Menu placement may vary; unsupported games may
reject a standalone controller even when inputs are bound correctly.

1. Start the existing Windows Phone Controller EXE and join the phone. Note its Phone Controller
   source slot (P1–P4). In Eden, open **Emulation → Configure → Controls** and
   enable the intended player. Choose **Joycon Left** or **Joycon Right** as that
   player's controller type, matching the app.
2. Choose that phone's Xbox/XInput device for input detection. Set the app to
   **Upright** while binding. Click each Eden button binding and press the matching
   named app control according to the carrier table above, including SL and SR.
   Use the separate Click button for stick press. Do not substitute L/ZL for the
   right half's SL/SR: although their carrier names overlap Xbox's unused left
   controls, they are different from the visible R/ZR controls.
3. Bind the half's **Left Stick** or **Right Stick** directions while the app is
   Upright: push up/right/down/left on screen for the corresponding Eden binding.
   Save a dedicated profile such as `Phone Controller Left standalone` or
   `Phone Controller Right standalone`. Check that all unused controls are unbound.
4. You may now choose Sideways in the app without rebinding. Stick movement is
   transformed once back into the upright hardware frame, matching the rotated
   button identities. Do not add another rotation/inversion in Eden on top of
   this profile. If you bind while Sideways, use the exact table below rather
   than treating the visible screen axes as upright hardware axes.
5. In Eden's **Motion / CemuhookUDP** configuration, enable the server at
   **127.0.0.1:26760** (or the EXE's configured `--dsu-port`). Enable Motion on
   the phone, calibrate while still, and return to the controls bindings.
6. Select **Any** input device if needed so the input detector can see the UDP
   source as well as the Xbox source. Bind **Motion 1** for Joycon Left or
   **Motion 2** for Joycon Right by moving this phone. Those are Eden motion-field
   names, **not** the DSU slot number. Confirm that the saved binding uses the
   phone's DSU pad: Phone Controller P1 → pad 0, P2 → 1, P3 → 2, P4 → 3. Restore neither
   auto-map nor a different device preset after manual binding, as it may replace
   these settings. Save the profile.
7. Test a game that supports a standalone half. Verify movement, face/directional
   labels, both rail buttons, stick click, motion direction and sensitivity.
   Calibrate/recenter through the game as needed. The app's gyro calibration
   removes rate bias, not absolute camera aim.

Eden [shows Motion 1 for a left half and Motion 2 for a right half](https://github.com/eden-emulator/mirror/blob/master/src/yuzu/configuration/configure_input_player.cpp)
and stores separate per-control input parameters. Its [Npad implementation](https://github.com/eden-emulator/mirror/blob/master/src/hid_core/resources/npad/npad.cpp)
forwards standalone half inputs and marks the standalone types horizontal. The
app holding selector does not override that emulator/game behavior. Upright
use depends on what the game does with that controller style; selecting Upright
in the app is not a promise that every game supports one-handed vertical play.

| When binding while Sideways | Left half: move stick on screen | Right half: move stick on screen |
| --- | --- | --- |
| Eden hardware stick Up | Left | Right |
| Eden hardware stick Right | Up | Down |
| Eden hardware stick Down | Right | Left |
| Eden hardware stick Left | Down | Up |

For example, a lone Right Joy-Con phone in **Phone Controller P1** still uses its Xbox
**right stick**, and **DSU pad 0** is bound to Eden **Motion 2**. Slot numbers
identify phone sources. Every connected phone consumes one of the existing four
slots; this feature does not increase that limit or create extra virtual devices.

## Motion coordinate contract

Motion remains extension v1: finite total acceleration including gravity in g,
angular velocity in degrees/second, per-phone sequence/timestamp protection,
calibration and sensitivity. See [MOTION_PROTOCOL.md](MOTION_PROTOCOL.md) for DSU
layout, timeout and lifecycle behavior. There is one physical source per phone.

Transforms run in this order:

1. Core Motion device axes → right-handed **screen** frame using the existing
   `UIInterfaceOrientation` transform (X right, Y toward top, Z out of glass).
2. Screen frame → selected half's **upright hardware** frame using the table below.
3. Serialize this vector to DSU fields as before. Eden applies its existing
   `(pitch,roll,-yaw)` gyro and `(x,-z,y)` acceleration remaps once.

| Mode / logical holding | Hardware vector from screen `(x,y,z)` |
| --- | --- |
| Full, either screen orientation | `(x,y,z)` (unchanged) |
| Left or Right Upright | `(x,y,z)` |
| Left Sideways | `(y,-x,z)` |
| Right Sideways | `(-y,x,z)` |

The same proper rotation applies to acceleration and angular velocity. The
stick uses its first two components after screen-space normalization/deadzone;
UIKit screen rotation is **not** applied again to touch coordinates. Physical
screen orientation and logical holding are independent. Changing either clears
old samples before sampling in the new frame. Bias is measured in device space
before those rotations; no attitude/Euler angle is used as angular velocity.

Basis-vector tests cover X/Y/Z for all holding modes and all four screen transforms,
including both landscapes. This verifies the mathematical contract. Actual
physical directional aiming in Eden, drift and per-game grip behavior remain
acceptance checks. Gyro does not add IR, NFC, HD rumble or absolute positional
tracking, and one phone does not reproduce two independently moving controllers.

See [IOS_VALIDATION.md](IOS_VALIDATION.md) for the dated automated and physical
results, plus remaining human/device/gameplay checks.
