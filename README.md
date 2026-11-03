# Tabbit

A native iOS receipt scanner written in SwiftUI. It scans a receipt with the camera, reads the text, and pulls out the merchant, date, line items, subtotal, tax and total. Then it checks that the numbers add up.

- iOS 16 or later, iPhone only
- No third-party dependencies
- **Everything runs on the device.** Scanning, text recognition (Apple's Vision framework) and parsing happen on the iPhone. The app has no networking code.

See [CLAUDE.md](CLAUDE.md) for the roadmap, including Apple Intelligence parsing on iOS 26.

## How it's built

There's no Mac involved. Every push runs `.github/workflows/build.yml` on GitHub Actions, with two jobs in parallel:

- **Build unsigned IPA:**
  1. [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates `Tabbit.xcodeproj` from `project.yml`. The `.xcodeproj` is never committed.
  2. `xcodebuild` builds the app for `iphoneos` in Release with code signing disabled.
  3. The `.app` is zipped as `ReceiptScanner.ipa` and uploaded as a build artifact.
- **Unit tests:** the parsing code's tests run on an iPhone simulator.

To start a run by hand: **Actions → Build → Run workflow**.

## Install on your iPhone (Sideloadly, free Apple ID)

1. Open the latest green run under **Actions → Build** and download the **ReceiptScanner** artifact. GitHub delivers it as a `.zip`; unzip it to get `ReceiptScanner.ipa`.
2. Connect your iPhone to your computer and open [Sideloadly](https://sideloadly.io).
3. Drag `ReceiptScanner.ipa` into Sideloadly, enter your Apple ID, and click **Start**. Sideloadly signs the app with your free Apple ID. Installing over an existing Tabbit keeps its data.
4. The first time, trust the developer profile on the iPhone: **Settings → General → VPN & Device Management**. On iOS 16 and later you also need **Developer Mode**: **Settings → Privacy & Security → Developer Mode**.
5. Open Tabbit, tap **Scan Receipt**, and allow camera access.

Free Apple ID limits:

- Apps expire after **7 days**. Sideload the app again to renew it.
- At most 3 sideloaded apps at once, and 10 new app IDs per week. Re-installing Tabbit with the same bundle ID doesn't use a new one.
- Bundle IDs are unique across every Apple developer account. If Sideloadly fails with `(9401) … Identifier '…' is not available`, someone else already registered that ID. Change `APP_BUNDLE_ID` in `project.yml` to something else unique (for example `com.yourname.tabbit`), push, and sideload the new build.

## Using the app

- **Receipt / Raw text:** switch between the parsed receipt and the plain recognized text.
- **Checks:** a green check means the items add up to the subtotal, or subtotal + tax matches the total. An orange warning means something was misread or missed.
- **Export:** shares a JSON file with the recognized text and positions (no image) plus what the parser found. These files are how the parser gets better: they become unit-test fixtures in `TabbitTests/Fixtures/`. The repo is public, so remove anything private (card digits, address) before committing one.

## Changing the app name or bundle ID

Both live in one place: the top-level `settings` block in `project.yml`.

```yaml
APP_BUNDLE_ID: com.eightbitbyte.tabbit
APP_DISPLAY_NAME: Tabbit
```

The app target, the test target and the Info.plist read these values, so the home-screen name and the camera permission text follow automatically.
