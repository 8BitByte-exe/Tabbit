# Tabbit

A native iOS app for splitting receipts with friends, written in SwiftUI. Scan a receipt (or pick a photo, or type it in), and Tabbit reads the merchant, date, items, tax, tip and total on the phone. Assign items to the people who had them, and Settle Up shows the fewest payments that make everyone even.

- iOS 17 or later, iPhone only
- No third-party dependencies
- **Everything runs on the device.** Scanning, text recognition (Apple's Vision framework), parsing, splitting and storage happen on the iPhone. The app has no networking code.

See [CLAUDE.md](CLAUDE.md) for the roadmap, including Apple Intelligence parsing on iOS 26, and [docs/AppStore.md](docs/AppStore.md) for the App Store listing draft.

## Features

- **Groups:** a name, a type (trip, event, home, business, personal) and the people in it. Cards show the total, receipt and people counts, and your balance. Search by group or person; swipe a card to edit or delete it.
- **Receipts:**
  - Merchant, date, category, who paid, tax, tip (amount or %), and the total.
  - Line items, each shared by everyone (the default) or by the people you pick.
  - Swipe a receipt to edit it, move it to another group, or delete it. On the receipt screen, swipe sideways for the next one.
  - Photos open full screen: pinch or double-tap to zoom, save to Photos, replace or remove.
- **Scanning:** the camera or a photo fills in the receipt on the phone. Fields it filled in have sparkles; fields it couldn't read have a warning; names it wasn't sure about have a question mark.
- **Splitting:**
  - Each item splits evenly between the people who shared it.
  - With **Share tax & tip** on, tax, tip and any difference from the printed total follow each person's items; off, the payer covers them.
  - Amounts are in whole cents and always add up exactly.
  - Each receipt shows who owes what, with each person's items.
- **Settle Up:**
  - Balances are what you paid minus your share.
  - The largest debtor pays the largest creditor until everyone's even, which keeps the list of payments short.
  - Tap a payment to see the receipts behind it. Swipe it (or tap **Mark Paid**) when it's paid; undo from the history.
  - **Copy** puts a summary on the clipboard; **Send** opens the share sheet (Messages, WhatsApp, …).
- **My Receipts:** your own receipts outside any group. Search by merchant, category, date, amount or item, and sort them.
- **Profile:** this month's spending against last month, a category ring, the last six months, and what you're owed or owe overall.
- **Settings:** light, dark or system appearance; text-recognition option; storage used; CSV export of every receipt; What's New; privacy summary.

## How it's built

There's no Mac involved. Every push runs `.github/workflows/build.yml` on GitHub Actions, with two jobs in parallel:

- **Build unsigned IPA:**
  1. [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates `Tabbit.xcodeproj` from `project.yml`. The `.xcodeproj` is never committed.
  2. `xcodebuild` builds the app for `iphoneos` in Release with code signing disabled.
  3. The `.app` is zipped as `ReceiptScanner.ipa` and uploaded as a build artifact.
- **Unit tests + screenshots:** the logic tests (parsing, splitting, Settle Up, storage, search, stats, CSV, contrast) run on an iPhone simulator. Then the Debug build is launched with sample data and every screen is captured in light and dark mode. The pictures go to the `ci-screenshots` branch.

To start a run by hand: **Actions → Build → Run workflow**.

## Install on your iPhone (Sideloadly, free Apple ID)

1. Open the latest green run under **Actions → Build** and download the **ReceiptScanner** artifact. GitHub delivers it as a `.zip`; unzip it to get `ReceiptScanner.ipa`.
2. Connect your iPhone to your computer and open [Sideloadly](https://sideloadly.io).
3. Drag `ReceiptScanner.ipa` into Sideloadly, enter your Apple ID, and click **Start**. Sideloadly signs the app with your free Apple ID. Installing over an existing Tabbit keeps its data; receipts from version 0.4 move to My Receipts.
4. The first time, trust the developer profile on the iPhone: **Settings → General → VPN & Device Management**. You also need **Developer Mode**: **Settings → Privacy & Security → Developer Mode**.
5. Open Tabbit, make a group, and tap **+** to add a receipt.

Free Apple ID limits:

- Apps expire after **7 days**. Sideload the app again to renew it.
- At most 3 sideloaded apps at once, and 10 new app IDs per week. Re-installing Tabbit with the same bundle ID doesn't use a new one.
- Bundle IDs are unique across every Apple developer account. If Sideloadly fails with `(9401) … Identifier '…' is not available`, someone else already registered that ID. Change `APP_BUNDLE_ID` in `project.yml` to something else unique (for example `com.yourname.tabbit`), push, and sideload the new build.

## Privacy and storage

- **On the iPhone only:** scanning, text recognition, parsing and splitting all run on the phone, and the app has no networking code.
- **Encrypted while locked:** receipts, groups and photos are stored in the app's private storage, encrypted whenever the phone is locked.
- **Not in iCloud Backup:** saved data is left out of backups, so it survives closing the app, restarting the phone and installing updates, but not deleting the app.
- **Leaves the phone only when you share it:** Settle Up summaries, CSV exports, saved photos and scan exports go only where you send them.
- The app includes Apple's privacy manifest (`Tabbit/Resources/PrivacyInfo.xcprivacy`): no tracking and no data collected.

## Design

Soft, matte clay: one light source at the top-left, rounded everything, SF Rounded type, green-grey surfaces, and a mint-sage accent with dark text on it. All tokens live in `Tabbit/Design/Theme.swift` and the shared components in `Tabbit/Design/Components.swift`. CI checks every text color for WCAG AA contrast.

## Changing the app name or bundle ID

Both live in one place: the top-level `settings` block in `project.yml`.

```yaml
APP_BUNDLE_ID: com.eightbitbyte.tabbit
APP_DISPLAY_NAME: Tabbit
```

The app target, the test target and the Info.plist read these values, so the home-screen name and the permission texts follow automatically.
