import Foundation
import XCTest
@testable import PersonalCore

final class SciencePDFImportTests: XCTestCase {
    func testOldWorkspaceWithoutLanguageDefaultsToChinese() throws {
        let original = Workspace()
        var object = try XCTUnwrap(JSONValue.decode(String(decoding: JSONEncoder().encode(original), as: UTF8.self)).object)
        object.removeValue(forKey: "language")
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(JSONValue.object(object)))
        XCTAssertEqual(decoded.language, .chinese)
        XCTAssertEqual(decoded.models, original.models)
    }
    private func draft(_ atomStatus: String = "recorded", sourcePage: String = "1", links: String = "[{\"atom_key\":\"test_a\",\"claim_key\":\"observation\",\"kind\":\"supports\"}]") throws -> SciencePDFImport {
        let json = """
        {"title":"Does treatment alter fluorescence?","detail":"One paper-reported comparison; human review required.",
         "claims":[{"key":"observation","kind":"observation","text":"Signal differed between groups.","source_page":1},
                   {"key":"conclusion","kind":"conclusion","text":"Treatment may affect fluorescence.","source_page":1}],
         "atomic_experiments":[{"key":"test_a","title":"Group comparison","method":"Compare images under matched conditions","status":"\(atomStatus)","observed_result":"\(atomStatus == "recorded" ? "The paper reports a higher signal in one group." : "")","source_page":\(sourcePage)}],
         "evidence_links":\(links),
         "claim_links":[{"from_key":"observation","to_key":"conclusion","kind":"supports"}]}
        """
        return try JSONDecoder().decode(SciencePDFImport.self, from: Data(json.utf8))
    }

    func testPaperResultBecomesTraceableGraphWithoutPretendingToBeOwnExperiment() throws {
        let output = try draft()
        let question = try output.materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc123", language: .english)
        XCTAssertEqual(question.atomicExperiments.count, 1)
        XCTAssertEqual(question.evidenceLinks.count, 1)
        XCTAssertEqual(question.relations.count, 1)
        XCTAssertNil(question.atomicExperiments[0].experimentID)
        XCTAssertTrue(question.atomicExperiments[0].sourceNote.contains("not a record of your own experiment"))
        XCTAssertTrue(question.atomicExperiments[0].sourceNote.contains("Page 1"))
        try question.validated(experimentIDs: [])
    }

    func testPlannedTestsCannotBecomeEvidenceAndCitationsMustExist() throws {
        XCTAssertThrowsError(try draft("planned").materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english))
        XCTAssertThrowsError(try draft("recorded", sourcePage: "3").materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english))
        let planned = try draft("planned", sourcePage: "null", links: "[]")
        XCTAssertNoThrow(try planned.materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english))
    }

    func testEnglishImportRejectsChineseGeneratedFieldsButChineseModeAcceptsThem() throws {
        let output = try draft()
        var chinese = output; chinese.title = "处理是否改变荧光？"
        XCTAssertThrowsError(try chinese.materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english))
        XCTAssertNoThrow(try chinese.materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .chinese))
    }

    func testRecordedResultsRequireMethodAndObservationAndConfidenceIsPlaceholder() throws {
        let output = try draft()
        let question = try output.materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english)
        XCTAssertTrue(question.detail.contains("not an AI confidence estimate"))
        var missingMethod = output
        missingMethod.atomicExperiments[0].method = " "
        XCTAssertThrowsError(try missingMethod.materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english))
        var missingObservation = output
        missingObservation.atomicExperiments[0].observedResult = ""
        XCTAssertThrowsError(try missingObservation.materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english))
        var plannedWithResult = output
        plannedWithResult.atomicExperiments[0].status = .planned
        XCTAssertThrowsError(try plannedWithResult.materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english))
    }

    private func mainlineJSON() throws -> JSONValue {
        var object = try XCTUnwrap(JSONValue.decode(String(decoding: JSONEncoder().encode(draft()), as: UTF8.self)).object)
        object["mainline"] = .array([.object([
            "claim_key": .string("conclusion"), "question": .string("Is an effect present?"),
            "motivation": .string("Establish the effect before testing mechanisms"), "origin": .string("inferred")
        ])])
        for key in ["evidence_links", "claim_links"] {
            object[key] = .array(try XCTUnwrap(object[key]?.array).map { value in
                var fields = value.object!; fields["explanation"] = .string("The matched comparison informs this specific conclusion")
                fields["limitations"] = .string("Does not establish a mechanism"); return .object(fields)
            })
        }
        return .object(object)
    }
    private func decode(_ json: JSONValue) throws -> SciencePDFImport {
        try JSONDecoder().decode(SciencePDFImport.self, from: JSONEncoder().encode(json))
    }
    func testNewPDFContractBuildsMainlineViaLowerConclusionAndPreservesWarrants() throws {
        let json = try mainlineJSON(); try SciencePDFImport.validateShape(json)
        let q = try decode(json).materialize(fileName: "paper.pdf", pageCount: 2, fingerprint: "abc", language: .english)
        XCTAssertEqual(q.mainline.count, 1)
        XCTAssertEqual(q.mainline[0].origin, .inferred)
        XCTAssertNotEqual(q.mainline[0].claimID, q.evidenceLinks[0].claimID)
        XCTAssertFalse(q.evidenceLinks[0].explanation.isEmpty)
        XCTAssertEqual(ScienceArgumentIndex(question: q).evidence(for: q.mainline[0].claimID).count, 1)
    }
    func testNewModelContractRejectsMissingMainlineAndUnknownNestedFields() throws {
        var object = try XCTUnwrap(mainlineJSON().object)
        object.removeValue(forKey: "mainline")
        XCTAssertThrowsError(try SciencePDFImport.validateShape(.object(object)))
        object = try XCTUnwrap(mainlineJSON().object)
        var fields = object["evidence_links"]!.array![0].object!
        fields["automatic_proof"] = .bool(true)
        object["evidence_links"] = .array([.object(fields)])
        XCTAssertThrowsError(try SciencePDFImport.validateShape(.object(object)))
    }
    func testMainlinePDFRejectsAtomicShortcutAndEmptyOrWrongLanguageWarrant() throws {
        var output = try decode(mainlineJSON())
        output.evidenceLinks[0].claimKey = "conclusion"
        XCTAssertThrowsError(try output.materialize(fileName: "p.pdf", pageCount: 2, fingerprint: "abc", language: .english))
        output = try decode(mainlineJSON()); output.evidenceLinks[0].explanation = " "
        XCTAssertThrowsError(try output.materialize(fileName: "p.pdf", pageCount: 2, fingerprint: "abc", language: .english))
        output = try decode(mainlineJSON()); output.evidenceLinks[0].explanation = "中文论证"
        XCTAssertThrowsError(try output.materialize(fileName: "p.pdf", pageCount: 2, fingerprint: "abc", language: .english))
    }

    func testCoverageAcceptsDeepAndSharedBranchesInBothLanguages() throws {
        var output = try decode(mainlineJSON())
        output.claims.append(.init(key: "middle", kind: .conclusion, text: "The controlled comparison excludes a measurement alternative.", sourcePage: 1))
        output.claimLinks = [
            .init(fromKey: "observation", toKey: "middle", kind: .supports, explanation: "Matched controls exclude the stated measurement alternative.", limitations: "Other explanations remain."),
            .init(fromKey: "middle", toKey: "conclusion", kind: .supports, explanation: "The controlled effect informs the scoped result.", limitations: "Mechanism untested."),
            .init(fromKey: "observation", toKey: "conclusion", kind: .contradicts, explanation: "The alternative observation limits the strength of the same result.", limitations: "Different interpretation.")
        ]
        for language in [AppLanguage.english, .chinese] { XCTAssertNoThrow(try output.validateMainlineCoverage(language: language)) }
    }

    func testCoverageRejectsOrphanClaimsAndReportsTheirKeys() throws {
        var output = try decode(mainlineJSON())
        output.claims.append(.init(key: "missing_branch", kind: .conclusion, text: "A separate source finding.", sourcePage: 1))
        for language in [AppLanguage.english, .chinese] {
            XCTAssertThrowsError(try output.validateMainlineCoverage(language: language)) { error in
                XCTAssertTrue(error.localizedDescription.contains("missing_branch"))
                XCTAssertEqual(AppLanguage.containsHan(error.localizedDescription), language == .chinese)
            }
        }
    }

    func testCoverageRejectsRecordedAtomWithoutResultPathAndReversedArrows() throws {
        var output = try decode(mainlineJSON()); output.evidenceLinks = []
        XCTAssertThrowsError(try output.validateMainlineCoverage(language: .english)) { error in
            XCTAssertTrue(error.localizedDescription.contains("test_a"))
        }
        output = try decode(mainlineJSON())
        output.claimLinks[0].fromKey = "conclusion"; output.claimLinks[0].toKey = "observation"
        XCTAssertThrowsError(try output.validateMainlineCoverage(language: .english))
    }

    func testDiscussionCannotReplaceAnExperimentsResultTree() throws {
        var output = try decode(mainlineJSON())
        output.mainline![0].role = .discussion
        XCTAssertThrowsError(try output.validateMainlineCoverage(language: .english))
    }

    func testFutureTestIsNotTreatedAsAnObservedOrphanAndOldGraphIsNotRewritten() throws {
        let old = try draft()
        XCTAssertNoThrow(try old.materialize(fileName: "old.pdf", pageCount: 1, fingerprint: "abc", language: .english))
        var output = try decode(mainlineJSON())
        output.atomicExperiments.append(.init(key: "future", title: "Future check", method: "Proposed only", status: .planned, observedResult: "", sourcePage: nil))
        XCTAssertNoThrow(try output.validateMainlineCoverage(language: .english))
    }

    func testNonemptyReadingCannotReturnAnEmptyOrDiscussionOnlyGraph() throws {
        let reading = PaperAnalysis(paper_title: "Study", authors: [], year: "", doi: "", study_type: .experimental,
            central_question: "Does treatment alter signal?", background_and_gap: "", summary: "A comparison was reported.",
            methods: [], findings: [.init(key: "f1", statement: "Groups differ", quantitative_result: "", uncertainty: "Limited sampling", interpretation: "A scoped difference, not mechanism", method_keys: [], source_pages: [1], figure_refs: [])], conclusions: [], limitations: [], open_questions: [])
        var output = try decode(mainlineJSON())
        output.analysis = reading
        output.claims = []; output.atomicExperiments = []; output.evidenceLinks = []; output.claimLinks = []; output.mainline = []
        XCTAssertThrowsError(try output.validateMainlineCoverage(language: .english))
        output = try decode(mainlineJSON()); output.analysis = reading
        output.atomicExperiments = []; output.evidenceLinks = []
        output.mainline![0].role = .discussion
        XCTAssertThrowsError(try output.validateMainlineCoverage(language: .english))
    }
}
