import Foundation
import XCTest
@testable import PersonalCore

final class ProtocolDocumentTests: XCTestCase {
    private func document() -> ProtocolContent {
        var value = ProtocolContent(blocks: [ProtocolBlock(title: "溶液制备", subblocks: [ProtocolSubblock(title: "配制工作液", steps: [ProtocolStep(title: "稀释缓冲液", minutes: 5)])])])
        value.objective = "获得实验所需的缓冲工作液。"
        value.materials = [ProtocolMaterial(name: "缓冲液", specification: "浓度待确认", quantity: "待确认"), ProtocolMaterial(name: "移液器", category: .equipment, quantity: "1 支")]
        value.principles = ["稀释改变溶液浓度。"]
        value.precautions = ["先确认目标浓度及器具兼容性。"]
        value.renumber(); return value
    }
    func testFivePartsRoundTripAndExecutionContainsOnlyOperations() throws {
        let value = document(); try value.validatedGeneratedDocument()
        let decoded = try JSONDecoder().decode(ProtocolContent.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(try decoded.executionItems().map(\.step.title), ["稀释缓冲液"])
        XCTAssertEqual(try decoded.executionItems().reduce(0) { $0 + $1.step.durationMinutes }, 5)
    }
    func testLegacyV3DefaultsWithoutChangingTree() throws {
        let value = document()
        var json = try XCTUnwrap(JSONValue.decode(String(decoding: JSONEncoder().encode(value), as: UTF8.self)).object)
        for key in ["objective", "materials", "principles", "precautions"] { json.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(ProtocolContent.self, from: JSONEncoder().encode(JSONValue.object(json)))
        try old.validated()
        XCTAssertEqual(old.blocks, value.blocks); XCTAssertEqual(old.atomicSteps, value.atomicSteps)
        XCTAssertEqual(old.objective, ""); XCTAssertTrue(old.materials.isEmpty); XCTAssertTrue(old.principles.isEmpty); XCTAssertTrue(old.precautions.isEmpty)
        XCTAssertThrowsError(try old.validatedGeneratedDocument())
    }
    func testMaterialAndSupportingSectionsCannotMasqueradeAsOperations() throws {
        var value = document()
        value.blocks[0].subblocks[0].steps[0].title = "缓冲液"
        value.blocks[0].subblocks[0].steps[0].description = "10 mL"
        XCTAssertThrowsError(try value.validatedGeneratedDocument())
        value = document(); value.blocks[0].title = "实验材料"
        // Preserve loading historical data; apply semantic separation only to newly generated outputs.
        try value.validated(); XCTAssertThrowsError(try value.validatedGeneratedDocument())
        value = document(); value.blocks[0].subblocks[0].title = "注意事项"
        XCTAssertThrowsError(try value.validatedGeneratedDocument())
        value = document(); value.blocks[0].subblocks[0].steps[0].title = "配制缓冲液"
        try value.validatedGeneratedDocument()
    }
    func testTypedPartsRejectWrongTypesAndInvalidMaterialRecords() throws {
        let value = document()
        var json = try XCTUnwrap(JSONValue.decode(String(decoding: JSONEncoder().encode(value), as: UTF8.self)).object)
        json["principles"] = .array([.object(["text": .string("错误类型")])])
        XCTAssertThrowsError(try JSONDecoder().decode(ProtocolContent.self, from: JSONEncoder().encode(JSONValue.object(json))))
        var duplicate = value; duplicate.materials.append(value.materials[0]); XCTAssertThrowsError(try duplicate.validated())
        var empty = value; empty.materials[0].name = "  "; XCTAssertThrowsError(try empty.validated())
        var blank = value; blank.precautions = [""]; XCTAssertThrowsError(try blank.validated())
    }
    func testWorkspaceChecklistRoundTripAndLegacyDefault() throws {
        var workspace = Workspace()
        let procedure = Procedure(name: "示例", content: document())
        workspace.procedures = [procedure]
        let version = procedure.currentVersion
        workspace.materialPreparation[version.id.uuidString] = [version.content.materials[0].id]
        try workspace.validated()
        let data = try JSONEncoder().encode(workspace)
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: data), workspace)
        var json = try XCTUnwrap(JSONValue.decode(String(decoding: data, as: UTF8.self)).object)
        json.removeValue(forKey: "materialPreparation")
        XCTAssertTrue(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(JSONValue.object(json))).materialPreparation.isEmpty)
    }
    func testDocumentJSONExchangePreservesAllParts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("protocol-document-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let value = document(), url = dir.appendingPathComponent("protocol.json")
        try JSONEncoder().encode(value).write(to: url)
        XCTAssertEqual(try ProtocolExchange.read(url), value)
    }
}
