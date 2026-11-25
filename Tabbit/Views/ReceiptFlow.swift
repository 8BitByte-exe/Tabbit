import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// A receipt open in the editor, with the photos to save alongside a new one.
struct EditorSession: Identifiable {
    let id = UUID()
    var record: ReceiptRecord
    var pageJPEGs: [Data]
    var thumbnailJPEG: Data?
    let isNew: Bool
}

/// Adding and editing receipts: choose a source → camera or photos → read the
/// text on the device → review in the editor → save.
@MainActor
final class ReceiptFlow: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Reading the text of a scan or photo.
        case processing
        case failed(String)
    }

    enum Source {
        case camera
        case photos
        case manual
    }

    @Published private(set) var phase: Phase = .idle
    /// True while Apple Intelligence is reading the scan (shown on the processing overlay).
    @Published private(set) var isUsingIntelligence: Bool = false
    /// The small "Scan / Photo / Type" sheet.
    @Published var isChoosingSource: Bool = false
    @Published var isShowingScanner: Bool = false
    @Published var isShowingPhotoPicker: Bool = false
    @Published var photoSelection: [PhotosPickerItem] = []
    /// The receipt being edited (a sheet).
    @Published var session: EditorSession?

    /// The group new receipts go into (nil = My Receipts).
    private(set) var targetGroupID: UUID?
    /// The business (Work) new receipts go into, and its job. Never set with a group.
    private(set) var targetBusinessID: UUID?
    private(set) var targetJobID: UUID?
    /// Picked in the source sheet; acted on once that sheet has closed.
    private var pendingSource: Source?

    private let store: TabbitStore

    init(store: TabbitStore) {
        self.store = store
    }

    // MARK: - Starting

    /// Opens the source sheet for a new receipt in a group (or My Receipts).
    func addReceipt(to groupID: UUID?) {
        self.targetGroupID = groupID
        self.targetBusinessID = nil
        self.targetJobID = nil
        self.phase = .idle
        self.isChoosingSource = true
    }

    /// Opens the source sheet for a business's new receipt (an expense), optionally for one job.
    func addReceipt(toBusiness businessID: UUID, job jobID: UUID?) {
        self.targetGroupID = nil
        self.targetBusinessID = businessID
        self.targetJobID = jobID
        self.phase = .idle
        self.isChoosingSource = true
    }

    /// Puts a new receipt where it was added from: a group, a business (and job), or My Receipts.
    private func placed(_ record: ReceiptRecord) -> ReceiptRecord {
        var copy = record
        copy.groupID = targetGroupID
        copy.businessID = targetGroupID == nil ? targetBusinessID : nil
        copy.jobID = copy.businessID == nil ? nil : targetJobID
        return copy
    }

    /// Called by the source sheet. The next step starts when the sheet has closed,
    /// because SwiftUI can't present two things at once.
    func choose(_ source: Source) {
        self.pendingSource = source
        self.isChoosingSource = false
    }

    /// The source sheet finished closing.
    func sourceSheetDismissed() {
        guard let source = pendingSource else {
            return
        }
        pendingSource = nil
        switch source {
        case .camera:
            startCamera()
        case .photos:
            photoSelection = []
            isShowingPhotoPicker = true
        case .manual:
            let record = placed(ReceiptRecord(paidBy: Person.meID, source: .manual))
            session = EditorSession(record: record, pageJPEGs: [], thumbnailJPEG: nil, isNew: true)
        }
    }

    func edit(_ record: ReceiptRecord) {
        session = EditorSession(record: record, pageJPEGs: [], thumbnailJPEG: nil, isNew: false)
    }

    func dismissError() {
        phase = .idle
    }

    func retry() {
        phase = .idle
        isChoosingSource = true
    }

    #if DEBUG
    /// For CI screenshots of the processing overlay.
    func showProcessingForScreenshots() {
        phase = .processing
        isUsingIntelligence = true
    }
    #endif

    // MARK: - Camera

    private func startCamera() {
        guard VNDocumentCameraViewController.isSupported else {
            phase = .failed("The camera scanner isn't available on this device. Try choosing a photo instead.")
            return
        }
        isShowingScanner = true
    }

    /// Called by the document camera when it finishes, is cancelled, or fails.
    func handle(_ outcome: DocumentScanOutcome) {
        // The document camera never dismisses itself.
        isShowingScanner = false
        switch outcome {
        case .cancelled:
            break
        case .failed(let error):
            phase = .failed(error.localizedDescription)
        case .scanned(let images):
            process(images, source: .camera)
        }
    }

    // MARK: - Photos

    /// Called when the photo picker returns. Each photo becomes a page.
    func handlePickedPhotos() {
        let items = photoSelection
        photoSelection = []
        guard !items.isEmpty else {
            return
        }
        phase = .processing
        Task {
            let images = await ReceiptFlow.loadImages(items)
            if images.isEmpty {
                self.phase = .failed("Couldn't open that photo. Please try another one.")
            } else {
                self.process(images, source: .photo)
            }
        }
    }

    static func loadImages(_ items: [PhotosPickerItem]) async -> [UIImage] {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        return images
    }

    // MARK: - Reading

    private func process(_ images: [UIImage], source: ReceiptSource) {
        guard !images.isEmpty else {
            phase = .failed("No pages were scanned. Please try again.")
            return
        }
        phase = .processing
        let options = OCRSettings.current
        let groupID = targetGroupID
        // The model starts loading now, while the text is read, so it's ready when needed.
        let warmup = ReceiptIntelligence.warmUp()
        let modelPhoto = warmup != nil && ReceiptIntelligence.willSendPhoto

        // This Task runs on the main actor (it inherits it from this class).
        // OCR, parsing and photo compression run in a detached task so the UI stays responsive.
        Task {
            do {
                var processed: ProcessedScan = try await Task.detached(priority: .userInitiated) {
                    return try await ScanProcessor.process(images: images, options: options, modelPhoto: modelPhoto)
                }.value
                // Apple Intelligence (iOS 26, on-device), checked against the scan; keeps
                // the rules result if it isn't available or doesn't check out.
                if warmup != nil {
                    self.isUsingIntelligence = true
                    processed = await ReceiptIntelligence.refine(processed, warmup: warmup)
                    self.isUsingIntelligence = false
                }
                let record = self.placed(ScanAutofill.record(from: processed, source: source, groupID: groupID))
                self.phase = .idle
                self.session = EditorSession(record: record, pageJPEGs: processed.pageJPEGs,
                                             thumbnailJPEG: processed.thumbnailJPEG, isNew: true)
                Haptics.success()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Saving

    /// Saves the editor's receipt. Returns an error message, or nil on success.
    func save(_ record: ReceiptRecord, from session: EditorSession) -> String? {
        // Saving from the editor means the person has looked at the "Check" marks.
        var record = record
        record.checks = []
        do {
            if session.isNew {
                try store.add(record, pageJPEGs: session.pageJPEGs, thumbnailJPEG: session.thumbnailJPEG)
            } else {
                try store.update(record)
            }
            Haptics.success()
            return nil
        } catch {
            return "Couldn't save the receipt: \(error.localizedDescription)"
        }
    }
}
