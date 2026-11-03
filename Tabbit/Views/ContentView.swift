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
                case .finished(let processed):
                    ReceiptResultView(processed: processed, onScanAgain: {
                        model.startScan()
                    })
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
            ScanButton(title: "Scan Receipt", action: {
                model.startScan()
            })
        }
        .padding()
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
            ScanButton(title: "Try Again", action: {
                model.startScan()
            })
        }
        .padding()
    }

    /// The home-screen name from Info.plist (set by APP_DISPLAY_NAME in project.yml).
    private var appName: String {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return displayName ?? "Receipt Scanner"
    }
}
