import Foundation
import SwiftUI
import UIKit
import VisionKit

/// Drives scan → recognize → save → open, plus navigation.
@MainActor
final class ScanViewModel: ObservableObject {

    enum Phase: Equatable {
        /// Nothing in progress.
        case idle
        /// Text recognition is running.
        case recognizing
        /// Something went wrong; the message is shown to the user.
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    /// Bound to the full-screen cover that shows the document camera.
    @Published var isShowingScanner: Bool = false

    /// Navigation stack: the receipts being shown, by ID.
    @Published var path: [UUID] = []

    private let store: ReceiptStore

    init(store: ReceiptStore) {
        self.store = store
    }

    /// Opens the document camera, or shows an error if this device can't scan.
    func startScan() {
        guard VNDocumentCameraViewController.isSupported else {
            self.phase = .failed("Document scanning isn't available on this device.")
            return
        }
        self.phase = .idle
        self.isShowingScanner = true
    }

    func dismissError() {
        self.phase = .idle
    }

    #if DEBUG
    /// For CI screenshots of the processing overlay.
    func showProcessingForScreenshots() {
        self.phase = .recognizing
    }
    #endif

    /// Called by the document camera when it finishes, is cancelled, or fails.
    func handle(_ outcome: DocumentScanOutcome) {
        // The document camera never dismisses itself.
        self.isShowingScanner = false

        switch outcome {
        case .cancelled:
            break
        case .failed(let error):
            self.phase = .failed(error.localizedDescription)
        case .scanned(let images):
            process(images)
        }
    }

    private func process(_ images: [UIImage]) {
        guard !images.isEmpty else {
            self.phase = .failed("No pages were scanned. Please try again.")
            return
        }

        self.phase = .recognizing
        let options = OCRSettings.current

        // This Task runs on the main actor (it inherits it from this class).
        // OCR, parsing and photo compression run in a detached task so the UI stays responsive.
        Task {
            do {
                let processed: ProcessedScan = try await Task.detached(priority: .userInitiated) {
                    return try ScanProcessor.process(images: images, options: options)
                }.value
                let saved = try self.store.add(processed)
                self.phase = .idle
                self.path = [saved.id]
                Haptics.success()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }
}
