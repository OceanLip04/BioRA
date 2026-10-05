import Foundation
import PersonalCore
import XCTest
@testable import PersonalMac

final class PanelLogicSupplementTests: XCTestCase {
    private func reading() -> LiteratureReading {
        var item = Workspace.paperLogicPreview().literatureReadings[0]
        item.analysis?.figure_panels = nil; item.analysis?.panel_links = nil
        return item
    }
    private func exchange(_ language: AppLanguage = .english, reading: LiteratureReading? = nil) throws -> PanelLogicSupplementExchange {
        try PanelLogicSupplementExchange(reading: reading ?? self.reading(), language: language, pageCount: 2, source: "[PAGE 1; PDF TEXT LAYER]\nFictional figure captions, not scientific evidence.")
    }
    private func json(_ exchange: PanelLogicSupplementExchange) throws -> JSONValue {
        let original = Workspace.paperLogicPreview().literatureReadings[0].analysis!
        func encode<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
        return .object([
            "exchange_id": .string(exchange.id.uuidString), "reading_id": .string(exchange.reading.id.uuidString),
            "source_fingerprint": .string(exchange.reading.fingerprint), "methods": .array([]), "findings": .array([]),
            "figure_panels": try encode(original.figure_panels!), "panel_links": try encode(original.panel_links!)
        ])
    }
    private func change(_ root: JSONValue, _ key: String, _ value: JSONValue) -> JSONValue {
        var fields = root.object!; fields[key] = value; return .object(fields)
    }
    func testDedicatedPromptIsBilingualFrozenAndOnlyIncludesSelectedPaper() throws {
        let en = try exchange(), zh = try exchange(.chinese)
        let prompt = en.prompt
        XCTAssertTrue(prompt.contains("Supplement ONLY")); XCTAssertTrue(prompt.contains("Copy the three identity fields literally"))
        XCTAssertFalse(AppLanguage.containsHan(PanelLogicSupplementPrompt.content(.english)))
        XCTAssertTrue(zh.prompt.contains("仅补充"))
        XCTAssertTrue(prompt.contains("Fictional figure captions")); XCTAssertFalse(prompt.contains("Authorization"))
        let payload = try JSONValue.decode(prompt.components(separatedBy: "SOURCE_DATA (JSON):\n").last!)
        XCTAssertEqual(payload["exchange_id"].string, en.id.uuidString)
        XCTAssertEqual(payload["reading_id"].string, en.reading.id.uuidString)
        XCTAssertEqual(payload["existing_reading"]["summary"].string, en.base.summary)
    }
    func testValidSupplementPreservesReadingAndAcceptsGroundedFeedback() throws {
        let item = try exchange(), body = try json(item).text()
        for reply in [body, "```json\n" + body + "\n```"] {
            let result = try item.parse(reply)
            XCTAssertEqual(result.figure_panels?.count, 4); XCTAssertEqual(result.panel_links?.count, 4)
            var expected = item.base; expected.figure_panels = result.figure_panels; expected.panel_links = result.panel_links
            XCTAssertEqual(result, expected)
            XCTAssertNoThrow(try item.validateApplication(result))
        }
    }
    func testWrongPaperStaleExchangeUnknownFieldsAndTruncatedRepliesFail() throws {
        let item = try exchange(), base = try json(item)
        for key in ["exchange_id", "reading_id", "source_fingerprint"] {
            XCTAssertThrowsError(try item.parse(change(base, key, .string("another" )).text()))
        }
        XCTAssertThrowsError(try item.parse(change(base, "summary", .string("overwrite" )).text()))
        XCTAssertThrowsError(try item.parse(String(try base.text().dropLast())))
        XCTAssertThrowsError(try item.parse("```json\n" + base.text()))
        XCTAssertThrowsError(try item.parse(String(repeating: "a", count: ManualPaperExchange.maxResponseBytes + 1)))
    }
    func testBadPanelEndpointsReferencesPagesAndGenericEmptyResultsFail() throws {
        let item = try exchange(), base = try json(item)
        var panels = base["figure_panels"].array!
        panels[0] = change(panels[0], "finding_keys", .array([.string("invented_finding")]))
        XCTAssertThrowsError(try item.parse(change(base, "figure_panels", .array(panels)).text()))
        panels = base["figure_panels"].array!; panels[0] = change(panels[0], "source_pages", .array([.number(3)]))
        XCTAssertThrowsError(try item.parse(change(base, "figure_panels", .array(panels)).text()))
        panels = base["figure_panels"].array!; panels[0] = change(panels[0], "extra", .string("unknown"))
        XCTAssertThrowsError(try item.parse(change(base, "figure_panels", .array(panels)).text()))
        var links = base["panel_links"].array!; links[0] = change(links[0], "to_panel", .string("missing"))
        XCTAssertThrowsError(try item.parse(change(base, "panel_links", .array(links)).text()))
        XCTAssertThrowsError(try item.parse(change(change(base, "figure_panels", .array([])), "panel_links", .array([])).text()))
    }
    func testNecessaryAdditionalMethodsAndFindingsAreAppendedNotReplaced() throws {
        let item = try exchange(), base = try json(item)
        var method = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(item.base.methods[0])).object!
        var finding = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(item.base.findings[0])).object!
        method["key"] = .string("new_m"); finding["key"] = .string("new_f"); finding["method_keys"] = .array([.string("new_m")])
        let value = change(change(base, "methods", .array([.object(method)])), "findings", .array([.object(finding)]))
        let result = try item.parse(value.text())
        XCTAssertEqual(result.methods.first, item.base.methods.first); XCTAssertEqual(result.findings.first, item.base.findings.first)
        XCTAssertEqual(result.methods.last?.key, "new_m"); XCTAssertEqual(result.findings.last?.key, "new_f")
        XCTAssertThrowsError(try item.parse(change(base, "methods", .array([try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(item.base.methods[0]))])).text()))
        var modified = result; modified.summary = "An impermissible replacement"
        XCTAssertThrowsError(try item.validateApplication(modified))
        modified = result; modified.methods[0].design = "Changed old method"
        XCTAssertThrowsError(try item.validateApplication(modified))
    }
    func testNewEnglishProseIsCheckedWithoutRewritingOldChineseReading() throws {
        var record = reading(); record.analysis?.summary = "已有中文记录"; record.analysis?.methods[0].title = "已有方法"
        let item = try exchange(reading: record), base = try json(item)
        XCTAssertEqual(try item.parse(base.text()).summary, "已有中文记录")
        var panels = base["figure_panels"].array!; panels[0] = change(panels[0], "title", .string("新生成中文"))
        XCTAssertThrowsError(try item.parse(change(base, "figure_panels", .array(panels)).text()))
    }
    func testLegacyGraphWithoutDetailedReadingCanReceiveAnExplicitPartialSupplement() throws {
        var record = reading(); record.analysis = nil
        let item = try exchange(reading: record)
        var base = try json(item).object!
        let reference = Workspace.paperLogicPreview().literatureReadings[0].analysis!
        base["methods"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(reference.methods))
        base["findings"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(reference.findings))
        let result = try item.parse(JSONValue.object(base).text())
        XCTAssertTrue(result.summary.contains("supplement only")); XCTAssertEqual(result.study_type, .unclear)
        XCTAssertNil(result.discussion); XCTAssertTrue(result.authors.isEmpty)
        XCTAssertEqual(result.figure_panels?.count, 4)
    }
    func testSourcePageLimitsExistingPanelsAndRepairPrompt() throws {
        let record = reading()
        XCTAssertThrowsError(try PanelLogicSupplementExchange(reading: record, language: .english, pageCount: 3, source: ""))
        XCTAssertThrowsError(try PanelLogicSupplementExchange(reading: record, language: .english, pageCount: 2, source: String(repeating: "a", count: PDFTextBudget.maxCharacters + 1)))
        XCTAssertThrowsError(try exchange(reading: Workspace.paperLogicPreview().literatureReadings[0]))
        let item = try exchange()
        let repair = try item.repairPrompt(response: "invalid", error: "bad endpoint")
        XCTAssertTrue(repair.hasPrefix(item.prompt)); XCTAssertTrue(repair.contains("REPAIR_DATA (JSON)"))
        XCTAssertTrue(repair.contains("bad endpoint"))
    }

    @MainActor func testReviewedSupplementPersistsWithoutChangingGraphOtherReadingOrCalendar() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/TestWorkspaces/panel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalStore(directory: directory, demo: false)
        let first = reading(), second = reading()
        try store.commit { $0.language = .english; $0.literatureReadings = [first, second] }
        let before = store.workspace
        let item = try exchange(reading: first), supplement = try item.parse(json(item).text())
        // Copy and parse never persist anything.
        XCTAssertEqual(store.workspace, before)
        try store.applyPanelLogicSupplement(item, analysis: supplement)
        var expected = before; expected.literatureReadings[0].analysis = supplement; expected.revision += 1
        XCTAssertEqual(store.workspace, expected)
        XCTAssertEqual(try store.file.load(), expected)
        let saved = store.workspace
        XCTAssertThrowsError(try store.applyPanelLogicSupplement(item, analysis: supplement))
        XCTAssertEqual(store.workspace, saved)
    }

    @MainActor func testChangedSourceLanguageAndReadonlyWorkspaceRejectSavingWithoutWrites() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/TestWorkspaces/panel-conflict-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalStore(directory: directory, demo: false), record = reading()
        try store.commit { $0.language = .english; $0.literatureReadings = [record] }
        let item = try exchange(reading: record), supplement = try item.parse(json(item).text())
        try store.commit { $0.literatureReadings[0].analysis?.summary = "Edited meanwhile" }
        var before = store.workspace
        XCTAssertThrowsError(try store.applyPanelLogicSupplement(item, analysis: supplement)); XCTAssertEqual(store.workspace, before)
        let current = try exchange(reading: store.workspace.literatureReadings[0])
        try store.setLanguage(.chinese); before = store.workspace
        XCTAssertThrowsError(try store.applyPanelLogicSupplement(current, analysis: supplement)); XCTAssertEqual(store.workspace, before)
        let protected = PersonalStore(previewDirectory: directory, previewWorkspace: before)
        let chinese = try exchange(.chinese, reading: before.literatureReadings[0])
        let result = try chinese.parse(json(chinese).text())
        XCTAssertThrowsError(try protected.applyPanelLogicSupplement(chinese, analysis: result))
        XCTAssertEqual(protected.workspace, before)
    }
}
