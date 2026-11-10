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

/// The model's answer for one numbered line. The answers come as an array with exactly one
/// entry per numbered line, in order, so the model can't skip, repeat or invent lines.
@available(iOS 26.0, *)
@Generable
struct GeneratedLineAnswer {
    @Guide(description: "What the line is")
    var kind: GeneratedLineKind

    @Guide(description: "For an item or discount, the product's name in Title Case, like Organic Bananas. Empty for every other kind.")
    var name: String
}

/// The shape of the model's whole answer, built for each receipt so the `lines` array has
/// exactly as many entries as the receipt has numbered lines.
@available(iOS 26.0, *)
enum ReceiptAnswerSchema {

    static func make(lineCount: Int) throws -> GenerationSchema {
        let answer = DynamicGenerationSchema(type: GeneratedLineAnswer.self, guides: [])
        let lines = DynamicGenerationSchema(arrayOf: answer, minimumElements: lineCount, maximumElements: lineCount)
        let text = DynamicGenerationSchema(type: String.self, guides: [])
        let flag = DynamicGenerationSchema(type: Bool.self, guides: [])
        let root = DynamicGenerationSchema(name: "ReceiptReading", description: "What the receipt says", properties: [
            DynamicGenerationSchema.Property(
                name: "storeName",
                description: "The business's brand name only, like Best Buy, Shell or Trader Joe's, spelled correctly: fix letters the scan misread, like rn for m or 0 for O. Never the address, city, branch or store number.",
                schema: text, isOptional: false),
            DynamicGenerationSchema.Property(
                name: "isItemized",
                description: "True if the receipt lists what was bought. False for a card slip, payment stub or transaction record that only shows the amount paid.",
                schema: flag, isOptional: false),
            DynamicGenerationSchema.Property(
                name: "lines",
                description: "Exactly one answer for each numbered line, in order: the first answer is for [1], the second for [2], and so on.",
                schema: lines, isOptional: false),
            DynamicGenerationSchema.Property(
                name: "pricesIncludeTax",
                description: "True if the receipt says its prices already include the tax, like VAT included or HST included",
                schema: flag, isOptional: false),
            DynamicGenerationSchema.Property(
                name: "category",
                description: "The kind of business: one category word from the list in the instructions. Decide from the store's name, and when the name doesn't say, from what was bought.",
                schema: text, isOptional: false),
            DynamicGenerationSchema.Property(
                name: "date",
                description: "The purchase date as YYYY-MM-DD, or an empty string if no date is printed",
                schema: text, isOptional: false),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The answer in plain Swift. Answer number i is for line [i + 1].
    static func reading(from content: GeneratedContent) throws -> ModelReceiptReading {
        let answers = try content.value([GeneratedLineAnswer].self, forProperty: "lines")
        var labels: [ModelReceiptReading.Label] = []
        for (index, answer) in answers.enumerated() {
            labels.append(ModelReceiptReading.Label(line: index + 1, kind: answer.kind.plain, name: answer.name))
        }
        return ModelReceiptReading(
            storeName: try content.value(String.self, forProperty: "storeName"),
            labels: labels,
            pricesIncludeTax: try content.value(Bool.self, forProperty: "pricesIncludeTax"),
            category: try content.value(String.self, forProperty: "category"),
            date: try content.value(String.self, forProperty: "date"),
            isItemized: try content.value(Bool.self, forProperty: "isItemized")
        )
    }
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

    /// Asks the on-device model to label the receipt's `lineCount` numbered lines. Greedy
    /// sampling, so the same scan always gives the same answer.
    static func read(prompt: String, lineCount: Int, session: LanguageModelSession) async throws -> ModelReceiptReading {
        let schema = try ReceiptAnswerSchema.make(lineCount: lineCount)
        let response = try await session.respond(to: prompt, schema: schema,
                                                 options: GenerationOptions(sampling: .greedy))
        return try ReceiptAnswerSchema.reading(from: response.content)
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
    static func read(prompt: String, lineCount: Int, photo: UIImage,
                     session: LanguageModelSession) async throws -> ModelReceiptReading {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let schema = try ReceiptAnswerSchema.make(lineCount: lineCount)
            let response = try await session.respond(schema: schema, options: GenerationOptions(sampling: .greedy)) {
                prompt
                Attachment(photo)
            }
            return try ReceiptAnswerSchema.reading(from: response.content)
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
    let lineCount: Int
    let photo: UIImage?
    let session: LanguageModelSession

    init(prompt: String, lineCount: Int, photo: UIImage?, session: LanguageModelSession?) {
        self.prompt = prompt
        self.lineCount = lineCount
        self.photo = photo
        self.session = session ?? AppleIntelligenceReader.makeSession()
    }

    func run() async throws -> ModelReceiptReading {
        if let photo = photo {
            return try await AppleIntelligenceReader.read(prompt: prompt, lineCount: lineCount, photo: photo,
                                                          session: session)
        }
        return try await AppleIntelligenceReader.read(prompt: prompt, lineCount: lineCount, session: session)
    }
}
#endif
