# Phone Controller support

Publication draft: add your monitored contact and Windows download link before
publishing this page and using its public HTTPS URL in App Store Connect.

## Get connected

1. Download the Phone Controller Windows companion: **ADD RELEASE DOWNLOAD URL**.
2. Install the required ViGEmBus driver from its
   [official releases](https://github.com/nefarius/ViGEmBus/releases).
3. Open Phone Controller.exe and keep its window open. Put your PC and iPhone on
   the same trusted private Wi-Fi network. Run Enable Wi-Fi access.cmd from the
   Windows companion folder if the firewall blocks connection.
4. In the iPhone app, tap Scan QR, scan the PC's current code, and tap Join game.
   Allow Local Network access. Camera access is optional; you can paste the full
   pairing URL instead. Scanning with the system Camera opens the browser client.

## Troubleshooting

- After restarting the companion, scan the new QR code; the old key expires.
- Check Camera and Local Network permissions in iOS Settings for Phone Controller.
- Avoid guest Wi-Fi/client isolation, which can prevent devices communicating.
- No controller output: check ViGEmBus and your game's input bindings. Preview
  mode does not create a Windows controller.
- No motion: enable it in the iPhone app, calibrate while still, and configure
  the PC game's/emulator's DSU client. A subscriber indicator does not prove that
  a game has the right bindings. Motion is optional.
- Full and standalone left/right modes have independent saved layouts. Reset
  restores only the active layout. The app does not pair directly with consoles.

## Contact

**ADD MONITORED SUPPORT EMAIL OR CONTACT FORM**

Include app version, iOS version, Windows version and a description of the issue.
Do not send pairing QR codes, pairing keys or private logs. If you send screenshots,
remove pairing URLs and personal/network details first.

Publish the privacy policy from `ios/IControl/PrivacyPolicy.txt` alongside this
page and link it here. Keep the published text synchronized with the app.
