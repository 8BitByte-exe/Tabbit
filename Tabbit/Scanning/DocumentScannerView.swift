import SwiftUI
import UIKit
import VisionKit

/// What happened when the document camera closed.
enum DocumentScanOutcome {
    /// The user saved a scan. One image per page, in page order.
    case scanned([UIImage])
    /// The user tapped Cancel.
    case cancelled
    /// The document camera reported an error.
    case failed(Error)
}

/// SwiftUI wrapper around VisionKit's document camera.
///
/// The camera does not dismiss itself: the presenting view must hide it
/// when `onOutcome` is called.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onOutcome: (DocumentScanOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(onOutcome: onOutcome)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // Keep the coordinator pointing at the latest closure.
        context.coordinator.onOutcome = onOutcome
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var onOutcome: (DocumentScanOutcome) -> Void

        init(onOutcome: @escaping (DocumentScanOutcome) -> Void) {
            self.onOutcome = onOutcome
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: pageIndex))
            }
            onOutcome(.scanned(images))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onOutcome(.cancelled)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onOutcome(.failed(error))
        }
    }
}
