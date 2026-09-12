# Phone Controller — iOS App Store preparation

Prepared on September 12, 2026. This is a release handoff, not a statement that
Apple has accepted the app or that it has been uploaded. No further tests were
run, as requested. See [IOS_VALIDATION.md](IOS_VALIDATION.md) for earlier results
and unverified device/gameplay behavior. Windows packaging must be rebuilt for
the new name; see [WINDOWS_REBUILD.md](WINDOWS_REBUILD.md).

## Prepared in this checkout

- Display name, in-app title, permission prompts and built product:
  **Phone Controller** / `Phone Controller.app`.
- Version **1.0**, build **2**, controlled by `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION`; choose a fresh build number for every upload.
- iPhone only, iOS 17 minimum, portrait and both landscape orientations. Existing
  opaque 1024 × 1024 app icon is retained. No iPad support is advertised.
- Bundled `PrivacyInfo.xcprivacy`: app-owned preferences (`CA92.1`) and elapsed
  time/timers (`35F9.1`), no tracking and no developer data collection.
  Native pings no longer send system uptime; motion sends time elapsed since the
  first usable sensor sample, preserving sequence/order across mode changes.
- Settings → About Phone Controller → Privacy policy works offline. Setup and
  support explains Windows/driver requirements. Optional public links are read
  from build settings so a release can point to the owner's actual URLs.
- Release builds disable Swift testability, retain dSYM symbols, and include an
  archive script and App Store Connect export configuration.
- `ITSAppUsesNonExemptEncryption = NO`: this build has no custom encryption; LAN
  transport is HTTP/WebSocket and public links use system HTTPS. Reassess if
  encryption libraries or transport behavior change.

The Xcode project/scheme/module names remain **IControl**. This is intentional:
these internal names are not the App Store name. Keep the installed bundle ID
when upgrading an existing app to retain its data. Do not rename UserDefaults or
browser storage keys. The owner confirmed the App Store Connect bundle ID is **`com.jakejin.IControl`**;
that exact case-sensitive spelling is now the shared project default. The previous
local development install used `com.jakejin.icontrol.companion`, so the registered
store app is a separate installation and will not inherit that app's saved layouts.
The existing development app is not removed by this rename.


## Local archive/export result

The Release archive and local App Store distribution export both succeeded with
bundle ID **`com.jakejin.IControl`**, version **1.0 (2)** and the iOS 26.0 SDK.
The archive contains the privacy manifest and offline privacy policy. The
1024 × 1024 icon has no alpha channel. Changed Python source and the archive
shell script passed syntax inspection; no test suites or device interactions ran.

Local artifacts (not committed):

- `build/ios-app-store/Phone Controller.xcarchive`
- `build/ios-app-store/Phone Controller.ipa`

These are preparation artifacts. Public support/privacy URLs have not yet been
provided, so their optional in-app links are absent. Re-archive with the actual
URLs before submission. Xcode emitted an expired-session warning for one saved
account but completed the local export; reauthenticate in Xcode Settings →
Accounts if Organizer asks at upload time. No upload or server-side App Store
validation has been performed.

## Owner details still needed before upload

1. The owner confirmed an App Store Connect record and bundle ID
   **`com.jakejin.IControl`**. Confirm the signing team has distribution access to
   that record. A Personal Team device install is not App Store signing.
2. Publish the [privacy policy text](../ios/IControl/PrivacyPolicy.txt) at a stable,
   publicly accessible HTTPS URL. Publish the [support draft](app-store/SUPPORT.md)
   with a real monitored contact and a working Windows companion download.
   Add the publisher identity/contact to the public policy and synchronize the
   bundled policy if those details change. No placeholder URLs are shipped.
3. Complete [store metadata and reviewer notes](app-store/METADATA.md), copyright,
   price/availability, current age-rating questionnaire, app privacy answers and
   applicable account agreements/business details in App Store Connect.
4. Capture actual release UI screenshots with no pairing keys or private network
   addresses visible. Include Full controller, standalone left/right modes and
   layout editing. Use a supported 6.9-inch iPhone screenshot size, such as
   **1320 × 2868** portrait or **2868 × 1320** landscape. Supply 1–10 per supported
   screenshot set. No new screenshots were captured under the no-tests request.
5. Make the Windows EXE/driver setup available to App Review and provide precise
   instructions plus a demonstration recording if needed. The app requires a PC
   for live input; offline layout editing alone does not exercise every feature.
6. Before a public release, arrange the remaining physical/Windows acceptance
   checks from IOS_VALIDATION.md. Their absence is not a claim of release quality.

## Archive for distribution

This Mac has Xcode 26.0.1 with the iOS 26 SDK. Apple's minimum upload requirement
as of this preparation is iOS 26 SDK or later. Verify current requirements again
at upload time. iOS 17 remains the deployment target, independent of the build SDK.

From the repository root, set your actual release values locally:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPMENT_TEAM=YOUR_PAID_TEAM_ID
export ICONTROL_BUNDLE_ID=com.jakejin.IControl
export BUILD_NUMBER=YOUR_UNUSED_BUILD_NUMBER
export PHONE_CONTROLLER_PRIVACY_URL=https://YOUR_DOMAIN/privacy
export PHONE_CONTROLLER_SUPPORT_URL=https://YOUR_DOMAIN/support
./ios/archive.sh
```

The script requires those fields, archives only, and never runs tests or uploads.
Use real URLs; the example values above are not release-ready. It writes
`build/Phone Controller.xcarchive` (ignored by Git). `ARCHIVE_PATH` and
`MARKETING_VERSION` can override the defaults. No signing identity or team is
checked into the project. Keep signing files, archives and IPA exports out of Git.

Open the archive in Xcode Organizer. With the correct paid team, use **Distribute
App → App Store Connect**, inspect the signing/privacy report and validate the
archive. Alternatively, export an IPA locally using:

```sh
xcodebuild -exportArchive \
  -archivePath 'build/Phone Controller.xcarchive' \
  -exportPath build/app-store-export \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates
```

`ExportOptions.plist` uses `app-store-connect` with `destination=export`: exporting
does not upload or publish. An App Store distribution profile/certificate and
correct team are required; successful development signing alone does not prove
export will work. Upload the reviewed build with Organizer or Transporter when
ready, select it in App Store Connect, and use TestFlight before public review.
No upload, TestFlight release or App Review submission was performed here.

## Privacy answers and sources

For the checked-in app, the proposed App Privacy answer is **Data Not Collected**:
there are no developer/partner servers or analytics SDKs receiving app sessions.
Local data goes to the computer the user selects, and the app stores settings on
the phone. This is a source-based assessment, not an App Store Connect submission.
Reassess website support processing, diagnostics, SDKs and hosting practices before
confirming answers. Do not claim that no data ever leaves the phone; controller
inputs, optional motion, a player name and an installation UUID do leave it.

Apple references checked for this handoff:

- [SDK minimum requirements](https://developer.apple.com/news/?id=ueeok6yw).
- [Required reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).
- [App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
  including review access/resources and privacy policy requirements.
