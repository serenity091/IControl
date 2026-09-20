# Paste into Codex on the Mac

Implement native iOS Joy-Con mode in this existing IControl app. First fetch the
shared `codex/native-ios-motion` branch and fast-forward safely, preserving any
local work. Read `docs/JOYCON_HANDOFF.md` and the protocol/validation documents it
references. Keep all recent Windows fixes, including commit `ff06a6e`.

Keep Full controller mode and add Left Joy-Con and Right Joy-Con modes, each with
upright and sideways layouts, independent saved button position/size editing,
proper Nintendo labels, optional native haptics and correctly transformed motion.
Use the existing simple classic design. Preserve full-controller layouts and
behavior. Implement real distinct SL/SR outputs using the documented transport
mapping; unknown wire button names are currently discarded by the server.

One phone is one independent motion source. Support standalone single Joy-Con
use and document/test using two phones as separate left/right sources for an Eden
Joy-Con Pair where Eden permits it. Keep the four-phone total limit. Do not claim
that one phone reproduces two independently moving Joy-Cons or that gyro adds IR,
NFC, HD rumble or absolute positional tracking.

Use the existing input gate to neutralize all input and motion when switching
mode/holding layout. Preserve multi-touch, reconnect/epoch protections, background
release, bounded sends and haptic settings. Build and test on the Mac and physical
iPhone when available. Follow the acceptance checklist in the handoff, document
what could not be physically verified, and write `docs/JOYCON_SETUP.md` with the
exact iPhone/Eden configuration and mapping tables. Commit and push the result to
the shared branch, with a Windows rebuild handoff if any server changes are needed.
