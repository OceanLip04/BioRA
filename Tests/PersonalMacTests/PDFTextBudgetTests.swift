import PersonalCore
import XCTest
@testable import PersonalMac

final class PDFTextBudgetTests: XCTestCase {
    func testLocalReaderAndSourceBudgetShareMillionCharacterLimit() throws {
        XCTAssertEqual(PDFLocalReader.maxCharacters, 1_000_000)
        XCTAssertEqual(PDFTextBudget.assistantRequestCharacters, 1_050_000)
        XCTAssertNoThrow(try PDFTextBudget.validate(1_000_000))
        XCTAssertThrowsError(try PDFTextBudget.validate(1_000_001))
    }

    func testAllPageLabelsAndSeparatorsCountTowardExactBoundary() throws {
        let pages = [SciencePDFPage(number: 1, text: "native"), SciencePDFPage(number: 2, text: "ocr", source: .localOCR), SciencePDFPage(number: 3, text: "", source: .unreadable)]
        XCTAssertEqual(try PDFTextBudget.source(pages), "[PAGE 1; PDF TEXT LAYER]\nnative\n\n[PAGE 2; LOCAL OCR]\nocr\n\n[PAGE 3; NO LOCAL TEXT]\n")
        let header = PDFTextBudget.pageText(SciencePDFPage(number: 1, text: ""))
        let full = SciencePDFPage(number: 1, text: String(repeating: "a", count: 1_000_000 - header.count))
        XCTAssertEqual(try PDFTextBudget.source([full]).count, 1_000_000)
        XCTAssertThrowsError(try PDFTextBudget.source([full, SciencePDFPage(number: 2, text: "a")]))
    }

    func testOverflowMessagesFollowLanguageAndDoNotClaimTruncation() {
        for language in [AppLanguage.english, .chinese] {
            XCTAssertThrowsError(try PDFTextBudget.validate(1_000_001, language: language)) { error in
                XCTAssertEqual(AppLanguage.containsHan(error.localizedDescription), language == .chinese)
            }
        }
    }
}
