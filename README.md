# Tabbit

A native iOS receipt scanner written in SwiftUI. Right now it scans a receipt with the camera and shows the recognized text. Receipt parsing comes later (see [CLAUDE.md](CLAUDE.md)).

- iOS 16 or later, iPhone only
- No third-party dependencies
- Text recognition runs on the device with Apple's Vision framework

## How it's built

There's no Mac involved. Every build runs on GitHub Actions (`.github/workflows/build.yml`):

1. [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates `Tabbit.xcodeproj` from `project.yml`. The `.xcodeproj` is never committed.
2. `xcodebuild` builds the app for `iphoneos` in Release with code signing disabled.
3. The `.app` goes into `Payload/`, which is zipped as `ReceiptScanner.ipa` and uploaded as a build artifact.

A build runs on every push to any branch. To start one by hand: **Actions → Build → Run workflow**.

## Install on your iPhone (Sideloadly, free Apple ID)

1. Open the latest green run under **Actions → Build** and download the **ReceiptScanner** artifact. GitHub delivers it as a `.zip`; unzip it to get `ReceiptScanner.ipa`.
2. Connect your iPhone to your computer and open [Sideloadly](https://sideloadly.io).
3. Drag `ReceiptScanner.ipa` into Sideloadly, enter your Apple ID, and click **Start**. Sideloadly signs the app with your free Apple ID.
4. The first time, trust the developer profile on the iPhone: **Settings → General → VPN & Device Management**. On iOS 16 and later you also need **Developer Mode**: **Settings → Privacy & Security → Developer Mode**.
5. Open Tabbit, tap **Scan Receipt**, and allow camera access.

Free Apple ID limits:

- Apps expire after **7 days**. Sideload the app again to renew it.
- You can only have a few sideloaded apps at once, and only a limited number of new app IDs per week.
- Bundle IDs are unique across every Apple developer account. If Sideloadly fails with `(9401) … Identifier '…' is not available`, someone else already registered that ID. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to something else unique (for example `com.yourname.tabbit`), push, and sideload the new build.

## Changing the app name or bundle ID

Both live in one place: the identity block at the top of the target settings in `project.yml`.

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.eightbitbyte.tabbit
APP_DISPLAY_NAME: Tabbit
```

The Info.plist (also defined in `project.yml`) reads these values, so the home-screen name and the camera permission text follow automatically.
