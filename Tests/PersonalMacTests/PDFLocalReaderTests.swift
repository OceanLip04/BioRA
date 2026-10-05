import AppKit
import CoreText
import XCTest
import PersonalCore
@testable import PersonalMac

final class PDFLocalReaderTests: XCTestCase {
    func testImagePageSelectionIsBoundedAndKeepsOrder() throws {
        XCTAssertEqual(try PDFLocalReader.pageNumbers("3,1-2,3", pageCount: 5), [3, 1, 2])
        XCTAssertThrowsError(try PDFLocalReader.pageNumbers("0", pageCount: 5))
        XCTAssertThrowsError(try PDFLocalReader.pageNumbers("5-2", pageCount: 5))
        XCTAssertThrowsError(try PDFLocalReader.pageNumbers("1-5", pageCount: 5))
    }

    func testLegacyModelDoesNotGainVisionCapability() throws {
        let model = ModelProfile(connectionID: UUID(), name: "Text model", model: "text-only")
        var object = try XCTUnwrap(JSONValue.decode(String(decoding: JSONEncoder().encode(model), as: UTF8.self)).object)
        object.removeValue(forKey: "supportsVision")
        let restored = try JSONDecoder().decode(ModelProfile.self, from: JSONEncoder().encode(JSONValue.object(object)))
        XCTAssertFalse(restored.supportsVision)
    }

    func testTextMessagesKeepStringContentAndImageMessagesUseParts() throws {
        let plain = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(WireMessage(role: "user", content: "hello")))
        XCTAssertEqual(plain["content"].string, "hello")
        let visual = WireMessage(role: "user", content: "hello", parts: [.text("hello"), .imageURL("data:image/jpeg;base64,/9j/")])
        let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(visual))
        XCTAssertEqual(encoded["content"].array?.count, 2)
        XCTAssertEqual(encoded["content"].array?.last?["image_url"]["url"].string, "data:image/jpeg;base64,/9j/")
        let restored = try JSONDecoder().decode(WireMessage.self, from: JSONEncoder().encode(visual))
        XCTAssertEqual(restored.parts, visual.parts)
    }

    func testNativePDFTextAndPageRenderingStayLocal() throws {
        let mutable = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: mutable as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 400, height: 500)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 35, y: 430)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Cell fluorescence was measured.", attributes: [
            .font: NSFont.systemFont(ofSize: 19)
        ]))
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        let data = mutable as Data
        let result = try PDFLocalReader.read(data)
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertTrue(result.pages[0].text.contains("fluorescence"))
        XCTAssertEqual(result.pages[0].source, .textLayer)
        let screenshot = try XCTUnwrap(PDFLocalReader.screenshots([1], from: data).first)
        XCTAssertEqual(screenshot.number, 1)
        XCTAssertTrue(screenshot.jpeg.starts(with: [0xFF, 0xD8]))
        XCTAssertNotNil(NSBitmapImageRep(data: screenshot.jpeg))
    }

    func testImageOnlyPDFUsesLocalVisionOCR() throws {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 1400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(NSColor.white.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: 1200, height: 1400))
        bitmap.setFillColor(NSColor.black.cgColor)
        bitmap.textPosition = CGPoint(x: 90, y: 800)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "RNA EXTRACTION RESULT", attributes: [
            .font: NSFont.systemFont(ofSize: 66)
        ])), bitmap)
        let image = try XCTUnwrap(bitmap.makeImage())
        let mutable = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: mutable as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 600, height: 700)
        let pdf = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        pdf.beginPDFPage(nil)
        pdf.draw(image, in: box)
        pdf.endPDFPage()
        pdf.closePDF()
        let result = try PDFLocalReader.read(mutable as Data)
        XCTAssertEqual(result.ocrPages, [1])
        XCTAssertTrue(result.pages[0].text.uppercased().contains("RNA"))
    }
}
