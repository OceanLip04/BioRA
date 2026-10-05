import Foundation
import XCTest
@testable import PersonalCore

final class ScienceQuestionTests: XCTestCase {
    func testLegacyWorkspaceWithoutQuestionsLoadsAndRoundTrips() throws {
        let original = Workspace()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "scientificQuestions")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Workspace.self, from: legacy)
        XCTAssertTrue(decoded.scientificQuestions.isEmpty)
        try decoded.validated()
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(decoded)), decoded)
    }

    func testQuestionGraphAndExperimentReferencePersist() throws {
        var workspace = Workspace()
        let procedure = Procedure(name: "对照实验", steps: [ProcedureStep(title: "记录", minutes: 10)])
        let experiment = Experiment(name: "第 1 次重复", procedureID: procedure.id)
        workspace.procedures = [procedure]; workspace.experiments = [experiment]
        let hypothesis = ScienceClaim(kind: .hypothesis, text: "处理可能改变读数", confidence: 0.4)
        let observation = ScienceClaim(kind: .observation, text: "本次记录了更高读数", confidence: 0.8, sourceNote: "原始笔记待复核", experimentIDs: [experiment.id])
        let relation = ScienceRelation(fromClaimID: observation.id, toClaimID: hypothesis.id, kind: .supports)
        workspace.scientificQuestions = [ScientificQuestion(title: "处理是否影响读数？", claims: [hypothesis, observation], relations: [relation])]
        try workspace.validated()
        let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        XCTAssertEqual(restored.scientificQuestions, workspace.scientificQuestions)
        try restored.validated()
    }

    func testDanglingAndSelfRelationsFailClosed() throws {
        let claim = ScienceClaim(kind: .assertion, text: "观察 A")
        var question = ScientificQuestion(title: "问题", claims: [claim], relations: [ScienceRelation(fromClaimID: claim.id, toClaimID: UUID(), kind: .supports)])
        XCTAssertThrowsError(try question.validated(experimentIDs: []))
        question.relations = [ScienceRelation(fromClaimID: claim.id, toClaimID: claim.id, kind: .contradicts)]
        XCTAssertThrowsError(try question.validated(experimentIDs: []))
        question.relations = []; question.claims[0].experimentIDs = [UUID()]
        XCTAssertThrowsError(try question.validated(experimentIDs: []))
    }

    func testPreviousQuestionFormatOpensWithoutNewGraphFields() throws {
        let old = ScientificQuestion(title: "旧问题", claims: [ScienceClaim(kind: .conclusion, text: "旧结论")])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "atomicExperiments")
        object.removeValue(forKey: "evidenceLinks")
        object.removeValue(forKey: "graphPositions")
        let decoded = try JSONDecoder().decode(ScientificQuestion.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.claims, old.claims)
        XCTAssertTrue(decoded.atomicExperiments.isEmpty)
        XCTAssertTrue(decoded.evidenceLinks.isEmpty)
        XCTAssertTrue(decoded.graphPositions.isEmpty)
        try decoded.validated(experimentIDs: [])
    }

    func testManyAtomicExperimentsCanSupportOneConclusionAndChainToAnother() throws {
        let observation = ScienceClaim(kind: .observation, text: "三次重复均记录变化")
        let conclusion = ScienceClaim(kind: .conclusion, text: "处理后出现稳定变化")
        let atoms = (1...3).map { index in
            AtomicExperiment(title: "第 \(index) 次独立重复", method: "同一测量方案", status: .recorded,
                observedResult: "读数已记录", sourceNote: "笔记 \(index)")
        }
        let links = atoms.map { AtomicEvidenceLink(atomicExperimentID: $0.id, claimID: observation.id, kind: .supports) }
        let relation = ScienceRelation(fromClaimID: observation.id, toClaimID: conclusion.id, kind: .supports)
        var question = ScientificQuestion(title: "变化是否可重复？", claims: [conclusion, observation], relations: [relation],
            atomicExperiments: atoms, evidenceLinks: links)
        try question.validated(experimentIDs: [])
        let layout = ScienceGraphLayout(question: question)
        XCTAssertEqual(layout.nodes.count, 6)
        XCTAssertEqual(layout.edges.count, 5) // Three experiments, one claim link, one conclusion to question.
        let positions = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.position) })
        XCTAssertLessThan(positions[question.id]!.x, positions[conclusion.id]!.x)
        XCTAssertLessThan(positions[conclusion.id]!.x, positions[observation.id]!.x)
        XCTAssertLessThan(positions[observation.id]!.x, positions[atoms[0].id]!.x)
        question.graphPositions[atoms[0].id.uuidString] = ScienceGraphPoint(x: 900, y: 220)
        try question.validated(experimentIDs: [])
        XCTAssertEqual(ScienceGraphLayout(question: question).nodes.first { $0.id == atoms[0].id }?.position, ScienceGraphPoint(x: 900, y: 220))
        XCTAssertEqual(try JSONDecoder().decode(ScientificQuestion.self, from: JSONEncoder().encode(question)), question)
    }

    func testPlannedExperimentsCannotPretendToBeEvidence() throws {
        let claim = ScienceClaim(kind: .conclusion, text: "待验证结论")
        var atom = AtomicExperiment(title: "计划中的检验")
        var question = ScientificQuestion(title: "问题", claims: [claim], atomicExperiments: [atom],
            evidenceLinks: [AtomicEvidenceLink(atomicExperimentID: atom.id, claimID: claim.id, kind: .supports)])
        XCTAssertThrowsError(try question.validated(experimentIDs: []))
        atom.status = .recorded; atom.observedResult = "有结果，但没有出处"
        question.atomicExperiments = [atom]
        XCTAssertThrowsError(try question.validated(experimentIDs: []))
        atom.sourceNote = "实验记录本第 4 页"
        question.atomicExperiments = [atom]
        try question.validated(experimentIDs: [])
    }

    func testClaimCyclesAndDanglingEvidenceAreRejected() throws {
        let a = ScienceClaim(kind: .assertion, text: "A"), b = ScienceClaim(kind: .conclusion, text: "B")
        var question = ScientificQuestion(title: "问题", claims: [a, b], relations: [
            ScienceRelation(fromClaimID: a.id, toClaimID: b.id, kind: .supports),
            ScienceRelation(fromClaimID: b.id, toClaimID: a.id, kind: .supports)
        ])
        XCTAssertThrowsError(try question.validated(experimentIDs: []))
        question.relations = []
        question.evidenceLinks = [AtomicEvidenceLink(atomicExperimentID: UUID(), claimID: a.id, kind: .supports)]
        XCTAssertThrowsError(try question.validated(experimentIDs: []))
    }

    func testLargeMapWrapsNodesInsteadOfGrowingInfinitelyTall() throws {
        let atoms = (0..<100).map { AtomicExperiment(title: "检验 \($0)") }
        let question = ScientificQuestion(title: "规模测试", atomicExperiments: atoms)
        try question.validated(experimentIDs: [])
        let layout = ScienceGraphLayout(question: question)
        XCTAssertEqual(layout.nodes.count, 101)
        XCTAssertLessThan(layout.height, 3000)
        XCTAssertGreaterThan(layout.width, 1000)
    }
}
