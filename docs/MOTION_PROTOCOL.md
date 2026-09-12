# Native motion extension and Eden DSU bridge

Implemented wire extension v1; existing browser input frames remain valid. See
[CONTROLLER_PROTOCOL.md](CONTROLLER_PROTOCOL.md) for pairing, buttons, epochs and releases.

## Capability and transport

The `joined` response adds:

```json
{"capabilities":{"motion":{"version":1,"available":true,"host":"127.0.0.1","port":26760,"error":null}}}
```

`host` is the **Windows computer's loopback**, for Eden; the phone never connects
to it. Motion goes over the authenticated `/ws` connection. An absent capability
means an older EXE: buttons still work, and the native app disables motion with an
upgrade message. A failed UDP bind sets `available:false` and an actionable error
without disabling XInput. The desktop and browser dashboards display that error.
`--no-motion` disables DSU; `--dsu-port N` changes its port in both `server.py` and
`desktop.py` / the built EXE. Default UDP binding is strictly `127.0.0.1:26760`.
No additional inbound Windows firewall rule is needed for Eden on the same PC.

Motion is optional on each full input frame:

```json
{"type":"input","epoch":0,"state":{"buttons":[],"lx":0,"ly":0,"rx":0,"ry":0,"zl":0,"zr":0},"motion":{"v":1,"seq":123,"timestamp":1230000,"accel":[0,0,-1],"gyro":[0,0,0]}}
```

- `v`: integer 1. `seq` and `timestamp`: nonnegative integers <= 2^53−1.
- `seq` increases for every newly acquired sensor sample; `timestamp` is Core
  Motion monotonic acquisition time in **microseconds**, not wall clock time.
  Phone Controller iOS builds use elapsed time since the first usable sensor
  sample of that app process; the origin survives mode changes and reconnects.
  Older clients use time since boot. The server only compares ordering/deltas,
  so both representations remain compatible.
- Both must increase within one connection. Duplicates/out-of-order samples do
  not replace or refresh motion. The last accepted sample expires independently.
- `accel`: exactly three finite numbers, **g**, each within ±16, including gravity.
- `gyro`: exactly three finite numbers, **degrees/second**, each within ±4000.
  Booleans, NaN/infinity, wrong shapes and unsupported versions close the socket
  and release its output. The phone bounds values before encoding.
- Omitted or `null` motion clears the source immediately. Old browser clients
  need no change and do not create active DSU motion sources.
- Motion never reserves a separate slot. Player 1–4 maps to DSU slot 0–3, with
  per-player samples, replay counters and the existing socket ownership checks.

The native app acquires at 60 Hz, coalesces network motion/movement around 30 Hz,
keeps button transitions prompt, and serializes one outstanding WebSocket send.
A 120 Hz maximum send cadence bounds aggregate traffic below 180 messages/sec.
A stalled send (>500 ms), stalled loop (>750 ms), join timeout or absent pong
releases contacts and reconnects from neutral. No queue of historical frames is
maintained. Pings are never input keepalives.

A watchdog epoch reset clears both inputs and motion. The acknowledgement must
have **neutral buttons/axes and no motion**. Merely copying the new epoch with an
active sensor sample cannot acknowledge a reset. The phone cancels all contacts
and waits for its neutral send to complete before accepting new contacts. An
older completion cannot reopen a newer input generation. Disconnect, host
release, editing, background, screen rotation, and geometry changes all clear
contacts; sensors stop on interruption and restart only after neutral recovery.
The final network release is best effort; server disconnect/watchdog cleanup is
the authoritative fallback. A normal stationary hold has no maximum duration.

## Units, axes and calibration

