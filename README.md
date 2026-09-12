# IControl

**Next iOS feature:** [Joy-Con implementation task](docs/JOYCON_TASK.md) and
[Mac handoff](docs/JOYCON_HANDOFF.md). These describe requested work; Joy-Con mode
has not been implemented yet.

Local phone controllers for Windows and Eden. The desktop app displays a QR code; up to four phones join over Wi-Fi and become virtual Xbox controllers.

## Native iPhone app

The Swift/SwiftUI companion is implemented under [ios/](ios/README.md), with QR/manual pairing, independent touches, saved layouts, adjustable native button/joystick haptics, and optional Core Motion. The Python server now includes a loopback DSU/Cemuhook motion bridge for Eden. Rebuild the Windows EXE to use it; existing browser clients remain compatible. See [motion setup](docs/MOTION_PROTOCOL.md), [build and validation results](docs/IOS_VALIDATION.md), and the [Windows rebuild handoff](docs/WINDOWS_REBUILD.md). Actual Eden gameplay still needs Windows validation.

## Open and play

Double-click **dist/IControl.exe**. This is a standalone Windows application: Python and the website are bundled inside the EXE. No console or separate browser window is needed. The native window starts the local server and shows a QR code.

1. Keep the IControl window open.
2. Connect your phone to the same Wi-Fi as the PC and scan the QR code.
3. Enter a name and tap **Join game**. A virtual Xbox controller appears in Windows for each connected phone.
4. In Eden, enable the player, choose Pro Controller, and select that phone's Xbox / XInput device. Bind buttons and save your profile.

**Close the IControl window to stop the server and remove all its controllers.** Minimizing keeps it running. The optional browser dashboard does not own the server; closing a browser tab does not stop the desktop app. Opening a second app while the first is running displays a port-in-use error and leaves the first app alone.

The executable is at `dist/IControl.exe` after building; generated EXEs are not included in the source repository. You can move that single file elsewhere. The shared **ViGEmBus driver** is still required on each Windows PC; install it from [the official releases](https://github.com/nefarius/ViGEmBus/releases) first. The executable does not silently install a driver.

## Players

There are **zero virtual controllers while idle**. Joining adds one; disconnecting removes it. The desktop and browser dashboards show players as they join. The maximum remains **4 simultaneous players**, matching the standard [XInput limit](https://learn.microsoft.com/en-us/windows/win32/xinput/getting-started-with-xinput).

A disconnected phone reserves its player number for 15 seconds for reconnection, but its virtual device is removed immediately. Other phones keep their player numbers. Use **Release** to free a reserved slot immediately. Windows can reassign XInput device indices when controllers reconnect; check Eden's selected device after reconnecting. Other physical XInput devices also occupy Windows' four device slots.

## Classic controller

The phone uses a gray body, black sticks/D-pad, and the Xbox button arrangement:

| Button | Position | Color | Windows output |
| --- | --- | --- | --- |
| A | Bottom | Green | Xbox A |
| B | Right | Red | Xbox B |
| X | Left | Blue | Xbox X |
| Y | Top | Yellow | Xbox Y |

LB/RB are shoulders, LT/RT are triggers, minus/plus are Back/Start, and L3/R3 click the sticks. Home sends Guide. **This replaces the previous Nintendo face-button mapping**, so rebind your Eden profile if you configured it for the earlier version. Eden's [controller guide](https://github.com/eden-emulator/mirror/blob/master/docs/user/Controllers.md) has more configuration details.

Tap **Edit layout**, drag a control, and adjust its size. Tap empty space to resize all controls. **Done** saves changes; **Reset** restores the classic defaults. Portrait and landscape layouts save separately in each phone browser. The new Xbox layout has its own saved-layout version; earlier layout data is retained but not automatically applied.

Multi-touch supports sticks and buttons together. Input is released on disconnect, when the page is hidden, and when editing. The server also clears stale input after 750 ms, rejects queued input from before the timeout, and requires the phone to acknowledge neutral before resuming. The phone independently checks global pointer releases, native touch contacts, capture ownership, and browser suspension. After an interruption, lift and touch the controls again; normal stationary holds are not timed out. The browser has no gyro or native haptics; optional motion and tactile feedback are available in the native iPhone app. NFC, capture and game-driven rumble are not implemented. Full screen and wake lock depend on phone/browser support; some browsers restrict them on local HTTP.

The phone controller blocks double-tap and pinch zoom while preserving simultaneous stick/button touches. Text fields use a mobile-friendly font size to avoid focus zoom.

## Network

The server listens on TCP 8080. If phones cannot connect, **Enable Wi-Fi access.cmd** requests administrator approval for a private-network, local-subnet firewall rule. Keep `enable-wifi.ps1` beside that launcher; Python is not required for this firewall helper. Use the PC's Wi-Fi address in the address selector. Guest-network isolation or VPNs may prevent local connections.

If the iOS app repeatedly reports “Network stalled” on Windows while it connects to a Mac preview server, run **Enable Wi-Fi access.cmd** again. Dismissing the Windows firewall prompt can create an explicit EXE block that overrides the port allowance. The helper repairs generated private-network TCP blocks for `IControl.exe` in its own folder or `dist/`; public-network blocks remain intact. Scan this Windows server's QR inside the iOS app. A phone cannot access the localhost-only host dashboard; `/play` is the phone page.

Everything works locally after installation, without accounts or internet assets. Pairing links have a random secret regenerated on each launch. HTTP traffic is unencrypted; use a trusted local network and do not forward the port to the internet. Host controls are restricted to localhost.

## Build and development

Python 3.12 is used for development. Run **Setup IControl.cmd** to install dependencies, then **Build IControl.cmd** to produce the EXE with PyInstaller. Packaging follows [PyInstaller's bundled resource rules](https://www.pyinstaller.org/en/stable/runtime-information.html).

```powershell
.\.venv\Scripts\python.exe desktop.py
.\.venv\Scripts\python.exe desktop.py --simulate --port 8081
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
node --test tests/controller.test.cjs
.\.venv\Scripts\python.exe tests/check_xinput.py
```

The last check requires a running live server with no connected phones or physical XInput devices; it briefly presses test buttons. It verifies Windows controller creation, input delivery, and removal. Do not run it during a game. `server.py` remains available for developers who explicitly want a server without a desktop window.

The desktop runs aiohttp in a managed thread inside the same process. Window close requests graceful shutdown, closes phone connections, removes gamepads, and waits for the server thread before exiting. No background server is left behind.
