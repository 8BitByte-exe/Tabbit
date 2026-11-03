# CLAUDE.md

Notes for working on Tabbit, a native SwiftUI receipt scanner for iOS.

## The main constraint: no Mac, no local builds

The owner has no Mac and no Xcode. **The GitHub Actions macOS runner is the only compiler**, and the only test of the UI is installing the built app on a real iPhone (the owner's iPhone 16 Pro on iOS 26).

- Write simple, conservative Swift. Before every commit, review each changed file for compile errors: exact API signatures, imports, optionals, and API availability on iOS 16.
- After every push, check the **Build** workflow run. It has two jobs, `build` (the IPA) and `test` (unit tests). If either fails, read the job log (GitHub MCP tools: `actions_list` → `list_workflow_runs` / `list_workflow_jobs`, then `get_job_logs`). Search the log for `error:`, `failed`, and `The following build commands failed`. Fix the cause and push again.
- Don't call something done until both jobs are green.
- Don't add steps that need Xcode on a dev machine.

## Privacy rule: everything stays on the device

Scanning, OCR, parsing and storage must run on the iPhone.

- No networking code: no `URLSession`, no web APIs, no analytics, no third-party SDKs.
- Use only on-device Apple frameworks: VisionKit, Vision, Foundation, and later Foundation Models.
- The only way data leaves the phone is when the user explicitly shares something (Export button, later CSV export).

## Build and sideload workflow

1. Push to any branch. `.github/workflows/build.yml` runs on `macos-latest` with its default Xcode. Manual runs use `workflow_dispatch`.
2. **`build` job:** `brew install xcodegen` → `xcodegen generate` → `xcodebuild -scheme Tabbit -configuration Release -sdk iphoneos -destination generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`. The log prints the bundled Info.plist. `Tabbit.app` is zipped into `ReceiptScanner.ipa` and uploaded as the `ReceiptScanner` artifact.
3. **`test` job (in parallel):** picks the newest available iPhone simulator and runs `xcodebuild test -scheme Tabbit`.
4. The owner downloads the artifact and sideloads it with **Sideloadly** using a free Apple ID. Sideloadly does the signing, so there are no certificates or provisioning profiles in this repo. Free-account apps expire after 7 days. Keep the bundle ID stable: changing it uses up one of the account's 10 new app IDs per week and installs a separate app.

## Project structure

```
project.yml                  XcodeGen spec: identity, targets, Info.plist, scheme
.github/workflows/build.yml  CI: build job (unsigned IPA) + test job (simulator unit tests)
Tabbit/
  TabbitApp.swift            @main SwiftUI App
  Models/
    ScanResult.swift         RecognizedTextBlock (text, confidence, normalized box, page) + ScanResult
    Receipt.swift            Receipt, ReceiptLineItem, CalendarDate, ReceiptParserKind
    ScanExport.swift         JSON format of the Export button (also the test-fixture format)
  Scanning/
    DocumentScannerView.swift  VNDocumentCameraViewController wrapped for SwiftUI
    TextRecognizer.swift       VNRecognizeTextRequest (.accurate, language correction)
    ScanProcessor.swift        OCR → parse → write export file (runs off the main thread)
  Parsing/
    LineGrouper.swift          rebuilds receipt lines from Vision blocks by height
    AmountParser.swift         money amounts at the end of a line
    ReceiptDateParser.swift    purchase date (explicit patterns, not NSDataDetector)
    RulesReceiptParser.swift   the rules-based parser (fallback tier, works on iOS 16+)
    ReceiptValidator.swift     arithmetic checks: items = subtotal, subtotal + tax = total
    RegexHelpers.swift         NSRegularExpression helpers (`Patterns.make`)
  Views/
    ScanViewModel.swift        @MainActor state machine: idle / recognizing / finished / failed
    ContentView.swift          idle and error screens
    ReceiptResultView.swift    parsed receipt / raw text, Export and Scan Again buttons
    ScanButton.swift
TabbitTests/                 XCTest unit tests (run in CI on a simulator)
  Support/TestSupport.swift  money("1.29"), ReceiptLayoutBuilder (fake Vision output), Fixtures loader
  Fixtures/*.json            scan exports used as test fixtures
```

- **The `.xcodeproj` and `Tabbit/Info.plist` are generated and gitignored.** Change `project.yml` instead, and never commit a hand-written `.xcodeproj`.
- Info.plist keys go under `targets.Tabbit.info.properties` in `project.yml`.
- **App identity lives in one place:** `APP_BUNDLE_ID` and `APP_DISPLAY_NAME` in the top-level `settings.base` of `project.yml`. Targets and Info.plist reference them as `$(APP_BUNDLE_ID)` / `$(APP_DISPLAY_NAME)`.
- New Swift files in `Tabbit/` or `TabbitTests/` are picked up automatically by XcodeGen; there's no project file to edit.

## Code rules

- Swift 5 language mode (`SWIFT_VERSION: "5.0"`), deployment target iOS 16.0, iPhone only.
- No third-party dependencies.
- Use only APIs available on iOS 16. Gate anything newer with `if #available(iOS NN, *)` / `@available`, and with `#if canImport(Module)` when the framework itself is new.
- Regexes: use `NSRegularExpression` via `Patterns.make` with raw strings (`#"..."#`). Don't use Swift `Regex` literals: bare `/.../` literals need a compiler flag in Swift 5 mode.
- Money is `Decimal`, never `Double`. Dates on receipts are `CalendarDate` (no time zone).
- No `#Preview` or Xcode-only conveniences; nobody can open the previews.
- Keep UI state on the main actor (`ScanViewModel` is `@MainActor`). Do heavy work like OCR and parsing off the main thread (`ScanProcessor` runs in a detached task).
- Bounding boxes are stored the way Vision returns them: normalized 0–1, with the origin at the **bottom-left** of the page.
- Put parsing logic in plain Swift types that unit tests can cover. CI can only test logic; UI is tested on the phone.
- No asset catalog yet. If you add one (for example an app icon) and CI fails while compiling assets, the runner may be missing a simulator runtime. Try adding `xcodebuild -downloadPlatform iOS` before the build.

## Test fixtures from real receipts

The app's **Export** button shares a JSON file (`ScanExport`): the raw OCR blocks with positions plus what the parser produced. No images. Drop such a file into `TabbitTests/Fixtures/` and load it with `Fixtures.scan(named:)`. Then assert what the parser should return. The repo is public, so real receipts should be redacted (card digits, addresses) before they're committed.

## Roadmap

The design is tiered and entirely on-device. Each phone gets the best tier it supports, and the rules always run as the fallback and as a sanity check.

| Tier | Requires | OCR | Parsing |
|---|---|---|---|
| 1 | iOS 26 + Apple Intelligence on | Vision `RecognizeDocumentsRequest` | Foundation Models fills a `@Generable` receipt; rules + `ReceiptValidator` verify it |
| 2 | iOS 26 | Vision `RecognizeDocumentsRequest` | Rules, helped by the document reader's rows and detected amounts |
| 3 | iOS 16+ | `VNRecognizeTextRequest` | Rules (`RulesReceiptParser`) |

1. **Done:** scan + raw OCR text.
2. **Done:** Export button, rules parser (tier 3), arithmetic checks, unit tests in CI, "Parsed with" label. Next: tune the rules with real exported receipts.
3. **Next:** iOS 26 tiers.
   - Vision's document reader.
   - Foundation Models with a `@Generable` receipt type. Guard with `#if canImport(FoundationModels)`, `@available(iOS 26, *)` and `SystemLanguageModel.default.availability`.
   - Validate the model's numbers: the arithmetic checks, and every amount must appear in the OCR text. Fall back to the rules result when they fail.
   - The model can only be tested on the phone; CI runners most likely can't run Apple Intelligence.
4. **Saving with editing, plus CSV export** (share sheet). The owner still has to decide whether saved receipts go into iCloud Backup. Use iOS file protection either way.
