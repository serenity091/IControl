# App Store Connect metadata

Name: **Phone Controller**

Registered bundle ID (owner confirmed): **`com.jakejin.IControl`**

Subtitle: **Wireless Gamepad for Windows**

Primary category: **Utilities**.

Price: **Free** (owner confirmed).

Keywords (under 100 characters):
`gamepad,wireless,pc,remote,joystick,motion,gyro,wifi,multiplayer,controller`

Promotional text:
> Turn your iPhone into a customizable wireless gamepad for your Windows PC, with optional motion controls and local haptic feedback.

## Description

Turn your iPhone into a wireless gamepad for a Windows PC on the same Wi-Fi network.

Phone Controller requires the Phone Controller Windows companion and the
ViGEmBus virtual controller driver on your PC. Install them before playing.
This app does not connect directly to a game console and does not include games.

CUSTOMIZE YOUR CONTROLS
Use a full two-stick controller or left- or right-hand single-stick layouts.
Move and resize buttons, with separate saved layouts for portrait, landscape and
upright or sideways holding. Use independent touches for sticks and buttons.

ADD MOTION AND TOUCH FEEDBACK
Enable optional gyroscope and accelerometer controls for compatible PC software
through the companion's DSU motion bridge. Adjust sensitivity and calibrate while
still. Optional iPhone haptics provide feedback for button presses and stick
movement. Motion support depends on the game or emulator and its configuration.

CONNECT ON YOUR LOCAL NETWORK
Scan the QR code in the Windows companion using the in-app scanner, or paste the
pairing URL. Keep the companion open while playing. Up to four phones can connect
as independent controllers. One phone supplies one motion source.

No app account, ads or analytics. Use a trusted private network: local controller
traffic is unencrypted. See the privacy policy for the data sent to your computer.

Compatibility: iPhone with iOS 17 or later; Windows PC with the companion and
ViGEmBus installed; both devices on the same local network. Games must support
compatible controller input. Motion requires a compatible DSU client. Standalone
left/right layouts require manual game or emulator bindings. Haptic feedback
depends on device hardware.

Phone Controller is an independent app and is not affiliated with Nintendo or
Microsoft. Joy-Con and Xbox names describe control compatibility. The app does
not provide IR, NFC, Nintendo HD rumble or absolute positional tracking.

## Reviewer setup reference

No login or subscription is required. Live controls require a Windows PC on the
same trusted local network. Companion download and setup resources:

- Windows companion download: https://github.com/serenity091/IControl/releases/tag/windows-v1.0.0-rc.1
- Setup/support URL: https://serenity091.github.io/IControl/support/ (GitHub Issues support)

Install the companion and ViGEmBus, allow private-network access and keep the
companion running. On the iPhone, tap Scan QR and scan the companion's current
code, allow Local Network, then tap Join game. QR keys are generated per server
launch: a screenshot of a developer's old QR is not a usable reviewer connection.

Tap Edit layout to inspect/customize controls without a PC. Choose Full, Left or
Right in the Controller menu. Left/Right have Upright and Sideways layouts; they
are standalone modes with no two-phone pair setup. To inspect motion, configure
a compatible PC DSU client at 127.0.0.1:26760, enable Motion in iOS settings, and
calibrate while still. Settings also contains support and the offline privacy
policy. Camera permission is optional because pairing URLs may be pasted.

## Submission fields

Public privacy URL: https://serenity091.github.io/IControl/privacy/

Copyright: 2026 Jake Jin. Reviewer contact details were supplied privately and
are entered only in App Store Connect. Age rating 4+, Data Not Collected privacy
declaration, free pricing, worldwide availability and build 1.0 (3) are saved.
The version is in a Ready to Submit draft with manual release selected.
See ../APP_STORE_RELEASE.md for the remaining owner decisions.
