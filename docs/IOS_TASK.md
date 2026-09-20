# Paste this task into Codex on the Mac

This original app task has been implemented. For the next requested feature, use
[JOYCON_TASK.md](JOYCON_TASK.md) and [JOYCON_HANDOFF.md](JOYCON_HANDOFF.md).

Build a native iPhone companion app for this IControl project. First read docs/MAC_HANDOFF.md, docs/CONTROLLER_PROTOCOL.md, README.md, server.py, and static/controller.js. The handoff documents distinguish existing features from work still required.

Create a buildable Swift/SwiftUI iOS app under ios/ that connects to the existing Windows server by scanning its QR code, with a manual pairing URL fallback. Preserve the simple classic gray/black Xbox layout, independent simultaneous touches, editable control positions/sizes, orientation-specific saved layouts, and four independent players across mixed native/browser clients. Add optional native button-press haptic feedback. Preserve all input release, watchdog epoch acknowledgement, backpressure, and reconnection safeguards so sticks/buttons cannot get stuck.

Then add optional Core Motion input and the corresponding backward-compatible Python DSU/Cemuhook motion server for Eden, with capability detection, documented units/axes, calibration, lifecycle cleanup, and per-player isolation. Merely collecting sensor data on the phone does not complete motion support. Keep the current browser client working. Do not change the classic design or add accounts/cloud services.

Inspect the Mac's Xcode and signing setup before selecting the iOS deployment target. Implement and test everything possible locally. Use a physical iPhone for sensor/haptic validation when available; report clearly what needs device testing or Windows/Eden validation. Do not claim physical haptic/gyro quality based on a simulator or mocked tests. Leave the project ready to build in Xcode, with exact signing/install steps and relevant tests. Request user action only for missing Apple signing/device access that cannot be completed locally. Do not commit certificates, provisioning profiles, pairing tokens, or build artifacts.

When server changes are ready, provide the branch/commit (if Git is configured) and a concise Windows rebuild/test handoff. The Windows side must rebuild IControl.exe from those changes and verify actual Eden motion. A source ZIP is also acceptable if no Git remote is configured.
