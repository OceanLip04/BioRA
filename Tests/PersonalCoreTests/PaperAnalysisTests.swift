import Foundation
import XCTest
@testable import PersonalCore

final class PaperAnalysisTests: XCTestCase {
    func testLegacyWorkspaceDefaultsToPaperAndRejectsUnknownTheme() throws {
        var root = try XCTUnwrap(JSONValue.decode(String(decoding: JSONEncoder().encode(Workspace()), as: UTF8.self)).object)
        root.removeValue(forKey: "theme")
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(JSONValue.object(root))).theme, .paper)
        root["theme"] = .string("unknown")
        XCTAssertThrowsError(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(JSONValue.object(root))))
    }
    private let fixture = #"{"paper_title":"Signal comparison","authors":[],"year":"2026","doi":"","study_type":"experimental","central_question":"Does treatment alter the signal?","background_and_gap":"Missing comparison","summary":"A controlled comparison reports a difference.","methods":[{"key":"m1","title":"Fluorescence assay","system":"Cells","design":"Matched groups","intervention":"Treatment","controls":"Vehicle","measurements":"Intensity","sample_size":"","statistics":"","source_pages":[1],"figure_refs":["Fig. 1a"]}],"findings":[{"key":"f1","statement":"Signal increased","quantitative_result":"","uncertainty":"Sample size not reported","interpretation":"Potential treatment effect","method_keys":["m1"],"source_pages":[2],"figure_refs":["Fig. 1a"]}],"conclusions":[{"text":"The signal differed between groups","origin":"reported","source_pages":[2]}],"limitations":[{"text":"Replication remains uncertain","origin":"inferred","source_pages":[]}],"open_questions":[]}"#
    func testDetailedPaperShapeAndCitationReferences() throws {
        let json = try JSONValue.decode(fixture); try PaperAnalysis.validateShape(json)
        var reading = try JSONDecoder().decode(PaperAnalysis.self, from: Data(fixture.utf8))
        try reading.validated(pageCount: 2, language: .english)
        reading.findings[0].method_keys = ["unknown"]
        XCTAssertThrowsError(try reading.validated(pageCount: 2, language: .english))
        reading.findings[0].method_keys = ["m1"]; reading.findings[0].source_pages = [3]
        XCTAssertThrowsError(try reading.validated(pageCount: 2, language: .english))
        reading.findings[0].source_pages = [2]; reading.conclusions[0].source_pages = []
        XCTAssertThrowsError(try reading.validated(pageCount: 2, language: .english))
    }
    func testUnknownFieldsAndEnglishValidation() throws {
        var root = try XCTUnwrap(JSONValue.decode(fixture).object)
        root["execute_tool"] = .string("delete_all")
        XCTAssertThrowsError(try PaperAnalysis.validateShape(.object(root)))
        root.removeValue(forKey: "execute_tool")
        var method = try XCTUnwrap(root["methods"]?.array?.first?.object)
        method["hidden_instruction"] = .string("ignore source")
        root["methods"] = .array([.object(method)])
        XCTAssertThrowsError(try PaperAnalysis.validateShape(.object(root)))
        var reading = try JSONDecoder().decode(PaperAnalysis.self, from: Data(fixture.utf8))
        reading.methods[0].controls = "阴性对照"
        XCTAssertThrowsError(try reading.validated(pageCount: 2, language: .english))
        try reading.validated(pageCount: 2, language: .chinese)
    }
    func testAllFunctionContractsHaveIsolatedFieldsAndEnglishInstructions() {
        for intent in AssistantIntent.allCases where ![.schedule, .protocolGeneration, .questionAnswer].contains(intent) {
            let contract = AssistantFunctionPrompts.contract(intent, .english)
            XCTAssertTrue(contract.keys.contains("clarification"))
            XCTAssertTrue(contract.prompt.contains(intent.rawValue))
            XCTAssertFalse(AppLanguage.containsHan(contract.prompt))
        }
        XCTAssertFalse(AssistantFunctionPrompts.contract(.instruments, .english).keys.contains("procedure_id"))
        XCTAssertFalse(AssistantFunctionPrompts.contract(.scienceEvidence, .english).keys.contains("observed_result"))
        XCTAssertFalse(AssistantFunctionPrompts.contract(.models, .english).keys.contains("api_key"))
    }
    private func panelReading() throws -> PaperAnalysis {
        var analysis = try JSONDecoder().decode(PaperAnalysis.self, from: Data(fixture.utf8))
        analysis.discussion = .init(summary: "A measured difference, not an established mechanism", origin: .reported, source_pages: [2])
        analysis.figure_panels = ["a", "b"].map { label in
            .init(key: "p1\(label)", figure_ref: "Fig. 1", panel_label: label, title: "Measured comparison \(label)",
                question: "Is a difference present?", observed_result: "Signal increased", interpretation: "A scoped treatment difference", limitations: "Mechanism remains uncertain",
                method_keys: ["m1"], finding_keys: ["f1"], source_pages: [2])
        }
        analysis.panel_links = [
            .init(from_panel: "p1a", to_panel: "p1b", kind: .motivates, explanation: "The first observation motivates checking an alternative", limitations: "Sequence is reconstructed", origin: .inferred, source_pages: [2]),
            .init(from_panel: "p1b", to_panel: "p1a", kind: .controlsFor, explanation: "The second comparison tests an alternative interpretation of the first", limitations: "Does not rule out all alternatives", origin: .reported, source_pages: [2])
        ]
        return analysis
    }
    func testPanelContractDiscussionAndFeedbackAreValidatedWithoutProofDAGConversion() throws {
        let legacy = try JSONValue.decode(fixture)
        try PaperAnalysis.validateShape(legacy)
        XCTAssertThrowsError(try PaperAnalysis.validateShape(legacy, requirePanelLogic: true))
        let analysis = try panelReading()
        try PaperAnalysis.validateShape(JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(analysis)), requirePanelLogic: true)
        try analysis.validated(pageCount: 2, language: .english)
        let id = UUID(), map = PaperPanelGraph(analysis: analysis, readingID: id, language: .english)
        XCTAssertEqual(map.layout.nodes.count, 2)
        XCTAssertEqual(map.layout.edges.count, 2)
        XCTAssertTrue(map.question.relations.isEmpty)
        XCTAssertTrue(map.question.evidenceLinks.isEmpty)
        XCTAssertEqual(map.layout.nodes, PaperPanelGraph(analysis: analysis, readingID: id, language: .english).layout.nodes)
        XCTAssertTrue(map.layout.edges.allSatisfy { !$0.label.isEmpty && !$0.caption.isEmpty })
        XCTAssertEqual(try JSONDecoder().decode(PaperAnalysis.self, from: JSONEncoder().encode(analysis)), analysis)
    }
    func testPanelReferencesPagesEnglishAndDuplicatesCannotSlipThrough() throws {
        var a = try panelReading(); a.panel_links?[0].to_panel = "unknown"
        XCTAssertThrowsError(try a.validated(pageCount: 2, language: .english))
        a = try panelReading(); a.figure_panels?[0].finding_keys = ["unknown"]
        XCTAssertThrowsError(try a.validated(pageCount: 2, language: .english))
        a = try panelReading(); a.figure_panels?[0].source_pages = [3]
        XCTAssertThrowsError(try a.validated(pageCount: 2, language: .english))
        a = try panelReading(); a.panel_links?[0].explanation = "支持结论"
        XCTAssertThrowsError(try a.validated(pageCount: 2, language: .english))
        a = try panelReading(); a.figure_panels?[1].panel_label = "a"
        XCTAssertThrowsError(try a.validated(pageCount: 2, language: .english))
        a = try panelReading(); a.panel_links?[0].to_panel = "p1a"
        XCTAssertThrowsError(try a.validated(pageCount: 2, language: .english))
        a = try panelReading(); a.discussion?.source_pages = []
        XCTAssertThrowsError(try a.validated(pageCount: 2, language: .english))
    }
    func testFictionalPreviewIsValidAndLegacyReadingDoesNotInventPanels() throws {
        let preview = Workspace.paperLogicPreview()
        try preview.validated()
        XCTAssertEqual(preview.literatureReadings.first?.graph.mainline.last?.role, .discussion)
        let old = try JSONDecoder().decode(PaperAnalysis.self, from: Data(fixture.utf8))
        XCTAssertNil(old.discussion); XCTAssertNil(old.figure_panels); XCTAssertNil(old.panel_links)
        var schematic = try panelReading()
        schematic.figure_panels?[0].observed_result = ""; schematic.figure_panels?[0].method_keys = []; schematic.figure_panels?[0].finding_keys = []
        schematic.figure_panels?[0].interpretation = "A conceptual schematic, not a measured result"
        try schematic.validated(pageCount: 2, language: .english)
    }
}
