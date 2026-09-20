# Phone Controller — App Store submission

Prepared September 12, 2026. App Store Connect accepted version **1.0 (3)**
into a draft marked **Item Ready to Submit**. **Submit for Review has not been
clicked.** Release is manual after Apple approval. This is not an approval or
live App Store release.

## Completed

- App record **6811429633**, exact bundle ID **com.jakejin.IControl**.
- Name **Phone Controller**, subtitle **Wireless Gamepad for Windows**, category
  **Utilities**, free pricing, availability configured for all 175 regions on
  release. Apple Silicon Mac and Vision Pro distribution are disabled.
- Windows-focused description, keywords, promotional text, copyright, support
  URL, marketing URL, and reviewer setup instructions saved. Private reviewer
  contact is entered only in App Store Connect, never in these public documents.
- Age rating **4+** with Apple's regional equivalents; no games or third-party
  game content are included. No app sign-in is required.
- Owner-approved **Data Not Collected** privacy declaration published. Local-PC
  data transfer and GitHub support/hosting practices are explained in the policy.
- Four actual Release simulator screenshots uploaded in the 6.9-inch set;
  App Store Connect uses them for the other required iPhone sizes. Order: full
  controller, layout editor, Windows pairing, standalone single-stick layout.
- Signed Release archive, App Store Connect upload, server processing and build
  selection completed with Xcode 26.0.1 / iOS 26 SDK. iOS 17 remains the minimum.
- Windows companion built on GitHub's Windows runner and published as a release
  candidate. No automated test suites or new physical-device tests were run.

## Public links

- [Support and setup](https://serenity091.github.io/IControl/support/)
- [Privacy policy](https://serenity091.github.io/IControl/privacy/)
- [Marketing homepage](https://serenity091.github.io/IControl/)
- [Windows companion release](https://github.com/serenity091/IControl/releases/tag/windows-v1.0.0-rc.1)
- [Windows ZIP](https://github.com/serenity091/IControl/releases/download/windows-v1.0.0-rc.1/Phone-Controller-Windows.zip)

GitHub Pages publishes the root of **codex/github-pages**. Source pages are in
`public/`; regenerate them with `python3 scripts/build_public_site.py`, then
publish the generated files to that Pages branch. The privacy page is generated
from `ios/IControl/PrivacyPolicy.txt`. Support is through GitHub Issues.

## Remaining owner decisions

- The owner confirmed a personal project outside a trade or profession. The
  non-trader declaration is saved, and DSA compliance is **Active**. The Free
  Apps Agreement is active; the unused Paid Apps Agreement is not signed.
- Review the completed draft and explicitly authorize **Submit for Review**.
  The app will still require manual release after approval.
- Windows gameplay, physical motion direction, extended simultaneous touch and
  haptic feel remain unverified in this release round. See
  [IOS_VALIDATION.md](IOS_VALIDATION.md). Screenshots and successful compilation
  do not establish those behaviors.

## Local artifacts

Not committed:

- `build/ios-app-store/Phone Controller.xcarchive`
- `build/ios-app-store/Phone Controller.ipa`
- `build/windows-release/Phone-Controller-Windows.zip`

Committed screenshots: `docs/app-store/screenshots/`, four 1320 × 2868 PNGs from
an iPhone 17 Pro Max simulator running the Release app. The connected screens
show **Preview only**, accurately reflecting the Mac preview host. The pairing
screenshot contains no key or private network address. Images are unaltered UI
captures, not generated marketing mockups.

The Xcode scheme/module remains **IControl**; visible product branding is
**Phone Controller**. Existing protocol markers and preference keys are retained.
The registered bundle ID differs from the older local development app, which is
not removed and does not share saved layouts with this App Store installation.

## Future archive/export

Choose an unused build number for each upload. From the repository root:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPMENT_TEAM=YOUR_PAID_TEAM_ID
export ICONTROL_BUNDLE_ID=com.jakejin.IControl
export BUILD_NUMBER=YOUR_UNUSED_BUILD_NUMBER
export PHONE_CONTROLLER_PRIVACY_URL=https://serenity091.github.io/IControl/privacy/
export PHONE_CONTROLLER_SUPPORT_URL=https://serenity091.github.io/IControl/support/
./ios/archive.sh
```

The archive script never runs tests or uploads. Its default archive is
`build/Phone Controller.xcarchive`; `ARCHIVE_PATH` overrides that location.
Export locally with:

```sh
xcodebuild -exportArchive \
  -archivePath 'build/Phone Controller.xcarchive' \
  -exportPath build/app-store-export \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates
```

The export configuration preserves the chosen build number and uses
`destination=export`; it does not upload. Use Organizer's App Store Connect flow
for a future upload. Keep signing credentials, logs, archives and IPA files out
of Git.

## Privacy and platform details

The bundled privacy manifest declares UserDefaults (`CA92.1`) and elapsed time
APIs (`35F9.1`), with no tracking or developer data collection. The offline policy
is available in Settings. Inputs, optional motion, player name and an installation
UUID go to the user's selected PC; do not claim nothing ever leaves the phone.
LAN traffic uses HTTP/WebSocket. Public links use system HTTPS and
`ITSAppUsesNonExemptEncryption` is `NO`. Reassess these declarations if behavior
or dependencies change. The retained 1024 × 1024 app icon is opaque.

References checked during preparation:

- [Apple SDK requirements](https://developer.apple.com/news/?id=ueeok6yw)
- [App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
