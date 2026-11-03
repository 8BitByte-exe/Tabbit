import SwiftUI

@main
struct TabbitApp: App {
    @StateObject private var store: ReceiptStore
    @StateObject private var scanner: ScanViewModel

    init() {
        Theme.configureNavigationBar()

        let store: ReceiptStore
        #if DEBUG
        if DemoMode.isEnabled {
            // Screenshot mode (CI): sample receipts in a throwaway folder, never the real ones.
            store = ReceiptStore(folder: DemoMode.freshFolder())
            DemoMode.populate(store)
        } else {
            store = ReceiptStore()
        }
        #else
        store = ReceiptStore()
        #endif

        let scanner = ScanViewModel(store: store)
        #if DEBUG
        DemoMode.prepare(scanner, store: store)
        #endif

        _store = StateObject(wrappedValue: store)
        _scanner = StateObject(wrappedValue: scanner)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(scanner)
        }
    }
}

/// Navigation, the document camera, and the processing/error overlays.
struct RootView: View {
    @EnvironmentObject private var store: ReceiptStore
    @EnvironmentObject private var scanner: ScanViewModel

    var body: some View {
        NavigationStack(path: $scanner.path) {
            HomeView()
                .navigationDestination(for: UUID.self) { id in
                    ReceiptDetailView(receiptID: id)
                }
        }
        .tint(Theme.Colors.accentInk)
        .fullScreenCover(isPresented: $scanner.isShowingScanner) {
            DocumentScannerView(onOutcome: { outcome in
                scanner.handle(outcome)
            })
            .ignoresSafeArea()
        }
        .overlay {
            phaseOverlay
        }
    }

    @ViewBuilder
    private var phaseOverlay: some View {
        switch scanner.phase {
        case .idle:
            EmptyView()
        case .recognizing:
            ProcessingOverlay()
        case .failed(let message):
            ErrorOverlay(
                message: message,
                onRetry: {
                    scanner.startScan()
                },
                onClose: {
                    scanner.dismissError()
                }
            )
        }
    }
}

/// Shown while a scan is being read.
struct ProcessingOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Theme.Colors.background
                .opacity(reduceTransparency ? 1 : 0.9)
                .ignoresSafeArea()
            NeumorphicCard {
                VStack(spacing: Theme.Spacing.l) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.Colors.accentInk)
                    Text("Reading your receipt…")
                        .font(Theme.Fonts.headline)
                        .foregroundColor(Theme.Colors.text)
                    Text("Everything stays on this iPhone.")
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.xxl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading your receipt")
    }
}

/// Shown when scanning or saving failed.
struct ErrorOverlay: View {
    let message: String
    let onRetry: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Theme.Colors.background
                .opacity(reduceTransparency ? 1 : 0.9)
                .ignoresSafeArea()
            NeumorphicCard {
                VStack(spacing: Theme.Spacing.l) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Theme.Fonts.largeTitle)
                        .foregroundColor(Theme.Colors.warning)
                        .accessibilityHidden(true)
                    Text("Something went wrong")
                        .font(Theme.Fonts.headline)
                        .foregroundColor(Theme.Colors.text)
                    Text(message)
                        .font(Theme.Fonts.callout)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                    Button(action: onRetry) {
                        Label("Try Again", systemImage: "camera")
                    }
                    .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                    Button("Close", action: onClose)
                        .buttonStyle(NeumorphicButtonStyle(prominence: .secondary))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.xl)
        }
    }
}
