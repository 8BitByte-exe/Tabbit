import XCTest
@testable import Tabbit

/// Reading a receipt in its own language and alphabet: stray characters from another
/// alphabet are misreads, whole words and lines in another language are not.
final class ReceiptAlphabetTests: XCTestCase {

    private let english = ReceiptAlphabet(script: .latin, language: "en")

    // MARK: - Stray characters

    func testStrayCharactersOnAnEnglishReceipt() {
        // From the Best Buy scan.
        XCTAssertEqual(english.normalized("TAX HST 13.00名 of $59.98"), "TAX HST 13.00 of $59.98")
        XCTAssertEqual(english.normalized("$24.9îŚ"), "$24.9iS")
        XCTAssertEqual(english.normalized("BUYă"), "BUYA")
        XCTAssertEqual(english.normalized("T-3681Í"), "T-3681I")
        // A Cyrillic "С" that looks like a C.
        XCTAssertEqual(english.normalized("СOFFEE 2.50"), "COFFEE 2.50")
        XCTAssertEqual(english.normalized("VAL&： 12"), "VAL&: 12")
    }

    func testRealWordsKeepTheirLetters() {
        XCTAssertEqual(english.normalized("Crème Brûlée 9.00"), "Crème Brûlée 9.00")
        XCTAssertEqual(english.normalized("CAFÉ CENTRAL"), "CAFÉ CENTRAL")
        // A Greek word on an English receipt is a Greek word.
        XCTAssertEqual(english.normalized("ΦΕΤΑ 4.99"), "ΦΕΤΑ 4.99")
        XCTAssertEqual(english.normalized("MILK 3.49"), "MILK 3.49")
    }

    func testLettersTheReceiptsLanguageWritesAreKept() {
        let french = ReceiptAlphabet(script: .latin, language: "fr")
        XCTAssertEqual(french.normalized("CRÈME 3,50"), "CRÈME 3,50")
        XCTAssertEqual(french.normalized("Thank you for shopping"), "Thank you for shopping")
        // "ă" isn't French: next to digits it's a misread "a".
        XCTAssertEqual(french.normalized("2ă"), "2a")
    }

    func testAGreekReceiptReadsStrayLatinLettersAsGreek() {
        let greek = ReceiptAlphabet(script: .greek, language: "el")
        // A Latin "A" at the end of ΓΑΛΑ (milk).
        XCTAssertEqual(greek.normalized("ΓΑΛA 1,20"), "ΓΑΛΑ 1,20")
        // An English line on a Greek receipt stays English.
        XCTAssertEqual(greek.normalized("THANK YOU"), "THANK YOU")
    }

    // MARK: - Finding the language

    func testTheReceiptsLanguageAndScript() {
        let receipt = ReceiptAlphabet(texts: [
            "Open more this holiday season.", "Need help? Visit our store", "NO SIGNATURE REQUIRED",
            "device returns please ask an in-store advisor", "SUBTOTAL $59.98",
        ])
        XCTAssertEqual(receipt.script, .latin)
        XCTAssertEqual(receipt.language, "en")

        let greek = ReceiptAlphabet(texts: [
            "ΑΠΟΔΕΙΞΗ ΛΙΑΝΙΚΗΣ ΠΩΛΗΣΗΣ", "Ευχαριστούμε για την προτίμησή σας", "ΣΥΝΟΛΟ 12,40", "ΜΕΤΡΗΤΑ 20,00",
        ])
        XCTAssertEqual(greek.script, .greek)
        XCTAssertEqual(greek.language, "el")
    }

    func testTheBestBuyReceiptReadsItsSecondPrice() throws {
        let scan = try Fixtures.scan(named: "bestbuy-two-items")
        let texts = LineGrouper.lines(from: scan).map { line in line.text }
        XCTAssertFalse(texts.joined().contains("名"))
        XCTAssertTrue(texts.contains { text in text.contains("ELITE") && text.contains("$24.9") })
    }

    // MARK: - Reading again in another language

    func testASpanishReceiptIsReadAgainInSpanish() {
        let texts = ["Gracias por su compra", "Vuelva pronto, le esperamos", "TOTAL A PAGAR 12,50", "Efectivo y cambio"]
        let retry = ReaderLanguages.retry(texts: texts, confidences: [0.9, 0.9, 0.9, 0.9],
                                          used: ["en"], supported: ["en", "es", "fr"])
        XCTAssertEqual(retry, .languages(["es", "en"]))
    }

    func testAnEnglishReceiptIsReadOnce() {
        let texts = ["Thank you for shopping with us", "Please come again soon", "TOTAL 12.50", "Cash and change"]
        XCTAssertNil(ReaderLanguages.retry(texts: texts, confidences: [0.9, 0.9, 0.9, 0.9],
                                           used: ["en"], supported: ["en", "es"]))
    }

    func testAHardlyReadablePageIsReadAgainDetectingTheLanguage() {
        let retry = ReaderLanguages.retry(texts: ["ZXQ", "4.50", "PRQW"], confidences: [0.3, 0.4, 0.2],
                                          used: ["en"], supported: ["en", "el"])
        XCTAssertEqual(retry, .automatic)
        XCTAssertTrue(ReaderLanguages.prefersSecond(first: [0.3, 0.4], second: [0.8, 0.9], plan: .automatic))
        XCTAssertFalse(ReaderLanguages.prefersSecond(first: [0.8, 0.9], second: [0.7, 0.8], plan: .automatic))
        XCTAssertTrue(ReaderLanguages.prefersSecond(first: [0.9], second: [0.88], plan: .languages(["es"])))
    }

    func testThePromptNamesTheReceiptsLanguage() {
        XCTAssertEqual(ReceiptPrompt.languageNote("fr"), "This receipt is in French.")
        XCTAssertNil(ReceiptPrompt.languageNote(nil))
    }
}
