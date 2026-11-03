# CLAUDE.md

Notes for working on Tabbit, a native SwiftUI receipt scanner for iOS.

## The main constraint: no Mac, no local builds

The owner has no Mac and no Xcode. **The GitHub Actions macOS runner is the only compiler**, and the only test is installing the built app on a real iPhone.

- Write simple, conservative Swift. Before every commit, review each changed file for compile errors: exact API signatures, imports, optionals, and API availability on iOS 16.
- After every push, check the **Build** workflow run. If it fails, read the job log (GitHub MCP tools: `actions_list` → `list_workflow_runs` / `list_workflow_jobs`, then `get_job_logs`). Search the log for `error:` and for `The following build commands failed`. Fix the cause and push again.
- Don't call something done until CI is green.
- The simulator is never used and there's nothing to run locally. Don't add steps that need Xcode on a dev machine.

## Build and sideload workflow

1. Push to any branch. `.github/workflows/build.yml` runs on `macos-latest` with its default Xcode. Manual runs use `workflow_dispatch`.
2. CI: `brew install xcodegen` → `xcodegen generate` → `xcodebuild -scheme Tabbit -configuration Release -sdk iphoneos -destination generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`.
3. `Tabbit.app` is copied into `Payload/`, zipped as `ReceiptScanner.ipa`, and uploaded as the `ReceiptScanner` artifact.
4. The owner downloads it and sideloads it with **Sideloadly** using a free Apple ID. Sideloadly does the signing, so there are no certificates or provisioning profiles in this repo. Free-account apps expire after 7 days.

## Project structure

```
project.yml                  XcodeGen spec: target, build settings, Info.plist, scheme
.github/workflows/build.yml  CI build → unsigned ReceiptScanner.ipa artifact
Tabbit/
  TabbitApp.swift            @main SwiftUI App
  Models/ScanResult.swift    RecognizedTextBlock (text, confidence, normalized bounding box, page)
                             and ScanResult (all blocks + plainText)
  Scanning/DocumentScannerView.swift  VNDocumentCameraViewController wrapped for SwiftUI
  Scanning/TextRecognizer.swift       VNRecognizeTextRequest (.accurate, language correction)
  Views/ScanViewModel.swift  @MainActor state machine: idle / recognizing / finished / failed
  Views/ContentView.swift    UI
```

- **The `.xcodeproj` and `Tabbit/Info.plist` are generated and gitignored.** Change `project.yml` instead, and never commit a hand-written `.xcodeproj`.
- Info.plist keys go under `targets.Tabbit.info.properties` in `project.yml`.
- **App identity lives in one place:** `PRODUCT_BUNDLE_IDENTIFIER` and `APP_DISPLAY_NAME` at the top of the target settings in `project.yml`. Info.plist values reference them as `$(APP_DISPLAY_NAME)`, and so on.
- New Swift files in `Tabbit/` are picked up automatically by XcodeGen; there's no project file to edit.

## Code rules

- Swift 5 language mode (`SWIFT_VERSION: "5.0"`), deployment target iOS 16.0, iPhone only.
- No third-party dependencies.
- Use only APIs available on iOS 16. Gate anything newer with `if #available(iOS NN, *)`, and with `#if canImport(Module)` when the framework itself is new.
- No `#Preview` or Xcode-only conveniences; nobody can open the previews.
- Keep UI state on the main actor (`ScanViewModel` is `@MainActor`). Do heavy work like OCR, and later parsing, off the main thread.
- Bounding boxes are stored the way Vision returns them: normalized 0–1, with the origin at the **bottom-left** of the page.
- No asset catalog yet. If you add one (for example an app icon) and CI fails while compiling assets, the runner may be missing a simulator runtime. Try adding `xcodebuild -downloadPlatform iOS` before the build.

## Roadmap

1. **Scan + raw OCR text** (done in the first pass): document camera → Vision OCR → show the plain text. Blocks are kept with bounding boxes for the parser.
2. **Receipt parser** that extracts merchant, date, line items, tax, and total from `ScanResult` using text plus layout (group blocks into lines by bounding box). Add a unit-test target in `project.yml` and run the tests in CI on a simulator destination. Use OCR samples copied from the app as test fixtures.
3. **Saving and CSV export**: persist parsed receipts on the device and export them as CSV through the share sheet.
4. **Later: Apple Intelligence**: on iOS 26+ with Apple Intelligence available, use the Foundation Models framework for better parsing. Guard it with `#if canImport(FoundationModels)`, `if #available(iOS 26, *)`, and a model availability check, and fall back to the heuristic parser from step 2 on older or unsupported devices.
