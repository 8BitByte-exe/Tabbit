import Foundation

/// A receipt kept on the phone: the editable fields, what the parser originally
/// found, and the raw OCR. Page photos are stored next to it as JPEG files
/// (see ReceiptStore).
struct SavedReceipt: Identifiable, Equatable, Codable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    /// The fields as shown and edited by the user.
    var receipt: Receipt
    /// What the parser produced, kept so edits can be undone.
    let parsed: Receipt
    /// The raw OCR result (for the Raw text view and exports).
    let scan: ScanResult
    /// How many page photos are stored.
    let pageImageCount: Int
    /// Whether Vision's language correction was on for this scan.
    let languageCorrection: Bool?

    /// True if the user changed anything the parser found.
    var isEdited: Bool {
        return receipt != parsed
    }

    /// The name to show in lists.
    var displayTitle: String {
        let merchant = receipt.merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return merchant.isEmpty ? "Receipt" : merchant
    }
}
