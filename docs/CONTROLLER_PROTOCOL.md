# Current controller wire protocol

This describes the existing `server.py` at the 2026-09-12 handoff, before native iOS/motion work. Source and tests are authoritative. JSON examples use placeholders, not live pairing secrets.

## Pairing and connection

QR URL: `http://<host>:<port>/play#key=<random-launch-token>`. Parse the fragment with a URL parser; the token is not a query parameter. Preserve the scanned host and port and connect to `ws://<host>:<port>/ws`. Treat the QR as untrusted input: validate scheme, host, port, path, and nonempty key; never execute arbitrary content. Do not log tokens or include them in analytics. Rescan after a host restart because the pairing key changes.

The server accepts a missing Origin header for a native client. If an Origin is present, it must equal `http://<request-host>`. Send a JSON text join within five seconds of connecting:

```json
{"type":"join","key":"<QR token>","client":"<persistent installation UUID>","name":"Player's phone"}
```

`client` must be 8–80 characters and unique per phone; persist it across reconnections. Name is truncated to 32 characters. The server currently does not require a type field on the initial join, but send it for clarity.

```json
{"type":"joined","player":1,"epoch":0,"mode":"live"}
```

Player numbers are 1–4. `mode` is `live` or `preview`; preview does not drive Windows controllers. On join, clear all local controls and send a neutral input frame with the supplied epoch.

## Input

Each frame contains the complete current state, not deltas:

```json
{"type":"input","epoch":0,"state":{"buttons":["A","L"],"lx":0.5,"ly":0,"rx":0,"ry":0,"zl":0,"zr":1}}
```

Sticks `lx/ly/rx/ry` are finite numbers clamped to -1..1; positive X is right and positive Y is up. Triggers `zl/zr` are 0..1. Reject non-finite values and booleans locally. Send neutral with empty buttons and all six numeric values zero.

| Wire value | UI / Xbox output |
| --- | --- |
| A, B, X, Y | Matching Xbox face button |
| UP, DOWN, LEFT, RIGHT | D-pad |
| L, R | LB, RB |
| zl, zr numeric fields | LT, RT |
| MINUS, PLUS | Back, Start |
| L3, R3 | Stick clicks |
| HOME | Guide |

`LS` and `RS` are browser UI identifiers, not wire buttons: translate them into the axis fields. `ZL` and `ZR` are UI identifiers translated into the trigger fields. Unknown wire buttons are filtered out. Button arrays have a maximum of 32 entries.

Coalesce movement at approximately 30 Hz (the current browser cadence). Send presses/releases promptly, with input keepalives at least every 200 ms even if unchanged. Bound aggregate messages below 180 per second per client; the server closes clients exceeding that rate. Each WebSocket message is limited to 4096 bytes. Do not allow an unbounded queue of old input frames.

## Timeout and reset generation

After more than 750 ms without accepted input, the server neutralizes the output and increments that player's epoch. On a later invalid-epoch or non-neutral recovery frame it sends:

```json
{"type":"reset","epoch":1}
```

Immediately cancel all active contacts, discard queued states, adopt that epoch, and send a full neutral frame. Only after this acknowledgement may new user contacts produce active input. A current-epoch active frame alone cannot acknowledge a reset. Do not automatically recreate held contacts from before the interruption.

Reset is announced once per epoch; an ignored reset can leave the client unable to send active input until reconnect. Keep all network/state handling serialized to avoid late sends using an old generation. Do not interpret the 750 ms timeout as a maximum time a user may hold a control: healthy keepalives sustain stationary holds.

## Ping and connection lifecycle

```json
{"type":"ping","time":1234.5}
```

Server echoes `{"type":"pong","time":1234.5}`. The existing client sends this every two seconds for latency display. Ping is not an input keepalive and does not prevent the input timeout. The WebSocket transport also has server heartbeat frames; the native client must support normal WebSocket ping/pong handling.

Errors: `{"type":"error","message":"...","fatal":true}`. Show the message and stop automatic retries on fatal errors. Cases include bad pairing key, all four slots occupied, duplicate active device ID, and virtual output failure.

- Close 4003: host released this player. Clear state, stop retries, allow explicit rejoin.
- Close 1008: malformed messages or rate limit. Clear state and show the issue; avoid a retry storm.
- Close 1001: host shutdown. Clear state and reconnect with bounded backoff if appropriate; new launch keys require rescanning.
- On any socket closure, backgrounding, cancellation, or focus interruption, neutralize locally, try to send neutral if connected, and close as needed. Never depend solely on successful delivery of a final frame.
- On network reconnect, join with the same installation ID and clear all input. Ignore late callbacks from obsolete sockets.

A disconnected phone reserves its player number for 15 seconds, but its virtual controller is removed immediately. A new connection with its client ID can reclaim the slot if available. Windows may assign a different XInput device index after reconnection.

## Host-only endpoints and future motion

`/`, `/api/bootstrap`, `/api/status`, `/api/qr`, `/api/stop`, and `/api/players/N/release` are localhost-only admin endpoints. A phone must not try to fetch bootstrap for its key or require an admin token. The phone uses the scanned QR and `/ws` only.

There is no gyro message or haptic command in this protocol yet. Native button haptics can be generated entirely on the phone. Gyro support needs a negotiated extension and a server-side motion bridge; the current Xbox output has no gyro field. See `MAC_HANDOFF.md` for that work.