The screen-frame mapping below remains unchanged for Full controller mode. Native
standalone Joy-Con modes additionally transform screen vectors into their logical
upright hardware frame; see [JOYCON_SETUP.md](JOYCON_SETUP.md#motion-coordinate-contract).
This does not change the wire version or DSU server.


Core Motion `rotationRate` is angular velocity, never Euler attitude angles.
The phone sums `userAcceleration + gravity` and subtracts a calibrated rotation
rate bias. It then rotates both vectors from Apple's fixed device axes into a
right-handed screen frame: **X right, Y toward screen top, Z out of the glass**.
These transforms use `UIInterfaceOrientation`, including 180° landscape changes:

| Interface orientation | Screen vector from device `(x,y,z)` |
| --- | --- |
| Portrait | `(x,y,z)` |
| Portrait upside down (mapping supported; UI currently iPhone portrait only) | `(-x,-y,z)` |
| Landscape left (Home edge left, camera edge right) | `(y,-x,z)` |
| Landscape right (Home edge right, camera edge left) | `(-y,x,z)` |

These are interface orientations, whose landscape names are opposite to
`UIDeviceOrientation`; see [Apple landscape-left definition](https://developer.apple.com/documentation/uikit/uiinterfaceorientation/landscapeleft).

DSU acceleration fields X/Y/Z receive that screen vector in g. DSU gyro fields
pitch/yaw/roll receive the corresponding screen X/Y/Z angular velocities, after
multiplication by `180/π` and user sensitivity (0.25–3×). A phone lying flat,
screen up, is approximately `(0,0,-1)` g. Positive rates follow the right-hand
rule around the listed screen axes. The mapping is covered by numerical basis
and conversion tests; physical directional aiming must still be checked in Eden.

Calibration collects 60 stationary samples (about one second), requiring each
rotation component <0.15 rad/s and user acceleration magnitude <0.08 g. Movement
restarts the collection. Only gyro bias is removed; gravity is retained.
Calibration is session-local and stops on interruption. “Recenter” here resets
rate bias; it does not send absolute aim or reset an emulator game's camera.
Use the game's/Eden's recenter control for absolute aim. Sensitivity affects gyro,
not acceleration. There is one physical motion source per phone, not a pair of
independently moving Joy-Cons.

The implementation follows Apple's [processed device motion API](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data).
DSU units/layouts follow the [Cemuhook protocol reference](https://v1993.github.io/cemuhook-protocol/)
and were cross-checked against [Eden's protocol structs](https://github.com/eden-emulator/mirror/blob/master/src/input_common/helpers/udp_protocol.h).
Eden's [UDP consumer](https://github.com/eden-emulator/mirror/blob/master/src/input_common/drivers/udp_client.cpp)
currently remaps acceleration to `(x,-z,y)` and gyro to `(pitch,roll,-yaw)/312`.
The bridge sends the protocol's degrees/second instead of silently baking that
emulator-specific scale into the transport. Tune sensitivity in the app/Eden
if needed and record the tested emulator version.

## DSU implementation

`motion.py` runs on the existing aiohttp event loop and owns one UDP transport.
It starts/stops with the desktop server, including preview mode; no child server
or background process is created. All integers/floats are little-endian.

- Magic `DSUC` requests / `DSUS` responses; protocol 1001; payload length excludes
  the 16-byte header but includes the 4-byte message type.
- CRC32 covers the whole declared packet with bytes 8–11 zeroed. Short/bad
  headers, oversized requests, unsupported newer versions and bad CRCs are
  dropped. Trailing bytes beyond the declared length are ignored.
- Version (`0x100000`), port info (`0x100001`), and subscriptions (`0x100002`)
  support all/slot/MAC selection, independent renewals, five-second expiration,
  and a bounded maximum of 128 endpoint/client/slot registrations.
- Metadata uses slot IDs 0–3, full-gyro model when fresh, and a locally
  administered pseudo-MAC derived from the installation UUID. DSU has no Wi-Fi
  connection enum; the wireless/Bluetooth value 2 is used. Battery is unknown.
- 100-byte data packets contain neutral DSU buttons, neutral sticks (128),
  inactive touches, per-slot wrapping 32-bit packet counters, 64-bit microsecond
  timestamps at offset 68, acceleration at 76 and gyro at 88. Use XInput for
  game buttons/sticks; DSU is the motion source only.
- Subscribers receive at up to 60 Hz. Fresh sample timestamps use the server's
  monotonic receipt clock, remain unchanged for repeated samples, and do not
  move backward when a phone reconnects. Source sequence/timestamp are used for
  replay protection, never trusted as a server clock.
- After 250 ms without a fresh sample, or immediately after release/disconnect,
  packets carry zero gyro and resting `(0,0,-1)` acceleration with inactive
  metadata. Advancing neutral packets continue until subscriptions expire;
  this also neutralizes consumers that ignore the connected flag. Shutdown
  sends final best-effort neutral packets before closing UDP.

`pong.motionSubscribers` reports the number of live DSU subscriptions for that
player. “DSU client subscribed” confirms transport demand only, **not** that Eden
has bound motion correctly or that physical aiming feels right.

## Eden and Windows acceptance

1. Rebuild the Windows EXE from this branch; the previous EXE has no bridge.
2. Enable the player's normal XInput device for buttons/sticks in Eden.
3. In Eden's motion/UDP server configuration, enable a Cemuhook/DSU server at
   **127.0.0.1, port 26760** (or the configured port). Labels vary by Eden build.
4. Enable Motion in the iPhone's Settings panel, calibrate while still, then bind
   that player's motion input to the matching DSU pad (P1=0, P2=1, P3=2, P4=3).
   Move only the intended phone while binding. Do not replace XInput buttons
   with this motion-only device.
5. Verify all three axes in portrait and both landscapes, stationary drift,
   sensitivity, a real game's aiming/tilting, and two independently moving
   phones. Background/disconnect one phone; its motion must stop without
   affecting another player. Check EXE close releases XInput and UDP.

See [WINDOWS_REBUILD.md](WINDOWS_REBUILD.md) and [IOS_VALIDATION.md](IOS_VALIDATION.md)
for exact rebuild commands and the boundary between verified and pending work.
