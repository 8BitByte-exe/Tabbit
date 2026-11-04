# CLAUDE.md

Notes for working on Tabbit, a native SwiftUI app for scanning and splitting receipts on iOS.

## The main constraint: no Mac, no local builds

The owner has no Mac and no Xcode. **The GitHub Actions macOS runner is the only compiler**, and the only test of the UI is installing the built app on a real iPhone (the owner's iPhone 16 Pro on iOS 26).

- Write simple, conservative Swift. Before every commit, review each changed file for compile errors: exact API signatures, imports, optionals, and API availability on iOS 17.
- After every push, check the **Build** workflow run. It has two jobs, `build` (the IPA) and `test` (unit tests). If either fails, read the job log (GitHub MCP tools: `actions_list` → `list_workflow_runs` / `list_workflow_jobs`, then `get_job_logs`). Search the log for `error:`, `failed`, and `The following build commands failed`. Fix the cause and push again.
- Don't call something done until both jobs are green.
- Don't add steps that need Xcode on a dev machine.

## Privacy rule: everything stays on the device

Scanning, OCR, parsing, splitting and storage must run on the iPhone.

- No networking code: no `URLSession`, no web APIs, no analytics, no third-party SDKs.
- Use only on-device Apple frameworks: VisionKit, Vision, PhotosUI, Photos (save only), Charts, Foundation, and later Foundation Models.
- The only way data leaves the phone is when the user explicitly shares something: Settle Up Copy/Send, CSV export, Save to Photos, Export Scan Data.
- `Tabbit/Resources/PrivacyInfo.xcprivacy` declares no tracking and no collected data, plus the required-reason APIs (UserDefaults CA92.1, disk space 85F4.1). Update it if the app ever touches another required-reason API.

## Build and sideload workflow

1. Push to any branch. `.github/workflows/build.yml` runs on `macos-latest` with its default Xcode. Manual runs use `workflow_dispatch`.
2. **`build` job:** `brew install xcodegen` → `xcodegen generate` → `xcodebuild -scheme Tabbit -configuration Release -sdk iphoneos -destination generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`. The log prints the bundled Info.plist and fails if `PrivacyInfo.xcprivacy` is missing from the bundle. `Tabbit.app` is zipped into `ReceiptScanner.ipa` and uploaded as the `ReceiptScanner` artifact.
3. **`test` job (in parallel):** picks the newest available iPhone simulator and runs `xcodebuild test -scheme Tabbit`.
4. The owner downloads the artifact and sideloads it with **Sideloadly** using a free Apple ID. Sideloadly does the signing, so there are no certificates or provisioning profiles in this repo. Free-account apps expire after 7 days. Keep the bundle ID stable: changing it uses up one of the account's 10 new app IDs per week and installs a separate app.

## Project structure

```
project.yml                  XcodeGen spec: identity, targets, Info.plist, privacy manifest, scheme
.github/workflows/build.yml  CI: build job (unsigned IPA) + test job (unit tests, then design screenshots)
Tabbit/
  TabbitApp.swift            @main App (store, router, flow); RootView: tabs kept alive in a ZStack,
                             ClayTabBar, add/scan/photo/editor presentations, processing/error overlays
  Design/
    Theme.swift              ALL design tokens: palette (light/dark hex), gradients, pastels, radii,
                             spacing, sizes, elevations, fonts (SF Rounded), motion, nav bar,
                             AppearanceSetting, ContrastMath, Haptics
    Components.swift         ClayBackground (.raised/.accent/.inset/.accentInset), InnerEdge,
                             NeumorphicCard/InsetCard, button styles (capsule, icon, card, chip),
                             ClayToggleStyle, ClaySegmentedPicker, ClaySearchField, SectionLabel,
                             AvatarView/Stack, CategoryBadge, StatusChip, EmptyStateView, MoneyText
  Models/
    Person.swift             Person (me has the fixed Person.meID), displayName ("You")
    SplitGroup.swift         a group: name, category, members (me first), settlements
    ReceiptRecord.swift      a saved receipt: SplitItem (assignees, empty = everyone), TipValue ($/%),
                             autofilled/unreadable marks, raw scan + parser output; Settlement
    Categories.swift         GroupCategory, SpendCategory (title, SF Symbol, pastel index)
    Money.swift              formatting and whole-cent conversion
    MoneyInput.swift         parse typed amounts ("1.234,56", "$4", "0.50-")
    Receipt.swift            the parser's Receipt, ReceiptLineItem, CalendarDate; money as text (MoneyCoding)
    ScanResult.swift         RecognizedTextBlock (text, confidence, normalized box, page, alternatives)
    ScanExport.swift         JSON format of Export Scan Data (also the test-fixture format)
  Logic/                     plain Swift, fully unit-tested
    SplitCalculator.swift    per-receipt shares in cents (items, fees by weight, largest remainder)
    SettleUp.swift           balances, greedy fewest transfers, debt details, share text
    ReceiptForm.swift        the editor's state (typed text), validation, assignee toggling, scan marks
    ReceiptSearch.swift      search (merchant, category, items, dates, amounts) and sort orders
    SpendingStats.swift      profile stats: my share by month and category, owed/owe
    CSVExporter.swift        one row per item, RFC 4180 escaping
    ScanAutofill.swift       ProcessedScan → ReceiptRecord with marks; CategoryGuesser
    AppInfo.swift            Changelog (What's New), StorageUsage
  Storage/
    TabbitStore.swift        @MainActor store: Application Support/Receipts/{profile.json, groups.json,
                             <id>/receipt.json, page-N.jpg, thumbnail.jpg}; no iCloud Backup; complete
                             file protection; migrates v0.4 receipts to My Receipts
  Scanning/
    DocumentScannerView.swift  VNDocumentCameraViewController wrapped for SwiftUI
    TextRecognizer.swift       VNRecognizeTextRequest (.accurate, top 3 candidates); RecognitionOptions,
                               OCRSettings (language correction toggle, default off)
    ScanProcessor.swift        OCR → parse → JPEG pages/thumbnail (off the main thread); writeExport(for:)
    ExportRedactor.swift       blanks card/account/phone digits in exports
  Parsing/
    LineGrouper.swift          rebuilds receipt lines from Vision blocks: tilt guesses, grouping,
                               lone prices joined to the nearest name
    ReceiptKeywords.swift      line roles with OCR-tolerant keywords (SJETOTAL → SUBTOTAL, TIP/GRATUITY)
    AmountParser.swift         money amounts at the end of a line
    ReceiptDateParser.swift    purchase date (explicit patterns, not NSDataDetector)
    RulesReceiptParser.swift   the rules-based parser (fallback tier): items, sale/deal lines, tip,
                               inferred subtotal, reconciliation, tilt choice
    ReceiptValidator.swift     arithmetic checks: items = subtotal, subtotal + tax + tip = total
    RegexHelpers.swift         NSRegularExpression helpers (`Patterns.make`)
  Views/
    AppRouter.swift            AppTab, Route, per-tab navigation paths
    ReceiptFlow.swift          @MainActor: source sheet → camera/photos → OCR → editor → save
    Shared/CommonViews.swift   clayRow/clayList (List of clay cards), ScreenHeader, FloatingAddButton,
                               BalanceChip, AmountRow, DateText, toast, ActivityView, claySheet
    Groups/                    GroupsView (list, search, swipe), GroupEditorView, GroupDetailView
                               (+ ReceiptRow, receiptSwipeActions), SettleUpView
    Receipts/                  MyReceiptsView, AddReceiptSheet, ReceiptEditorView, ReceiptPagerView
                               (+ ReceiptDetailPage), MoveReceiptSheet, PhotoViewer (+ ZoomableImageView)
    Profile/                   ProfileView (stats, Swift Charts ring and bars, ProfileEditSheet),
                               SettingsView (+ WhatsNewView)
  Resources/PrivacyInfo.xcprivacy  Apple privacy manifest
  Assets.xcassets            AppIcon (1024 PNG), LaunchBackground (launch screen color)
  Debug/DemoMode.swift       DEBUG only: sample groups/receipts + launch arguments for CI screenshots
Design/AppIcon/              icon artwork source + make_app_icon.py (not part of the build)
docs/AppStore.md             App Store listing draft and submission checklist
TabbitTests/                 XCTest unit tests (run in CI on a simulator)
  Support/TestSupport.swift  money("1.29"), ReceiptLayoutBuilder (fake Vision output), Fixtures loader
  Fixtures/*.json            scan exports used as test fixtures
```

- **The `.xcodeproj` and `Tabbit/Info.plist` are generated and gitignored.** Change `project.yml` instead, and never commit a hand-written `.xcodeproj`.
- Info.plist keys go under `targets.Tabbit.info.properties` in `project.yml`.
- **App identity lives in one place:** `APP_BUNDLE_ID` and `APP_DISPLAY_NAME` in the top-level `settings.base` of `project.yml`. Targets and Info.plist reference them as `$(APP_BUNDLE_ID)` / `$(APP_DISPLAY_NAME)`.
- New Swift files in `Tabbit/` or `TabbitTests/` are picked up automatically by XcodeGen; there's no project file to edit.

## Design system (soft, tactile, clay-like)

The owner cares a lot about design. Every new screen must use the design system.

- **Tokens only.** Colors, radii, spacing, shadows, fonts and motion come from `Theme`. Surfaces come from `Components.swift`: `NeumorphicCard`, `NeumorphicInsetCard`, `clayRaised()`, `clayInset()`, the button styles, and `insetField()`. Don't write `.shadow` or hex colors in views.
- **Matte, lit from the top-left.** Raised surfaces: a subtle diagonal gradient (`surfaceHigh` → `surfaceLow`), a crisp 1pt lit edge, a light shadow at the top-left and a dark one at the bottom-right. No inner gloss on raised surfaces (the owner found it glossy and muddy). Green fills get a green-tinted shadow (`accentShade`), never grey. Inset/pressed surfaces use inner shadows (`InnerEdge`, a blurred stroke that's offset and masked).
- **Shape:** continuous corners everywhere. Cards 28pt, tiles 20pt, fields 18pt, buttons are capsules at least 56pt tall (44pt compact).
- **Color rules:**
  - Mint-sage (`accentHigh` #A8EECB → `accentLow` #6ED6A4) is only a fill, with `onAccent` (dark) text on it.
  - Green text and icons use `accentInk`: #1B6844 in light mode, #8FE5BC in dark mode.
  - Avatars, category badges and charts use `Theme.pastels` with `onPastel` text.
  - Swipe actions use `swipeEdit` / `swipeMove` / `swipeDelete` (iOS draws white on them).
  - Never use pure black or white text.
  - Status (owed/owe/settled, warnings) always comes with an icon and a label.
- **Navigation:** tab roots hide the navigation bar and show `ScreenHeader` + the floating `ClayTabBar`; pushed screens use the system bar and back button, so edge-swipe back works. Lists with swipe actions are `List` + `clayList()` + `clayRow()`. Sheets use `claySheet()`.
- **Accessibility:**
  - Text must reach 4.5:1 on every surface. `ThemeContrastTests` checks this, so add any new color to it.
  - Tap targets are at least 48pt.
  - Pressed and selected states change more than the shadow (inset + scale + color/label).
  - Respect Reduce Motion (no scale animation), Reduce Transparency (no blurred edges, add an outline) and Increase Contrast (outline).
  - Support Dynamic Type: use the text styles in `Theme.Fonts`, and switch the card layout at accessibility sizes.
  - Give every control an accessibility label.
- **Screenshots:** the CI `test` job launches the Debug build with `-TabbitDemo -TabbitScreen <groups|group|receipt|settle|edit|add|mine|profile|settings|whatsnew|processing|empty>` in light and dark mode. It uploads the `design-screenshots` artifact and force-pushes the PNGs to the **`ci-screenshots`** branch. To review them from this container: `git fetch origin ci-screenshots && git show origin/ci-screenshots:groups-light.png > /tmp/groups-light.png`, then open the PNG. Look at them after any UI change.

## Storage

- Everything lives only on the phone in `Application Support/Receipts/`: `profile.json` (me), `groups.json` (groups, members, settlements) and `<uuid>/receipt.json` with its photos. The folder is excluded from iCloud Backup (owner's choice: device-only), and files use `.complete` data protection.
- It survives closing the app, restarting the phone and re-sideloading updates with the same bundle ID. Deleting the app deletes it.
- Receipt files carry `schema: 2`. Files without it are v0.4 `SavedReceipt`s; `TabbitStore` migrates them to My Receipts and rewrites them.
- `ReceiptRecord.parsed` keeps the parser's original output and `scan` the raw OCR, so exports include both `parsed` and the user's `corrected` fields.
- Removing a person from a group (or moving a receipt) resets payers and assignments that no longer fit (`TabbitStore.clean`). People with recorded payments can't be removed.
- Money in JSON is text ("7.76") to avoid floating-point drift. Older numeric files still decode.

## Code rules

- Swift 5 language mode (`SWIFT_VERSION: "5.0"`), deployment target iOS 17.0, iPhone only.
- No third-party dependencies.
- Use only APIs available on iOS 17 (`sensoryFeedback`, `onChange` with two values, Swift Charts sectors, `scrollClipDisabled` are fine). Gate anything newer with `if #available(iOS NN, *)` / `@available`, and with `#if canImport(Module)` when the framework itself is new.
- Regexes: use `NSRegularExpression` via `Patterns.make` with raw strings (`#"..."#`). Don't use Swift `Regex` literals: bare `/.../` literals need a compiler flag in Swift 5 mode.
- Money is `Decimal`, never `Double`; splitting works in whole cents (`Int`) and must always add up exactly. The parser's dates are `CalendarDate`; saved receipts store local midnight as a `Date`.
- No `#Preview` or Xcode-only conveniences; nobody can open the previews.
- Keep UI state on the main actor (`TabbitStore`, `AppRouter`, `ReceiptFlow` are `@MainActor`). Do heavy work like OCR and parsing off the main thread (`ScanProcessor` runs in a detached task).
- Bounding boxes are stored the way Vision returns them: normalized 0–1, with the origin at the **bottom-left** of the page.
- Put parsing logic in plain Swift types that unit tests can cover. CI can only test logic; UI is tested on the phone.
- Lessons from real receipts:
  - Prices often sit up to a line higher or lower than their names (tilt, curl), so never match by height alone.
  - OCR garbles keywords, so match them fuzzily.
  - Sale and regular-price lines aren't purchases.
  - Use the arithmetic (items = subtotal, subtotal + tax = total) to choose between interpretations, and say so in `Receipt.notes` when it changes something.
- **App icon:** `Tabbit/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, a single 1024×1024 opaque PNG that iOS scales and masks.
  - It's generated from the owner's artwork `Design/AppIcon/app-icon-source.jpg` by `python3 Design/AppIcon/make_app_icon.py <source> <output>`. The script crops the tile out of the black mockup, repaints the old rounded corners, and adds a 6% background margin so iOS's mask doesn't clip the bunny's hole.
  - Rerun the script if the artwork changes.
  - If CI ever fails while compiling assets, the runner may be missing a simulator runtime. Try `xcodebuild -downloadPlatform iOS` before the build.

## Test fixtures from real receipts

The app's **Export** button shares a JSON file (`ScanExport`): the raw OCR blocks with positions plus what the parser produced. No images. Drop such a file into `TabbitTests/Fixtures/` and load it with `Fixtures.scan(named:)`. Then assert what the parser should return. The repo is public, so real receipts should be redacted (card digits, addresses) before they're committed.

## Roadmap

The design is tiered and entirely on-device. Each phone gets the best tier it supports, and the rules always run as the fallback and as a sanity check.

| Tier | Requires | OCR | Parsing |
|---|---|---|---|
| 1 | iOS 26 + Apple Intelligence on | Vision `RecognizeDocumentsRequest` | Foundation Models fills a `@Generable` receipt; rules + `ReceiptValidator` verify it |
| 2 | iOS 26 | Vision `RecognizeDocumentsRequest` | Rules, helped by the document reader's rows and detected amounts |
| 3 | iOS 17+ | `VNRecognizeTextRequest` | Rules (`RulesReceiptParser`) |

1. **Done:** scan + raw OCR text.
2. **Done:** Export button, rules parser (tier 3), arithmetic checks, unit tests in CI, "Parsed with" label.
   - **Done:** accuracy pass after the first real-world test (v0.3): tilt handling, fuzzy keywords, sale/deal lines, reconciliation, OCR settings, uncertain-name marks, redacted exports.
   - Next: real exported receipts as fixtures.
3. **Next:** iOS 26 tiers.
   - Vision's document reader.
   - Foundation Models with a `@Generable` receipt type. Guard with `#if canImport(FoundationModels)`, `@available(iOS 26, *)` and `SystemLanguageModel.default.availability`.
   - Validate the model's numbers: the arithmetic checks, and every amount must appear in the OCR text. Fall back to the rules result when they fail.
   - The model can only be tested on the phone; CI runners most likely can't run Apple Intelligence.
4. **Done:** saving with editing (v0.4): design system, saved receipts, editable receipt screen, on-device storage with photos.
5. **Done (v1.0):** splitting.
   - Groups, people, item assignment, tax/tip fees, Settle Up with Mark Paid, My Receipts with search and sort.
   - Profile stats and charts, Settings (appearance, storage, CSV export, What's New).
   - Mint-sage matte clay redesign, iOS 17 minimum, privacy manifest.
6. **Next:** App Store.
   - Needs a paid Apple Developer account (signing, TestFlight, App Store Connect); see `docs/AppStore.md`.
   - Real App Store screenshots from a device, a support URL and a privacy policy URL.
