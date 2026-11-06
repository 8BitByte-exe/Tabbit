import Foundation

/// Whether Apple Intelligence can read receipts on this iPhone.
enum IntelligenceStatus: Equatable {
    case available
    /// Apple Intelligence is off in the iPhone's Settings.
    case turnedOff
    /// The model is still downloading.
    case downloading
    /// This iPhone can't run Apple Intelligence.
    case notSupported
    /// Needs iOS 26 or later.
    case needsNewerIOS

    var title: String {
        switch self {
        case .available: return "Ready"
        case .turnedOff: return "Turned off"
        case .downloading: return "Downloading"
        case .notSupported: return "Not on this iPhone"
        case .needsNewerIOS: return "Needs iOS 26"
        }
    }

    var explanation: String {
        switch self {
        case .available:
            return "Reads items, totals and the store's name more accurately, entirely on this iPhone."
        case .turnedOff:
            return "Turn on Apple Intelligence in the iPhone's Settings app to use it here."
        case .downloading:
            return "Apple Intelligence is still getting ready. Tabbit uses its built-in rules until then."
        case .notSupported:
            return "This iPhone doesn't support Apple Intelligence, so Tabbit uses its built-in rules."
        case .needsNewerIOS:
            return "Update to iOS 26 to read receipts with Apple Intelligence."
        }
    }
}

/// The Apple Intelligence step of reading a receipt (roadmap tier 1).
///
/// Runs after OCR and the rules parser. The model reads the receipt's lines, and
/// `ModelReceiptVerifier` checks every number against the scan before anything is
/// used. If the model isn't available, is switched off, fails or takes too long,
/// the rules result is kept. Everything runs on the device.
enum ReceiptIntelligence {

    /// Settings toggle (on by default).
    static let enabledKey = "appleIntelligence.enabled"

    /// Give up and keep the rules result after this long (seconds).
    static let timeout: Double = 25

    static var isEnabled: Bool {
        return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var status: IntelligenceStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligenceReader.status
        }
        #endif
        return .needsNewerIOS
    }

    /// True if the next scan will be read with Apple Intelligence.
    static var willRun: Bool {
        return isEnabled && status == .available
    }

    /// The scan with the model's checked reading, or unchanged if the model can't help.
    static func refine(_ processed: ProcessedScan) async -> ProcessedScan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard willRun else {
                return processed
            }
            let prompt = ReceiptPrompt.make(for: processed.scan)
            guard !prompt.isEmpty else {
                return processed
            }
            var result = processed
            do {
                let draft = try await withTimeout(seconds: timeout) {
                    try await AppleIntelligenceReader.read(prompt: prompt)
                }
                let outcome = ModelReceiptVerifier.evaluate(draft, scan: processed.scan, rules: processed.receipt)
                result.receipt = outcome.receipt
                result.suggestedCategory = outcome.suggestedCategory
            } catch {
                result.receipt.notes.append(ModelReceiptVerifier.unavailableNote)
            }
            return result
        }
        #endif
        return processed
    }

    private struct TimedOut: Error {}

    /// Runs `operation`, but throws if it takes longer than `seconds`.
    static func withTimeout<T: Sendable>(seconds: Double,
                                         _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimedOut()
            }
            defer {
                group.cancelAll()
            }
            guard let first = try await group.next() else {
                throw TimedOut()
            }
            return first
        }
    }
}
