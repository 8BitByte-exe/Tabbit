#if canImport(FoundationModels)
import Foundation
import FoundationModels
import UIKit

// Apple Intelligence's on-device language model (iOS 26). Nothing here goes over
// the network: Foundation Models runs entirely on the iPhone.
//
// The model labels the receipt's numbered lines; it never writes an amount. Every
// field is required (no optionals): the model tends to leave optional fields out,
// which is what lost the total in 1.1's first build.

@available(iOS 26.0, *)
@Generable
enum GeneratedLineKind {
    case item
    case discount
    case subtotal
    case tax
    case taxTotal
    case tip
    case total
    case payment
    case savings
    case unitPrice
    case other
}

@available(iOS 26.0, *)
@Generable
struct GeneratedLineLabel {
    @Guide(description: "The number in brackets at the start of the line, like 4 for [4]")
    var line: Int

    @Guide(description: "What the line is")
    var kind: GeneratedLineKind

    @Guide(description: "For an item or discount, the product's name in Title Case, like Organic Bananas. Empty for every other kind.")
    var name: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedReceiptReading {
    @Guide(description: "The business's brand name only, like Best Buy, Shell or Trader Joe's. Never the address, city, branch or store number.")
    var storeName: String

    @Guide(description: "One label for each numbered line, in order, each number only once")
    var lines: [GeneratedLineLabel]

    @Guide(description: "True if the receipt says its prices already include the tax, like VAT included or HST included")
    var pricesIncludeTax: Bool

    @Guide(description: "The kind of business: one category word from the list in the instructions, like groceries for a supermarket")
    var category: String

    @Guide(description: "The purchase date as YYYY-MM-DD, or an empty string if no date is printed")
    var date: String
}

@available(iOS 26.0, *)
extension GeneratedLineKind {
    var plain: ModelLineKind {
        switch self {
        case .item: return .item
        case .discount: return .discount
        case .subtotal: return .subtotal
        case .tax: return .tax
        case .taxTotal: return .taxTotal
        case .tip: return .tip
        case .total: return .total
        case .payment: return .payment
        case .savings: return .savings
        case .unitPrice: return .unitPrice
        case .other: return .other
        }
    }
}

@available(iOS 26.0, *)
extension GeneratedReceiptReading {
    var plain: ModelReceiptReading {
        return ModelReceiptReading(
            storeName: storeName,
            labels: lines.map { label in
                ModelReceiptReading.Label(line: label.line, kind: label.kind.plain, name: label.name)
            },
            pricesIncludeTax: pricesIncludeTax,
            category: category,
            date: date
        )
    }
}

@available(iOS 26.0, *)
enum AppleIntelligenceReader {

    static var status: IntelligenceStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .notSupported
            case .appleIntelligenceNotEnabled:
                return .turnedOff
            case .modelNotReady:
                return .downloading
            @unknown default:
                return .notSupported
            }
        @unknown default:
            return .notSupported
        }
    }

    /// A new session with Tabbit's instructions. One session reads one receipt.
    static func makeSession() -> LanguageModelSession {
        return LanguageModelSession(instructions: ReceiptPrompt.instructions)
    }

    /// Asks the on-device model to label the receipt's lines. Greedy sampling, so the
    /// same scan always gives the same answer.
    static func read(prompt: String, session: LanguageModelSession) async throws -> ModelReceiptReading {
        let response = try await session.respond(to: prompt, generating: GeneratedReceiptReading.self,
                                                 options: GenerationOptions(sampling: .greedy))
        return response.content.plain
    }

    /// True if this build can show the model a photo: built with the iOS 27 SDK and running
    /// on iOS 27 or later. The model reads the photo on the device, like the text.
    static var canSeePhotos: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return true
        }
        #endif
        return false
    }

    /// Like `read(prompt:session:)`, with the receipt's photo next to the text (iOS 27).
    /// Throws `PhotoUnsupported` on older systems.
    static func read(prompt: String, photo: UIImage, session: LanguageModelSession) async throws -> ModelReceiptReading {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let response = try await session.respond(generating: GeneratedReceiptReading.self,
                                                     options: GenerationOptions(sampling: .greedy)) {
                prompt
                Attachment(photo)
            }
            return response.content.plain
        }
        #endif
        throw PhotoUnsupported()
    }

    struct PhotoUnsupported: Error {}

    /// True if the prompt didn't fit the model's context window.
    static func isTooLong(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return false
        }
        if case .exceededContextWindowSize = generationError {
            return true
        }
        return false
    }

    /// True if Apple's safety filter stopped the model.
    static func isGuardrail(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return false
        }
        if case .guardrailViolation = generationError {
            return true
        }
        return false
    }
}
/// One request to the model, carried into the timeout's task. The session may be one
/// that was warmed up while the scan was being read.
@available(iOS 26.0, *)
final class ModelRequest: @unchecked Sendable {
    let prompt: String
    let photo: UIImage?
    let session: LanguageModelSession

    init(prompt: String, photo: UIImage?, session: LanguageModelSession?) {
        self.prompt = prompt
        self.photo = photo
        self.session = session ?? AppleIntelligenceReader.makeSession()
    }

    func run() async throws -> ModelReceiptReading {
        if let photo = photo {
            return try await AppleIntelligenceReader.read(prompt: prompt, photo: photo, session: session)
        }
        return try await AppleIntelligenceReader.read(prompt: prompt, session: session)
    }
}
#endif
