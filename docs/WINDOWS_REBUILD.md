# Windows rebuild and Eden handoff

Branch: **codex/native-ios-motion**. Use the final commit reported with this
handoff. Changes to `server.py`, `desktop.py`, `motion.py`, and
`static/dashboard.js` must all reach Windows; the old EXE cannot receive motion.
The checked-in Xcode app is under `ios/` and is built on the Mac.

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
& ".\Setup IControl.cmd"
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
node --test tests/controller.test.cjs
& ".\Build IControl.cmd"
.\dist\IControl.exe
```

`build_exe.py` imports `desktop.py` → `server.py` → `motion.py`; PyInstaller follows
that normal Python import, so the new bridge is bundled. There are no new Python
runtime dependencies. Regenerate the spec through the build script; never copy
a Mac-generated spec or virtual environment. UDP defaults to loopback 26760;
a conflict disables motion and displays its error while buttons continue working.
You can run `IControl.exe --dsu-port 26761` or `--no-motion` when needed.

With an idle **live** server and no other phones/physical XInput pads, run:

```powershell
.\.venv\Scripts\python.exe tests/check_xinput.py
```

Then check four independent players across native and browser clients, actual
XInput button/stick output, simultaneous contacts, disconnect/rejoin and host
release. The virtual controller count must return to zero when all phones leave.
Close the EXE and verify its TCP port and UDP port are reusable and controllers
are removed. Restart and rescan because launch pairing tokens change.

For motion, follow [MOTION_PROTOCOL.md](MOTION_PROTOCOL.md): Eden's Cemuhook/DSU
server is `127.0.0.1:26760`, P1–P4 correspond to slots 0–3, and XInput remains the
button/stick source. Enable phone motion, calibrate, then bind motion in Eden.
Test pitch/yaw/roll, portrait/both landscape orientations, stationary drift,
sensitivity, real gameplay and per-player isolation with two moving phones.
Confirm background/screen lock/network loss stop motion. A subscription indicator
or a passing packet test is not a substitute for this emulator check.

Record Windows build, ViGEmBus version, Eden version, game, phone/iOS versions,
axis directions and chosen sensitivity in [IOS_VALIDATION.md](IOS_VALIDATION.md).
Windows packaging, live XInput and actual Eden motion remain Windows-side checks;
Mac preview and simulator results cannot establish those outcomes.
