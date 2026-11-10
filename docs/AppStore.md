# App Store listing (draft)

Everything below is ready to paste into App Store Connect. Fields with a character limit list it in brackets.

## Identity

- **Name** [30]: Tabbit: Split Receipts
- **Subtitle** [30]: Scan, split and settle up
- **Bundle ID:** `com.eightbitbyte.tabbit` (set in `project.yml`)
- **Version:** 1.0.0 (build 5)
- **Category:** Finance (primary), Utilities (secondary)
- **Age rating:** 4+ (no objectionable content)
- **Price:** free (no in-app purchases)

## Promotional text [170]

Scan a receipt, tap who had what, and Tabbit works out who owes whom, down to the cent. Everything stays on your iPhone.

## Description [4000]

Tabbit makes splitting the bill painless.

Scan a receipt with your camera or pick a photo, and Tabbit reads the merchant, date, items, tax, tip and total, right on your iPhone. Tap each item to say who had it. Tax and tip are shared fairly in proportion to what everyone ordered, and every share adds up exactly to the cent.

GROUPS FOR EVERYTHING
Make a group for a trip, a dinner, an event or your home. Add the people you're with, and keep every receipt in one place with the total spent and what you're owed or owe.

SETTLE UP IN AS FEW PAYMENTS AS POSSIBLE
Tabbit turns a pile of receipts into the shortest list of payments that makes everyone even. Tap a payment to see the receipts and items behind it, swipe it when it's paid, and send the summary to your friends in any messaging app.

YOUR OWN RECEIPTS, TOO
Keep personal receipts in My Receipts. Search by merchant, item, date or amount, and sort them any way you like.

SEE WHERE YOUR MONEY GOES
Your profile shows this month's spending compared with last month, a breakdown by category, and the last six months at a glance.

PRIVATE BY DESIGN
• Scanning, reading and splitting happen on your iPhone, with no account and no servers.
• Receipts and photos are stored only on your iPhone, encrypted while it's locked.
• Nothing leaves your phone unless you share or export it.

MADE TO FEEL GOOD
A calm, tactile design in light and dark mode, with haptics, smooth animations, Dynamic Type and VoiceOver support.

Export everything as CSV whenever you like.

## Keywords [100]

split,bill,receipt,scanner,splitwise,expenses,group,trip,friends,settle,tip,calculator,share,owe

(Check that "splitwise" is acceptable before submitting; competitor names in keywords can be rejected. A safe swap is "roommates".)

## What's New in this version [4000]

Tabbit 1.0: split with friends.
• Groups for trips, events and home, with everyone you share costs with.
• Assign each item to the people who had it. Tax and tip follow along.
• Settle Up shows the fewest payments to make everyone even.
• See where your money goes on your profile.
• A calmer look, in light and dark.

## App Privacy ("nutrition label")

- **Data collection:** "We do not collect data from this app." Nothing is sent to the developer or anyone else; there is no analytics and no account.
- **The map (opt-in, v1.2):** when the person turns it on, Apple Maps (MapKit) receives each receipt's store name and printed address to find it, and loads the map. That's Apple's own service, not data the developer collects, so the label should still be "no data collected". Check Apple's current guidance on MapKit before submitting, and mention the map in the privacy policy.
- **Tracking:** none.
- The bundled privacy manifest (`Tabbit/Resources/PrivacyInfo.xcprivacy`) matches: no tracking, no collected data, and two required-reason APIs: UserDefaults (CA92.1, the app's own settings) and disk space (85F4.1, shown in Settings).

## Review notes

- No login is needed. To try splitting: Groups → + → name the group and add a person → open it → + → Type (or Scan) → add items and tap the people who shared them → Save → Settle Up.
- Camera access is used only for scanning receipts. Photo library access is add-only, for "Save to Photos".
- Export compliance: the app uses no encryption beyond what iOS provides (`ITSAppUsesNonExemptEncryption` = NO in the Info.plist).

## Screenshots needed

App Store Connect needs at least one set at 6.9" (1320 × 2868, iPhone 16 Pro Max / 17 Pro Max class); smaller sizes are scaled from it. Suggested order:

1. Groups list (light): "Split receipts with anyone"
2. Receipt with "Who owes what" open: "Everyone pays for what they had"
3. Settle Up: "The fewest payments to get even"
4. Receipt editor after a scan, showing sparkle marks: "Scan it. It fills itself in."
5. Profile charts: "See where your money goes"
6. Groups list (dark): "Easy on the eyes, day and night"

The CI demo screenshots (`ci-screenshots` branch) show the layouts, but they come from a smaller simulator. Take the final ones on a 6.9" simulator or device.

## Before submitting

1. **Apple Developer Program** membership (paid, yearly). Sideloadly with a free Apple ID can't upload to App Store Connect.
2. **Signing in CI:** add a distribution certificate and an App Store provisioning profile as GitHub secrets, then add a release job that archives with signing on and uploads with `xcrun altool` or the App Store Connect API (an API key as a secret). No Mac is needed for this, but it can't use the unsigned IPA.
3. **App Store Connect record:** create the app with the bundle ID above, then fill in this listing.
4. **URLs:** a support URL and a privacy policy URL are required. A simple GitHub Pages page saying "Tabbit collects no data; everything stays on your device" covers the policy.
5. **TestFlight first:** install the TestFlight build on the iPhone and run through the review notes above.
6. Bump `CURRENT_PROJECT_VERSION` in `project.yml` for every upload; bump `MARKETING_VERSION` for every release.
