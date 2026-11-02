import Foundation
import SwiftUI
import UIKit
import VisionKit

/// Drives the scan → recognize → show flow for ContentView.
@MainActor
final class ScanViewModel: ObservableObject {

    enum Phase {
        /// Nothing scanned yet.
        case idle
        /// Text recognition is running.
        case recognizing
        /// Recognition finished.
        case finished(ScanResult)
        /// Something went wrong; the message is shown to the user.
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    /// Bound to the full-screen cover that shows the document camera.
    @Published var isShowingScanner: Bool = false

    /// Opens the document camera, or shows an error if this device can't scan.
    func startScan() {
        guard VNDocumentCameraViewController.isSupported else {
            self.phase = .failed("Document scanning isn't available on this device.")
            return
        }
        self.isShowingScanner = true
    }

    /// Called by the document camera when it finishes, is cancelled, or fails.
    func handle(_ outcome: DocumentScanOutcome) {
        // The document camera never dismisses itself.
        self.isShowingScanner = false

        switch outcome {
        case .cancelled:
            // Keep whatever was on screen before (idle or the previous result).
            break
        case .failed(let error):
            self.phase = .failed(error.localizedDescription)
        case .scanned(let images):
            recognizeText(in: images)
        }
    }

    private func recognizeText(in images: [UIImage]) {
        guard !images.isEmpty else {
            self.phase = .failed("No pages were scanned. Please try again.")
            return
        }

        self.phase = .recognizing

        // This Task runs on the main actor (it inherits it from this class).
        // The OCR itself runs in a detached task so the UI stays responsive.
        Task {
            do {
                let result: ScanResult = try await Task.detached(priority: .userInitiated) {
                    return try TextRecognizer.recognizeText(in: images)
                }.value
                self.phase = .finished(result)
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }
}
