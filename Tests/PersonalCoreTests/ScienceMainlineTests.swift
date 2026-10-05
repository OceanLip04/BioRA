import Foundation
import XCTest
@testable import PersonalCore

final class ScienceMainlineTests: XCTestCase {
    private func forest() -> ScientificQuestion {
        let r1 = ScienceClaim(kind: .conclusion, text: "The treatment alters the measured phenotype")
        let r2 = ScienceClaim(kind: .conclusion, text: "A candidate pathway contributes to the phenotype")
        let intermediate = ScienceClaim(kind: .conclusion, text: "The response persists across independent measurements")
        let local1 = ScienceClaim(kind: .observation, text: "Matched groups differ in readout")
        let local2 = ScienceClaim(kind: .observation, text: "Inhibition attenuates the readout")
        let a1 = AtomicExperiment(title: "Matched comparison", method: "Treated versus control", status: .recorded, observedResult: "A difference was recorded", sourceNote: "Notebook p.1")
        let a2 = AtomicExperiment(title: "Inhibition comparison", method: "Inhibitor versus vehicle", status: .recorded, observedResult: "A lower readout was recorded", sourceNote: "Notebook p.2")
        return ScientificQuestion(title: "How does treatment affect the system?", claims: [r1, r2, intermediate, local1, local2], relations: [
            ScienceRelation(fromClaimID: local1.id, toClaimID: intermediate.id, kind: .supports, explanation: "Matched comparison establishes a measured response"),
            ScienceRelation(fromClaimID: intermediate.id, toClaimID: r1.id, kind: .supports, explanation: "The repeated response informs the scoped phenotype conclusion"),
            ScienceRelation(fromClaimID: local2.id, toClaimID: r2.id, kind: .supports, explanation: "Attenuation informs pathway involvement", limitations: "Off-target effects remain possible"),
            ScienceRelation(fromClaimID: local1.id, toClaimID: r2.id, kind: .supports, explanation: "The original comparison provides the baseline for the pathway test")
        ], atomicExperiments: [a1, a2], evidenceLinks: [
            AtomicEvidenceLink(atomicExperimentID: a1.id, claimID: local1.id, kind: .supports, explanation: "Matched observations establish the local difference"),
            AtomicEvidenceLink(atomicExperimentID: a2.id, claimID: local2.id, kind: .supports, explanation: "Inhibition-versus-vehicle comparison establishes attenuation")
        ], mainline: [
            ScienceMainlineStep(claimID: r1.id, question: "Is an effect present?", motivation: "Establish the effect first", origin: .inferred),
            ScienceMainlineStep(claimID: r2.id, question: "Which pathway contributes?", motivation: "The first result leaves the mechanism unresolved", origin: .inferred)
        ])
    }
    func testMainlineIsSeparateFromMultilevelEvidenceAndCrossTreeLinksPersist() throws {
        let q = forest(); try q.validated(experimentIDs: [])
        let layout = ScienceGraphLayout(question: q, language: .english)
        XCTAssertEqual(layout.nodes.count, 8)
        XCTAssertEqual(Set(layout.nodes.map(\.id)).count, 8) // Shared evidence is drawn once.
        XCTAssertEqual(layout.edges.filter { $0.kind == .progression }.count, 2)
        XCTAssertEqual(layout.edges.filter { $0.kind != .progression }.count, q.relations.count + q.evidenceLinks.count)
        XCTAssertEqual(layout.edges.filter(\.isCrossTree).count, 1)
        XCTAssertFalse(q.relations.contains { $0.fromClaimID == q.mainline[0].claimID && $0.toClaimID == q.mainline[1].claimID })
        let nodes = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0) })
        XCTAssertLessThan(nodes[q.id]!.position.x, nodes[q.mainline[0].claimID]!.position.x)
        XCTAssertLessThan(nodes[q.mainline[0].claimID]!.position.x, nodes[q.mainline[1].claimID]!.position.x)
        XCTAssertEqual(nodes[q.mainline[0].claimID]!.position.y, nodes[q.mainline[1].claimID]!.position.y)
        // The shared local finding has a shorter real support path to the second
        // root; its cross-tree contribution to the first is retained as an edge.
        XCTAssertLessThan(nodes[q.claims[2].id]!.position.y, nodes[q.mainline[0].claimID]!.position.y)
        XCTAssertGreaterThan(nodes[q.atomicExperiments[0].id]!.position.y, nodes[q.mainline[1].claimID]!.position.y)
        XCTAssertGreaterThan(nodes[q.atomicExperiments[1].id]!.position.y, nodes[q.mainline[1].claimID]!.position.y)
        XCTAssertLessThan(nodes[q.mainline[1].claimID]!.position.x - nodes[q.mainline[0].claimID]!.position.x, 400)
        XCTAssertEqual(ScienceArgumentIndex(question: q).evidence(for: q.mainline[1].claimID).count, 2)
        XCTAssertTrue(ScienceArgumentIndex(question: q).unassignedClaimIDs.isEmpty)
        XCTAssertTrue(ScienceArgumentIndex(question: q).unassignedAtomIDs.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(ScientificQuestion.self, from: JSONEncoder().encode(q)), q)
    }
    func testAtomicTestsCannotPointDirectlyToMainlineAndInvalidMainlinesFail() throws {
        var q = forest()
        q.evidenceLinks[0].claimID = q.mainline[0].claimID
        XCTAssertThrowsError(try q.validated(experimentIDs: []))
        q = forest(); q.mainline.append(q.mainline[0])
        XCTAssertThrowsError(try q.validated(experimentIDs: []))
        q = forest(); q.mainline[0].claimID = UUID()
        XCTAssertThrowsError(try q.validated(experimentIDs: []))
    }
    func testLegacyDataDoesNotInventMainlineOrWarrants() throws {
        let q = forest()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(q)) as? [String: Any])
        object.removeValue(forKey: "mainline")
        for key in ["relations", "evidenceLinks"] {
            object[key] = (object[key] as? [[String: Any]])?.map { value in
                var fields = value; fields.removeValue(forKey: "explanation"); fields.removeValue(forKey: "limitations"); return fields
            }
        }
        let old = try JSONDecoder().decode(ScientificQuestion.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.mainline.isEmpty)
        XCTAssertTrue(old.relations.allSatisfy { $0.explanation.isEmpty && $0.limitations.isEmpty })
        XCTAssertTrue(old.evidenceLinks.allSatisfy { $0.explanation.isEmpty && $0.limitations.isEmpty })
        try old.validated(experimentIDs: [])
    }
    func testUnconnectedNodesAreNotArtificiallyAttachedAndMainlineCanCollapse() throws {
        var q = forest()
        let isolated = AtomicExperiment(title: "Future unrelated check")
        q.atomicExperiments.append(isolated)
        try q.validated(experimentIDs: [])
        let index = ScienceArgumentIndex(question: q)
        XCTAssertEqual(index.unassignedAtomIDs, [isolated.id])
        let map = ScienceGraphLayout(question: q)
        XCTAssertTrue(map.nodes.first { $0.id == isolated.id }!.subtitle.contains("尚未关联"))
        let spine = map.mainlineOnly()
        XCTAssertEqual(spine.nodes.count, 3)
        XCTAssertTrue(spine.edges.allSatisfy { $0.kind == .progression })
        XCTAssertLessThan(spine.height, map.height)
    }
    func testDeletingMainlineResultClearsStaleSuccessorRationaleWithoutDeletingEvidence() {
        var q = forest(); let originalCount = q.claims.count
        q.removeClaimFromMainline(q.mainline[0].claimID)
        XCTAssertEqual(q.mainline.count, 1)
        XCTAssertEqual(q.mainline[0].motivation, "")
        XCTAssertEqual(q.claims.count, originalCount)
        XCTAssertFalse(q.relations.isEmpty)
    }
    func testMoreThanThreeConclusionLevelsArePreserved() throws {
        let claims = (0..<12).map { ScienceClaim(kind: .conclusion, text: "Conclusion \($0)") }
        let atom = AtomicExperiment(title: "Measurement", status: .recorded, observedResult: "Recorded observation", sourceNote: "Notebook")
        let q = ScientificQuestion(title: "Deep argument", claims: claims,
            relations: (1..<12).map { ScienceRelation(fromClaimID: claims[$0].id, toClaimID: claims[$0 - 1].id, kind: .supports) },
            atomicExperiments: [atom], evidenceLinks: [AtomicEvidenceLink(atomicExperimentID: atom.id, claimID: claims[11].id, kind: .supports)],
            mainline: [ScienceMainlineStep(claimID: claims[0].id)])
        try q.validated(experimentIDs: [])
        let nodes = ScienceGraphLayout(question: q, language: .english).nodes
        XCTAssertEqual(nodes.first { $0.id == claims[11].id }?.subtitle, "Level 12 conclusion")
        XCTAssertEqual(ScienceArgumentIndex(question: q).evidence(for: claims[0].id).count, 1)
    }
    func testCounterEvidenceDoesNotStealSecondTreeAndLeafEdgesAvoidOtherNodes() throws {
        let q = try XCTUnwrap(Workspace.demo().scientificQuestions.first)
        try q.validated(experimentIDs: Set(Workspace.demo().experiments.map(\.id)))
        let map = ScienceGraphLayout(question: q)
        let first = try XCTUnwrap(map.nodes.first { $0.id == q.mainline[0].claimID })
        let second = try XCTUnwrap(map.nodes.first { $0.id == q.mainline[1].claimID })
        let alternative = try XCTUnwrap(q.claims.first { $0.kind == .hypothesis })
        let alternativeNode = try XCTUnwrap(map.nodes.first { $0.id == alternative.id })
        XCTAssertEqual(alternativeNode.position.x, second.position.x)
        XCTAssertNotEqual(alternativeNode.position.x, first.position.x)
        for edge in q.evidenceLinks {
            let source = try XCTUnwrap(map.nodes.first { $0.id == edge.atomicExperimentID })
            let target = try XCTUnwrap(map.nodes.first { $0.id == edge.claimID })
            XCTAssertGreaterThan(abs(source.position.y - target.position.y), 100)
            XCTAssertLessThanOrEqual(abs(source.position.x - target.position.x), 132)
        }
        XCTAssertTrue(map.edges.contains { $0.kind == .contradicts && $0.isCrossTree })
    }
    func testDiscussionRoleRoundTripsAndMustBeUniqueFinalStep() throws {
        var q = forest()
        q.mainline[1].role = .discussion
        try q.validated(experimentIDs: [])
        let decoded = try JSONDecoder().decode(ScientificQuestion.self, from: JSONEncoder().encode(q))
        XCTAssertEqual(decoded.mainline.last?.role, .discussion)
        XCTAssertTrue(ScienceGraphLayout(question: q, language: .english).nodes.contains { $0.subtitle.contains("DISCUSSION") })
        q.mainline[0].role = .discussion
        XCTAssertThrowsError(try q.validated(experimentIDs: []))
        q.mainline[1].role = .result
        XCTAssertThrowsError(try q.validated(experimentIDs: []))
        let legacy = #"{"claimID":"00000000-0000-4000-8000-000000000001","question":"Q","motivation":"M","origin":"inferred"}"#
        XCTAssertEqual(try JSONDecoder().decode(ScienceMainlineStep.self, from: Data(legacy.utf8)).role, .result)
    }
    func testFourBroadTreesAlternateAndDoNotOverlapCards() throws {
        var q = ScientificQuestion(title: "Compact forest")
        for tree in 0..<4 {
            let root = ScienceClaim(kind: .conclusion, text: "Result \(tree)")
            q.claims.append(root); q.mainline.append(ScienceMainlineStep(claimID: root.id))
            for leaf in 0..<3 {
                let local = ScienceClaim(kind: .observation, text: "Local \(tree)-\(leaf)")
                q.claims.append(local)
                q.relations.append(ScienceRelation(fromClaimID: local.id, toClaimID: root.id, kind: .supports))
            }
        }
        try q.validated(experimentIDs: [])
        let map = ScienceGraphLayout(question: q)
        let nodes = Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0) })
        for (index, step) in q.mainline.enumerated() {
            let root = try XCTUnwrap(nodes[step.claimID])
            for edge in q.relations where edge.toClaimID == root.id {
                let leaf = try XCTUnwrap(nodes[edge.fromClaimID])
                if index.isMultiple(of: 2) { XCTAssertLessThan(leaf.position.y, root.position.y) }
                else { XCTAssertGreaterThan(leaf.position.y, root.position.y) }
            }
        }
        for a in map.nodes.indices {
            for b in map.nodes.indices where b > a {
                XCTAssertTrue(abs(map.nodes[a].position.x - map.nodes[b].position.x) >= 232
                    || abs(map.nodes[a].position.y - map.nodes[b].position.y) >= 100, "Cards overlap")
            }
        }
        XCTAssertLessThan(map.width, 4 * 820) // Opposite-side trees reuse horizontal space.
    }
}
