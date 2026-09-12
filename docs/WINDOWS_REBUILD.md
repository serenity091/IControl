# Phone Controller — Windows rebuild handoff

**Rebuild required for the rename.** Close any running IControl or Phone Controller
window, then build from the shared **codex/native-ios-motion** branch. The output
is now `dist/Phone Controller.exe`; old `dist/IControl.exe` builds may remain in
an existing checkout but are no longer launched by the renamed Start script.
Remove or archive that old executable manually once the new build is working.
Update desktop shortcuts to the new EXE. The source changes have been prepared
on macOS; a Windows EXE has not been built or validated on this Mac.

The desktop title, dashboard, phone browser, error messages and Setup/Build/Start/
Stop launchers use **Phone Controller**. Keep filenames with spaces quoted.
The icon is now `assets/phone-controller.ico`. PyInstaller's one-file build still
bundles the local website and motion bridge. Run **Enable Wi-Fi access.cmd** if
Windows blocks the new executable. The helper recognizes both new and old EXE
paths and updates the existing rule's display name, retaining its stable internal
name and the previous private-network-only repair scope.

No new wire IDs, ports or motion behavior are required on Windows. The stable
`app: "IControl"` discovery marker and existing browser/iOS storage keys are
preserved; status now additionally reports `displayName: "Phone Controller"`.
Existing iOS clients and older motion-capable EXEs remain protocol-compatible.
The previous Windows fixes, including `ff06a6e`, remain in place. Standalone
Left/Right Joy-Con setup is documented in [JOYCON_SETUP.md](JOYCON_SETUP.md);
no two-phone pairing setup is included.

If the branch has been pushed to origin, on Windows:

```powershell
git fetch origin
git switch codex/native-ios-motion
git pull --ff-only
```

For a local-only branch, push it from the Mac first with
`git push -u origin codex/native-ios-motion`, or transfer the Git bundle supplied
with the handoff and fetch it on Windows:

```powershell
git fetch C:\path\icontrol-ios-motion.bundle codex/native-ios-motion
git switch -c codex/native-ios-motion FETCH_HEAD
```

Close the running EXE before rebuilding. Keep ViGEmBus installed. From the repo:

```powershell
& ".\Setup Phone Controller.cmd"
& ".\Build Phone Controller.cmd"
& ".\dist\Phone Controller.exe"
```

`build_exe.py` imports `desktop.py` → `server.py` → `motion.py`; PyInstaller follows
that normal Python import, so the new bridge is bundled. There are no new Python
runtime dependencies. Regenerate the spec through the build script; never copy
a Mac-generated spec or virtual environment. UDP defaults to loopback 26760;
a conflict disables motion and displays its error while buttons continue working.
You can run `"Phone Controller.exe" --dsu-port 26761` or `--no-motion` when needed.

The user requested no further tests during this handoff. The following checks
are documented for a later Windows release validation; they have not been run
as part of the rename.

With an idle **live** server and no other phones/physical XInput pads, run:

```powershell
.\.venv\Scripts\python.exe tests/check_xinput.py
```

An isolated packaged motion/lifecycle test is also available:

```powershell
.\.venv\Scripts\python.exe tests/check_packaged_motion.py
```

It launches a test-owned preview EXE on temporary ports, streams synthetic motion,
checks DSU output and stale neutralization, and verifies desktop shutdown releases
both sockets. It does not drive Windows controllers or validate real phone gyro.

Then check four independent players across native and browser clients, actual
XInput button/stick output, simultaneous contacts, disconnect/rejoin and host
release. The virtual controller count must return to zero when all phones leave.
Close the EXE and verify its TCP port and UDP port are reusable and controllers
are removed. Restart and rescan because launch pairing tokens change.

For motion, follow [MOTION_PROTOCOL.md](MOTION_PROTOCOL.md): Eden's Cemuhook/DSU
server is `127.0.0.1:26760`, P1–P4 correspond to slots 0–3, and XInput remains the
button/stick source. Enable phone motion, calibrate, then bind motion in Eden.
Test pitch/yaw/roll, portrait/both landscape orientations, stationary drift,
sensitivity and real standalone gameplay with one phone.
Confirm background/screen lock/network loss stop motion. A subscription indicator
or a passing packet test is not a substitute for this emulator check.

Record Windows build, ViGEmBus version, Eden version, game, phone/iOS versions,
axis directions and chosen sensitivity in [IOS_VALIDATION.md](IOS_VALIDATION.md).
Windows packaging, live XInput and actual Eden motion remain Windows-side checks;
Mac preview and simulator results cannot establish those outcomes.

The dependency installer verifies the pinned vgamepad source archive and suppresses
only its setup-time MSI launch before installing it. Upstream 0.1.0 ignores the
old skip-install environment variable. Runtime code is unchanged; ViGEmBus remains
a separate user installation. This also permits unattended GitHub Windows builds.
