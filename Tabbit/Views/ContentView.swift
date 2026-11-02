import SwiftUI

struct ContentView: View {
    @StateObject private var model = ScanViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle:
                    idleView
                case .recognizing:
                    ProgressView("Reading receipt…")
                case .finished(let result):
                    resultView(result)
                case .failed(let message):
                    failureView(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(appName)
        }
        .fullScreenCover(isPresented: $model.isShowingScanner) {
            DocumentScannerView(onOutcome: { outcome in
                model.handle(outcome)
            })
            .ignoresSafeArea()
        }
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(Color.accentColor)
            Text("Scan a receipt to read its text.")
                .multilineTextAlignment(.center)
                .foregroundColor(Color.secondary)
            scanButton(title: "Scan Receipt")
        }
        .padding()
    }

    private func resultView(_ result: ScanResult) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(summary(for: result))
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                    if result.blocks.isEmpty {
                        Text("No text was found. Try again with the receipt flat and well lit.")
                            .foregroundColor(Color.secondary)
                    } else {
                        Text(result.plainText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            Divider()
            scanButton(title: "Scan Again")
                .padding()
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(Color.orange)
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(Color.secondary)
            scanButton(title: "Try Again")
        }
        .padding()
    }

    // MARK: - Pieces

    private func scanButton(title: String) -> some View {
        Button(action: {
            model.startScan()
        }, label: {
            Label(title, systemImage: "camera")
                .frame(maxWidth: .infinity)
        })
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func summary(for result: ScanResult) -> String {
        let pages = result.pageCount == 1 ? "1 page" : "\(result.pageCount) pages"
        let blocks = result.blocks.count == 1 ? "1 text block" : "\(result.blocks.count) text blocks"
        return "\(pages) · \(blocks)"
    }

    /// The home-screen name from Info.plist (set by APP_DISPLAY_NAME in project.yml).
    private var appName: String {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return displayName ?? "Receipt Scanner"
    }
}
