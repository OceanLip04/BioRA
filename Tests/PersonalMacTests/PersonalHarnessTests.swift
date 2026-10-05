import CryptoKit
import Foundation
import XCTest
import PersonalCore
@testable import PersonalMac

private final class MockModel: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        let lock = NSLock(); var replies: [(Int, String, String)] = []; var requests: [URLRequest] = []
        var handler: (@Sendable (URLRequest, Int) -> (Int, String, String))?
        func reset(_ values: [(Int, String, String)]) { lock.lock(); defer { lock.unlock() }; replies = values; requests = []; handler = nil }
        func configure(_ callback: @escaping @Sendable (URLRequest, Int) -> (Int, String, String)) { lock.lock(); defer { lock.unlock() }; requests = []; handler = callback }
        func next(_ request: URLRequest) -> (Int, String, String) { lock.lock(); defer { lock.unlock() }; requests.append(request); if let handler { return handler(request, requests.count) }; return replies.isEmpty ? (500, "application/json", "{}") : replies.removeFirst() }
        func captured() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
            captured.httpBody = data
        }
        let (code, type, body) = Self.state.next(captured)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class PersonalHarnessTests: XCTestCase {
    private func routeDirectory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/TestWorkspaces/route-\(UUID())", isDirectory: true)
    }
    @MainActor func testThemePersistsAndChangesOnlyPresentation() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        let instrument = Instrument(name: "Centrifuge"); try store.saveInstrument(instrument)
        let snapshot = store.workspace
        try store.setTheme(.macOS)
        var expected = snapshot; expected.theme = .macOS; expected.revision += 1
        XCTAssertEqual(store.workspace, expected)
        XCTAssertEqual(ThemeAppearance.shared.theme, .macOS)
        let reloaded = PersonalStore(directory: dir, demo: false, loadImmediately: false)
        XCTAssertTrue(reloaded.isLoading); XCTAssertTrue(reloaded.readOnly)
        XCTAssertThrowsError(try reloaded.saveInstrument(Instrument(name: "Must not write")))
        await reloaded.loadWorkspace(demo: false)
        XCTAssertFalse(reloaded.isLoading); XCTAssertFalse(reloaded.readOnly)
        XCTAssertEqual(reloaded.workspace.theme, .macOS)
        XCTAssertEqual(reloaded.workspace.instruments, [instrument])
        try await runFunction(store, "workspace_preferences", #"{"action":"update","theme":"paper"}"#)
        XCTAssertEqual(store.workspace.theme, .paper)
        XCTAssertEqual(PersonalStore(directory: dir, demo: false).workspace.theme, .paper)
        XCTAssertEqual(store.workspace.models, snapshot.models)
        XCTAssertEqual(store.workspace.preferences, snapshot.preferences)
    }
    @MainActor func testDeferredLoadingProtectsCorruptDatabase() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = Data("Not a SQLite database".utf8)
        let url = dir.appendingPathComponent("workspace.sqlite"); try data.write(to: url)
        let store = PersonalStore(directory: dir, demo: false, loadImmediately: false)
        XCTAssertTrue(store.isLoading)
        await store.loadWorkspace(demo: false)
        XCTAssertTrue(store.readOnly); XCTAssertFalse(store.isLoading)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
    @MainActor private func runFunction(_ store: PersonalStore, _ intent: String, _ request: String, input: String = "Perform this requested operation") async throws {
        MockModel.state.reset([(200, "application/json", try response(intent)), (200, "application/json", try response(request))])
        store.startAssistant(input); await store.runningTask?.value
    }
    @MainActor func testSchedulingAsksForSamplesInsteadOfGuessing() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let p = Procedure(name: "Preparation", steps: [ProcedureStep(title: "Handle", minutes: 20)])
        try store.saveProcedure(p)
        let request = try scheduleJSON(["procedure_id": .string(p.id.uuidString), "sample_count": .null])
        try await runFunction(store, "schedule", request)
        XCTAssertEqual(store.workspace.runs.last?.status, .completed)
        XCTAssertTrue(store.workspace.artifacts.isEmpty); XCTAssertTrue(store.workspace.experiments.isEmpty)
        XCTAssertTrue(store.activeSession?.messages.last?.content.contains("How many samples") ?? false)
    }
    @MainActor func testAssistantRecordsOnlyReportedOccurrencesAfterReview() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let p = Procedure(name: "Preparation", steps: [ProcedureStep(title: "Handle", minutes: 20), ProcedureStep(title: "Incubate", minutes: 30)])
        try store.saveProcedure(p)
        try store.addExperiment(name: "Run", procedureID: p.id, date: Date().addingTimeInterval(86400), sampleCount: 4)
        let experiment = try XCTUnwrap(store.workspace.experiments.first), plan = store.workspace.plan
        let request = """
        {"action":"update","experiment_id":"\(experiment.id)","sample_count":4,"step_timings":[{"step_id":"\(p.currentVersion.content.atomicSteps[0].id)","iteration":"1.1","actual_minutes":8.5}]}
        """
        MockModel.state.reset([(200, "application/json", try response("experiment_management")), (200, "application/json", try response(request))])
        store.startAssistant("I ran four samples. The handling step took 8.5 minutes; record that.")
        for _ in 0..<200 { if store.pendingApproval != nil || store.runningRunID == nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(store.pendingApproval); XCTAssertTrue(store.workspace.experiments[0].stepTimings.isEmpty)
        store.approveTool(true); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.workspace.experiments[0].stepTimings.count, 1)
        XCTAssertEqual(store.workspace.experiments[0].stepTimings[0].actualMinutes, 8.5)
        XCTAssertEqual(store.workspace.plan, plan)
    }
    @MainActor func testAssistantTimingConfigurationUsesProtocolBranchWithoutEditingRecipe() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let p = Procedure(name: "Preparation", steps: [ProcedureStep(title: "Handle", minutes: 20)])
        try store.saveProcedure(p)
        let request = """
        {"action":"timing","version_id":"\(p.currentVersion.id)","step_id":"\(p.currentVersion.content.atomicSteps[0].id)","timing_mode":"learnedSamples","baseline_minutes":20,"reference_sample_count":4}
        """
        MockModel.state.reset([(200, "application/json", try response("protocol_management")), (200, "application/json", try response(request))])
        store.startAssistant("Learn handling time by sample count; the baseline is twenty minutes for four samples.")
        for _ in 0..<200 { if store.pendingApproval != nil || store.runningRunID == nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(store.pendingApproval); store.approveTool(true); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.workspace.stepTimingConfigurations.first?.mode, .learnedSamples)
        XCTAssertEqual(store.workspace.procedures[0], p)
    }
    @MainActor func testAssistantChangingSampleCountCannotAdoptOldPlanUnchanged() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let p = Procedure(name: "Preparation", steps: [ProcedureStep(title: "Handle", minutes: 20)])
        try store.saveProcedure(p)
        let artifact = try store.scheduleArtifact(name: "Four", procedureID: p.id, date: Date().addingTimeInterval(86400),
            preferences: SchedulePreferences(), sampleCount: 4)
        let request = try scheduleJSON(["action": .string("apply"), "artifact_id": .string(artifact.id.uuidString), "sample_count": .number(8)])
        try await runFunction(store, "schedule", request)
        XCTAssertNil(store.pendingApproval); XCTAssertTrue(store.workspace.experiments.isEmpty)
        XCTAssertTrue(store.activeSession?.messages.last?.content.contains("requires a revised schedule") ?? false)
    }
    @MainActor func testAssistantCalibrationAsksForReferenceSamplesRatherThanAssumingOne() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let p = Procedure(name: "Preparation", steps: [ProcedureStep(title: "Handle", minutes: 20)])
        try store.saveProcedure(p)
        let request = """
        {"action":"timing","version_id":"\(p.currentVersion.id)","step_id":"\(p.currentVersion.content.atomicSteps[0].id)","timing_mode":"learnedSamples"}
        """
        try await runFunction(store, "protocol_management", request)
        XCTAssertNil(store.pendingApproval); XCTAssertTrue(store.workspace.stepTimingConfigurations.isEmpty)
        XCTAssertTrue(store.activeSession?.messages.last?.content.contains("How many samples") ?? false)
    }
    @MainActor func testInstrumentRouteUsesPlainLabelThenDedicatedJSONAndPersists() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        try await runFunction(store, "instrument_management", #"{"action":"create","name":"Centrifuge","location":"Bench A","available":false,"note":"Awaiting inspection"}"#)
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        let item = try XCTUnwrap(store.workspace.instruments.first)
        XCTAssertFalse(item.available); XCTAssertEqual(item.location, "Bench A")
        XCTAssertEqual(try store.file.load()?.instruments.first?.name, "Centrifuge")
        let requests = try MockModel.state.captured().map { try JSONValue.decode(String(decoding: $0.httpBody!, as: UTF8.self)) }
        XCTAssertEqual(requests[0]["response_format"], .null)
        XCTAssertEqual(requests[0]["max_tokens"].int, 256)
        XCTAssertTrue(requests[1]["messages"].array![0]["content"].string!.contains("ONLY for function instrument_management"))
        XCTAssertFalse(requests[1]["messages"].array![0]["content"].string!.contains("schema for schedule"))
        try await runFunction(store, "instrument_management", "{\"action\":\"update\",\"instrument_id\":\"\(item.id)\",\"available\":true}")
        XCTAssertTrue(store.workspace.instruments[0].available); XCTAssertEqual(store.workspace.instruments[0].note, "Awaiting inspection")
    }
    @MainActor func testUnknownOrJSONClassifierNeverExecutesMutation() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        try await runFunction(store, #"{"user_intent":"instrument_management"}"#, "unregistered_function")
        XCTAssertEqual(store.workspace.runs.last?.status, .failed)
        XCTAssertTrue(store.workspace.instruments.isEmpty)
        XCTAssertEqual(MockModel.state.captured().count, 2)
    }
    @MainActor func testMissingTargetClarifiesWithoutMutating() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        try await runFunction(store, "instrument_management", #"{"action":"update","clarification":"Which centrifuge should I update?"}"#)
        XCTAssertEqual(store.workspace.runs.last?.status, .completed)
        XCTAssertTrue(store.workspace.instruments.isEmpty)
        XCTAssertEqual(store.activeSession?.messages.last?.content, "Which centrifuge should I update?")
    }
    @MainActor func testExperimentsRouteUpdatesActualStatusAndNotes() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        let p = Procedure(name: "Measure", steps: [ProcedureStep(title: "Measure mass", minutes: 5)])
        try store.saveProcedure(p)
        let a = try store.scheduleArtifact(name: "Sample", procedureID: p.id, date: Date().addingTimeInterval(86400), preferences: SchedulePreferences())
        try store.applySchedule(artifactID: a.id, candidateID: a.candidates[0].id)
        let id = try XCTUnwrap(store.workspace.experiments.first?.id)
        try await runFunction(store, "experiment_management", "{\"action\":\"update\",\"experiment_id\":\"\(id)\",\"status\":\"completed\",\"note\":\"Measured 12 mg\"}")
        XCTAssertEqual(store.workspace.experiments[0].status, .completed)
        XCTAssertEqual(store.workspace.experiments[0].note, "Measured 12 mg")
    }
    @MainActor func testCalendarRejectsReversedTimeWithoutWriting() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        try await runFunction(store, "calendar_management", #"{"action":"create","title":"Meeting","start":"2026-10-02T10:00:00+08:00","end":"2026-10-02T09:00:00+08:00"}"#)
        XCTAssertEqual(store.workspace.runs.last?.status, .failed)
        XCTAssertTrue(store.workspace.busyIntervals.isEmpty)
        try await runFunction(store, "calendar_management", #"{"action":"create","title":"Meeting","start":"2026-10-02T09:00:00+08:00","end":"2026-10-02T10:00:00+08:00"}"#)
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.workspace.busyIntervals.count, 1)
    }
    @MainActor func testScienceRoutesCreateQuestionAndRejectPlannedEvidence() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        try await runFunction(store, "science_question", #"{"action":"create","title":"Does temperature affect fluorescence?"}"#)
        let question = try XCTUnwrap(store.workspace.scientificQuestions.first)
        try await runFunction(store, "science_claim", "{\"action\":\"create\",\"question_id\":\"\(question.id)\",\"text\":\"Temperature may affect the signal\",\"kind\":\"hypothesis\"}")
        let claim = try XCTUnwrap(store.workspace.scientificQuestions[0].claims.first)
        try await runFunction(store, "science_experiment", "{\"action\":\"create\",\"question_id\":\"\(question.id)\",\"title\":\"Temperature comparison\",\"method\":\"Compare 20 and 30 degrees\"}")
        let atom = try XCTUnwrap(store.workspace.scientificQuestions[0].atomicExperiments.first)
        XCTAssertEqual(atom.status, .planned)
        try await runFunction(store, "science_evidence", "{\"action\":\"link_atom\",\"question_id\":\"\(question.id)\",\"atom_id\":\"\(atom.id)\",\"claim_id\":\"\(claim.id)\",\"kind\":\"supports\",\"explanation\":\"Matched comparison tests the hypothesis\"}")
        XCTAssertEqual(store.workspace.runs.last?.status, .failed)
        XCTAssertTrue(store.workspace.scientificQuestions[0].evidenceLinks.isEmpty)
    }
    @MainActor func testAssistantOrganizesMainlineAndWritesWarrantWithoutDirectAtomicShortcut() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let root = ScienceClaim(kind: .conclusion, text: "The treatment alters the phenotype")
        let leaf = ScienceClaim(kind: .observation, text: "Matched groups differ in readout")
        let atom = AtomicExperiment(title: "Comparison", method: "Treated versus control", status: .recorded, observedResult: "Different recorded readouts", sourceNote: "Notebook p.1")
        let q = ScientificQuestion(title: "Is an effect present?", claims: [root, leaf], atomicExperiments: [atom])
        try store.saveScientificQuestion(q)
        try await runFunction(store, "science_question", """
        {"action":"mainline","question_id":"\(q.id)","mainline":[{"claimID":"\(root.id)","question":"Is an effect present?","motivation":"Establish the effect before studying the mechanism","origin":"inferred"}]}
        """)
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.workspace.scientificQuestions[0].mainline.count, 1)
        try await runFunction(store, "science_evidence", """
        {"action":"link_atom","question_id":"\(q.id)","atom_id":"\(atom.id)","claim_id":"\(root.id)","kind":"supports","explanation":"Matched comparison"}
        """)
        XCTAssertEqual(store.workspace.runs.last?.status, .failed)
        XCTAssertTrue(store.workspace.scientificQuestions[0].evidenceLinks.isEmpty)
        try await runFunction(store, "science_evidence", """
        {"action":"link_atom","question_id":"\(q.id)","atom_id":"\(atom.id)","claim_id":"\(leaf.id)","kind":"supports","explanation":"The recorded matched groups establish a readout difference","limitations":"Mechanism remains untested"}
        """)
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        let link = try XCTUnwrap(store.workspace.scientificQuestions[0].evidenceLinks.first)
        XCTAssertTrue(link.explanation.contains("readout difference"))
        try await runFunction(store, "science_evidence", """
        {"action":"link_claim","question_id":"\(q.id)","from_claim_id":"\(leaf.id)","to_claim_id":"\(root.id)","kind":"supports","explanation":"The scoped observation informs the phenotype conclusion"}
        """)
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(ScienceArgumentIndex(question: store.workspace.scientificQuestions[0]).evidence(for: root.id).count, 1)
        try await runFunction(store, "science_evidence", """
        {"action":"update","question_id":"\(q.id)","link_id":"\(link.id)","explanation":"Updated warrant, without changing support kind"}
        """)
        XCTAssertEqual(store.workspace.scientificQuestions[0].evidenceLinks[0].kind, .supports)
        XCTAssertTrue(store.workspace.scientificQuestions[0].evidenceLinks[0].explanation.contains("Updated warrant"))
        XCTAssertEqual(try store.file.load()?.scientificQuestions[0].mainline[0].claimID, root.id)
    }
    @MainActor func testReadOnlyMainlinePreviewDoesNotCreateDatabase() throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(previewDirectory: dir, previewWorkspace: .demo())
        XCTAssertTrue(store.readOnly); XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.workspace.scientificQuestions[0].mainline.isEmpty)
        try store.workspace.validated()
        XCTAssertThrowsError(try store.commit { $0.scientificQuestions = [] })
        try store.setTheme(.macOS)
        XCTAssertEqual(store.workspace.theme, .macOS)
        XCTAssertTrue(store.readOnly)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
    @MainActor func testPreferenceAndModelAndNavigationRoutes() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        try await runFunction(store, "workspace_preferences", #"{"action":"update","language":"en","work_start_minute":600}"#)
        XCTAssertEqual(store.workspace.language, .english); XCTAssertEqual(store.workspace.preferences.workStartMinute, 600)
        XCTAssertFalse(AppLanguage.containsHan(store.activeSession?.messages.last?.content ?? ""))
        let connection = store.workspace.connections[0].id
        try await runFunction(store, "model_configuration", "{\"action\":\"create\",\"connection_id\":\"\(connection)\",\"name\":\"Reader\",\"model\":\"local-reader\",\"supports_vision\":true}")
        let model = try XCTUnwrap(store.workspace.models.last)
        XCTAssertEqual(model.model, "local-reader"); XCTAssertTrue(model.supportsVision)
        try await runFunction(store, "model_configuration", "{\"action\":\"route\",\"purpose\":\"protocol_builder\",\"model_id\":\"\(model.id)\"}")
        XCTAssertEqual(store.workspace.routing.protocolBuilder, model.id)
        try await runFunction(store, "navigation", #"{"page":"instruments"}"#)
        XCTAssertEqual(store.requestedPage, "instruments")
    }
    @MainActor func testAssistantPaperPipelineProducesReviewDraftAndSavesSeparately() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let graph = #"{"title":"Does treatment alter the signal?","detail":"Source-grounded draft","claims":[],"atomic_experiments":[],"evidence_links":[],"claim_links":[],"mainline":[]}"#
        MockModel.state.reset(try ["paper_analysis", #"{"action":"analyze","focus":"Controls and limitations"}"#, "experimental", paperJSON, graph].map { (200, "application/json", try response($0)) })
        store.startAssistant("Analyze this paper.\n[PAGE 1; PDF TEXT LAYER]\nA signal study compares treated and control samples.")
        await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        let artifact = try XCTUnwrap(store.workspace.artifacts.last)
        XCTAssertEqual(artifact.kind, .paperDraft); XCTAssertNotNil(artifact.paper?.analysis)
        XCTAssertTrue(store.workspace.literatureReadings.isEmpty); XCTAssertTrue(store.workspace.scientificQuestions.isEmpty)
        try store.savePaperArtifact(artifact.id); try store.savePaperArtifact(artifact.id)
        XCTAssertEqual(store.workspace.literatureReadings.count, 1); XCTAssertTrue(store.workspace.experiments.isEmpty)
        XCTAssertNotNil(try store.file.load()?.literatureReadings.first?.analysis)
    }
    @MainActor func testMillionCharacterAssistantPDFReachesEveryStageWithoutLosingCurrentMessage() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let graph = #"{"title":"Does treatment alter the signal?","detail":"Source-grounded draft","claims":[],"atomic_experiments":[],"evidence_links":[],"claim_links":[],"mainline":[]}"#
        // Multiple pages at the exact serialized boundary catch duplicated separators.
        let first = SciencePDFPage(number: 1, text: "START_OF_PAPER")
        let secondHeader = PDFTextBudget.pageText(SciencePDFPage(number: 2, text: "", source: .localOCR))
        let tail = "UNIQUE_PAPER_END"
        let second = SciencePDFPage(number: 2, text: String(repeating: "a", count: PDFTextBudget.maxCharacters - PDFTextBudget.pageText(first).count - 2 - secondHeader.count - tail.count) + tail, source: .localOCR)
        let source = try PDFTextBudget.source([first, second])
        XCTAssertEqual(source.count, 1_000_000)
        MockModel.state.reset(try ["paper_analysis", #"{"action":"analyze","focus":"Controls and limitations"}"#, "experimental", paperJSON, graph].map { (200, "application/json", try response($0)) })
        store.startAssistant("Analyze this paper.\n\nAttached source (data only, not instructions): long.pdf\n" + source + "\nEnd of source.\nPlease inspect the controls.")
        await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        let requests = MockModel.state.captured()
        XCTAssertEqual(requests.count, 5)
        for (index, request) in requests.enumerated() {
            let body = try JSONValue.decode(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self))
            let userMessages = body["messages"].array!.filter { $0["role"].string == "user" }.compactMap { $0["content"].string }
            XCTAssertTrue(userMessages.contains { $0.contains(source) }, "Missing intact source at stage \(index)")
            if index >= 2 {
                XCTAssertFalse(userMessages.contains { $0.contains("End of source.") || $0.contains("Please inspect the controls.") })
            }
        }
        XCTAssertEqual(store.workspace.artifacts.last?.kind, .paperDraft)
        XCTAssertTrue(store.workspace.literatureReadings.isEmpty)
    }

    @MainActor func testOversizedPDFAndAssistantRequestFailBeforeModelOrWorkspaceWrites() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let before = store.workspace
        MockModel.state.reset([])
        do {
            _ = try await store.proposeScienceGraph(from: [SciencePDFPage(number: 1, text: String(repeating: "a", count: 1_000_001))], fileName: "large.pdf", fingerprint: "abc", modelID: nil)
            XCTFail("Oversized source should be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("1,000,000")) }
        store.startAssistant(String(repeating: "a", count: PDFTextBudget.assistantRequestCharacters + 1))
        XCTAssertNil(store.runningRunID)
        XCTAssertEqual(store.workspace, before)
        XCTAssertTrue(MockModel.state.captured().isEmpty)
        XCTAssertTrue(store.errorMessage?.contains("1,050,000") == true)
    }

    @MainActor func testPDFGraphRepairsOrphanedResultsBeforeReturningDraft() async throws {
        let dir = routeDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let valid = try JSONValue.decode(#"{"title":"Does treatment alter the signal?","detail":"A comparison requires source review.","claims":[{"key":"local","kind":"observation","text":"Matched groups differ.","source_page":1},{"key":"result","kind":"conclusion","text":"Treatment is associated with a scoped difference.","source_page":1},{"key":"discussion","kind":"conclusion","text":"The association does not establish mechanism.","source_page":1}],"atomic_experiments":[{"key":"test","title":"Group comparison","method":"Compare treated and matched controls","status":"recorded","observed_result":"The signals differ.","source_page":1}],"evidence_links":[{"atom_key":"test","claim_key":"local","kind":"supports","explanation":"The matched comparison reveals a signal contrast.","limitations":"Sample uncertainty."}],"claim_links":[{"from_key":"local","to_key":"result","kind":"supports","explanation":"The contrast informs a treatment-associated difference.","limitations":"Not causation."}],"mainline":[{"claim_key":"result","question":"Is a difference present?","motivation":"Establish the comparison before interpreting it.","origin":"inferred","role":"result"},{"claim_key":"discussion","question":"What remains unresolved?","motivation":"Integrate the scoped difference and limits.","origin":"inferred","role":"discussion"}]}"#)
        var invalid = valid.object!
        invalid["claim_links"] = .array([])
        MockModel.state.reset(try ["experimental", paperJSON, JSONValue.object(invalid).text(), valid.text()].map { (200, "application/json", try response($0)) })
        let (_, graph) = try await store.proposeScienceGraph(from: [SciencePDFPage(number: 1, text: "A matched comparison reports a signal difference.")], fileName: "test.pdf", fingerprint: "abc", modelID: nil)
        XCTAssertEqual(graph.evidenceLinks.count, 1)
        let requests = MockModel.state.captured()
        XCTAssertEqual(requests.count, 4)
        let repaired = try JSONValue.decode(String(decoding: try XCTUnwrap(requests.last?.httpBody), as: UTF8.self))
        let instruction = try XCTUnwrap(repaired["messages"].array?.last?["content"].string)
        XCTAssertTrue(instruction.contains("Mainline coverage failed"))
        XCTAssertTrue(instruction.contains("local")); XCTAssertTrue(instruction.contains("test"))
        XCTAssertTrue(instruction.contains("Do not fix coverage by deleting results"))
        XCTAssertTrue(store.workspace.literatureReadings.isEmpty)
    }

    private func intent(_ name: String) -> String { name }
    private var paperJSON: String {
        """
        {"paper_title":"Signal study","authors":[],"year":"","doi":"","study_type":"experimental","central_question":"Does treatment alter the signal?","background_and_gap":"","summary":"A reported comparison requires source review.","methods":[],"findings":[],"conclusions":[],"limitations":[],"open_questions":[],"discussion":{"summary":"Interpretation remains limited to the reported comparison.","origin":"inferred","source_pages":[]},"figure_panels":[],"panel_links":[]}
        """
    }
    private func scheduleJSON(_ values: [String: JSONValue]) throws -> String {
        var output: [String: JSONValue] = ["action": .string("generate"), "sample_count": .number(1), "objective": .string("earliest_finish"), "blocked_times": .array([]), "apply_after_generation": .bool(false)]
        output.merge(values) { _, new in new }; return try JSONValue.object(output).text()
    }
    private func session() -> URLSession { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [MockModel.self]; return URLSession(configuration: c) }
    private func response(_ text: String, calls: [ToolCall] = []) throws -> String {
        try Self.response(text, calls: calls)
    }
    private static func response(_ text: String, calls: [ToolCall] = []) throws -> String {
        let msg = WireMessage(role: "assistant", content: text, toolCalls: calls.isEmpty ? nil : calls)
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(msg))
        return try JSONValue.object(["choices": .array([.object(["message": json, "finish_reason": .string(calls.isEmpty ? "stop" : "tool_calls")])])]).text()
    }
    @MainActor private func store(_ dir: URL) throws -> PersonalStore {
        let store = PersonalStore(directory: dir, demo: false)
        var c = store.workspace.connections[0]; c.baseURL = "http://localhost:1234/v1"; try store.saveConnection(c)
        var m = store.workspace.models[0]; m.model = "mock-model"; m.stream = false; try store.saveModel(m)
        store.networkSession = session(); return store
    }
    @MainActor func testEnglishLanguagePersistsAndQuestionAnswerRepairsChineseOutput() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("language-qa-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        XCTAssertEqual(store.workspace.language, .chinese)
        try store.setLanguage(.english)
        XCTAssertEqual(try store.file.load()?.language, .english)
        MockModel.state.reset([
            (200, "application/json", try response("question_answer")),
            (200, "application/json", try response("{\"answer\":\"这是中文回答\",\"referenced_protocol_ids\":[]}")),
            (200, "application/json", try response("{\"answer\":\"The recorded data do not yet establish this conclusion.\",\"referenced_protocol_ids\":[]}")),
        ])
        store.startAssistant("目前有哪些证据？")
        await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.activeSession?.messages.last?.content, "The recorded data do not yet establish this conclusion.")
        let wires = try MockModel.state.captured().map { try JSONDecoder().decode(JSONValue.self, from: $0.httpBody!) }
        XCTAssertEqual(wires.count, 3)
        XCTAssertTrue(wires[0]["messages"].array!.first!["content"].string!.contains("You are the intent classifier"))
        XCTAssertTrue(wires[1]["messages"].array!.first!["content"].string!.contains("read-only question-answering branch"))
        XCTAssertTrue(wires[2]["messages"].array!.last!["content"].string!.contains("write user-facing strings in English"))
        XCTAssertEqual(PersonalStore(directory: dir, demo: false).workspace.language, .english)
    }

    @MainActor func testEnglishProtocolBuilderTranslatesAllDocumentSections() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("language-protocol-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        var english = ProtocolContent(blocks: [ProtocolBlock(title: "Preparation", subblocks: [ProtocolSubblock(title: "Sample setup", steps: [ProtocolStep(title: "Weigh the sample", minutes: 5)])])])
        english.renumber(); english.objective = "Measure sample mass."
        english.materials = [ProtocolMaterial(name: "Sample", category: .sample, quantity: "To be confirmed")]
        english.principles = ["Mass is measured with a calibrated balance."]
        english.precautions = ["Confirm that the balance is calibrated."]
        var chinese = english; chinese.objective = "测量样品质量。"
        let json = { (value: ProtocolContent) throws -> String in String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
        MockModel.state.reset([
            (200, "application/json", try response("protocol_generation")),
            (200, "application/json", try response("{\"action\":\"generate\",\"name\":\"Sample Mass\",\"source\":\"测量样品质量\"}")),
            (200, "application/json", try response(json(chinese))),
            (200, "application/json", try response(json(english))),
        ])
        store.startAssistant("生成测量质量的 Protocol")
        await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.workspace.artifacts.last?.procedure?.currentVersion.content, english)
        XCTAssertFalse(AppLanguage.containsHan(store.activeSession?.messages.last?.content ?? ""))
        let wires = try MockModel.state.captured().map { try JSONDecoder().decode(JSONValue.self, from: $0.httpBody!) }
        XCTAssertEqual(wires.count, 4)
        XCTAssertTrue(wires[2]["messages"].array!.first!["content"].string!.contains("Every newly generated human-readable string"))
        XCTAssertTrue(wires[3]["messages"].array!.last!["content"].string!.contains("Translate all generated prose into English"))
    }

    @MainActor func testEnglishScheduleCandidateAndLanguageSwitchGuard() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("language-schedule-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let procedure = Procedure(name: "Mass measurement", steps: [ProcedureStep(title: "Weigh sample", minutes: 15)])
        try store.saveProcedure(procedure)
        let artifact = try store.scheduleArtifact(name: "Sample experiment", procedureID: procedure.id, date: Date().addingTimeInterval(86400), preferences: SchedulePreferences())
        XCTAssertFalse(AppLanguage.containsHan(artifact.candidates[0].label + artifact.candidates[0].rationale))
        store.runningRunID = UUID()
        XCTAssertThrowsError(try store.setLanguage(.chinese))
        XCTAssertEqual(store.workspace.language, .english)
        store.runningRunID = nil
    }
    @MainActor func testPDFGraphProposalRepairsLanguageAndDoesNotWriteUntilReviewed() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-graph-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let invalid = """
        {"title":"处理是否改变信号？","detail":"Draft","claims":[],"atomic_experiments":[],"evidence_links":[],"claim_links":[],"mainline":[]}
        """
        let valid = """
        {"title":"Does treatment change the signal?","detail":"A paper-reported comparison; verify the source.",
         "claims":[{"key":"c1","kind":"observation","text":"The signal differed between groups.","source_page":1},{"key":"r1","kind":"conclusion","text":"Treatment may alter the signal under the measured conditions.","source_page":1},{"key":"d1","kind":"conclusion","text":"The measured difference warrants further checks, not a causal mechanism.","source_page":1}],
         "atomic_experiments":[{"key":"a1","title":"Group comparison","method":"Compare images","status":"recorded","observed_result":"The paper reports a difference.","source_page":1}],
         "evidence_links":[{"atom_key":"a1","claim_key":"c1","kind":"supports","explanation":"The matched groups showed different signals.","limitations":"Verify image measurements."}],
         "claim_links":[{"from_key":"c1","to_key":"r1","kind":"supports","explanation":"The observed difference informs the scoped treatment conclusion.","limitations":"Does not establish a mechanism."},{"from_key":"r1","to_key":"d1","kind":"supports","explanation":"A scoped difference leaves causal interpretation unresolved.","limitations":"Further controls needed."}],
         "mainline":[{"claim_key":"r1","question":"Is a treatment-related difference present?","motivation":"Establish an effect before testing its mechanism.","origin":"inferred","role":"result"},{"claim_key":"d1","question":"What can be concluded?","motivation":"Integrate the result within its measured scope.","origin":"inferred","role":"discussion"}]}
        """
        MockModel.state.reset([(200, "application/json", try response("experimental")), (200, "application/json", try response(paperJSON)), (200, "application/json", try response(invalid)), (200, "application/json", try response(valid))])
        let originalPDF = Data("%PDF-1.4 test paper".utf8)
        let fingerprint = SHA256.hash(data: originalPDF).map { String(format: "%02x", $0) }.joined().prefix(12).description
        let (draft, preview) = try await store.proposeScienceGraph(from: [SciencePDFPage(number: 1, text: "Study text about a reported comparison.")],
            fileName: "study.pdf", fingerprint: fingerprint, modelID: nil)
        XCTAssertEqual(draft.claims.count, 3)
        XCTAssertEqual(preview.mainline.count, 2)
        XCTAssertEqual(preview.mainline.last?.role, .discussion)
        XCTAssertEqual(preview.evidenceLinks.count, 1)
        XCTAssertTrue(store.workspace.scientificQuestions.isEmpty)
        let wires = try MockModel.state.captured().map { try JSONDecoder().decode(JSONValue.self, from: $0.httpBody!) }
        XCTAssertEqual(wires.count, 4)
        XCTAssertEqual(wires[0]["response_format"], .null)
        XCTAssertTrue(wires[1]["messages"].array!.first!["content"].string!.contains("Cover every major result"))
        XCTAssertTrue(wires[2]["messages"].array!.first!["content"].string!.contains("Atomic tests MUST NOT point directly"))
        XCTAssertTrue(wires[3]["messages"].array!.last!["content"].string!.contains("write every generated string in English"))
        XCTAssertNotNil(draft.analysis)
        try store.saveLiteratureReading(LiteratureReading(fileName: "study.pdf", fingerprint: fingerprint,
            pageCount: 1, graph: preview, analysis: draft.analysis), originalPDF: originalPDF)
        XCTAssertTrue(store.workspace.scientificQuestions.isEmpty)
        XCTAssertEqual(store.workspace.literatureReadings.count, 1)
        let reloaded = try XCTUnwrap(store.file.load())
        XCTAssertEqual(reloaded.literatureReadings.first?.graph.title, preview.title)
        let archived = try XCTUnwrap(reloaded.literatureReadings.first?.pdfStorageName)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("LiteraturePDFs/").appendingPathComponent(archived)), originalPDF)
        let readingID = try XCTUnwrap(reloaded.literatureReadings.first?.id)
        try store.setLiteratureGraphPosition(readingID: readingID, nodeID: preview.id,
                                            point: ScienceGraphPoint(x: 640, y: 260))
        XCTAssertEqual(try store.file.load()?.literatureReadings.first?.graph.graphPositions[preview.id.uuidString],
                       ScienceGraphPoint(x: 640, y: 260))
        try store.resetLiteratureGraphLayout(readingID: readingID)
        XCTAssertTrue(try XCTUnwrap(store.file.load()?.literatureReadings.first?.graph.graphPositions).isEmpty)
    }
    @MainActor func testLegacyPDFQuestionMovesToLiteratureLibraryWithBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-migration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        let ownQuestion = ScientificQuestion(title: "My actual research question")
        let paperQuestion = ScientificQuestion(title: "Reported paper question", detail:
            "AI-extracted from PDF “study.pdf” (SHA-256 prefix abc123). Check page citations.")
        try store.saveScientificQuestion(ownQuestion)
        try store.saveScientificQuestion(paperQuestion)
        let migrated = PersonalStore(directory: dir, demo: false)
        XCTAssertFalse(migrated.readOnly, migrated.errorMessage ?? "")
        XCTAssertEqual(migrated.workspace.scientificQuestions.map(\.id), [ownQuestion.id])
        XCTAssertEqual(migrated.workspace.literatureReadings.map(\.id), [paperQuestion.id])
        XCTAssertEqual(migrated.workspace.literatureReadings.first?.fileName, "study.pdf")
        let backup = try Data(contentsOf: dir.appendingPathComponent("before-literature-migration.json"))
        XCTAssertTrue(String(decoding: backup, as: UTF8.self).contains(paperQuestion.id.uuidString))
        let secondLaunch = PersonalStore(directory: dir, demo: false)
        XCTAssertEqual(secondLaunch.workspace.literatureReadings.count, 1)
    }
    @MainActor func testPDFGraphRejectsImageOnlyTextBeforeModelCall() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-empty-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        MockModel.state.reset([])
        do {
            _ = try await store.proposeScienceGraph(from: [SciencePDFPage(number: 1, text: " \n ")],
                fileName: "scan.pdf", fingerprint: "abc123", modelID: nil)
            XCTFail("An image-only PDF must fail before any model request")
        } catch {}
        XCTAssertTrue(MockModel.state.captured().isEmpty)
    }
    @MainActor func testPDFGraphSendsSelectedImagesOnlyToVisionModel() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-vision-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        let tinyJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let pages = [SciencePDFPage(number: 1, text: "", source: .unreadable)]
        MockModel.state.reset([])
        do {
            _ = try await store.proposeScienceGraph(from: pages, fileName: "scan.pdf", fingerprint: "abc", modelID: nil,
                images: [SciencePDFImage(number: 1, jpeg: tinyJPEG)])
            XCTFail("A text-only model must refuse images")
        } catch {}
        XCTAssertTrue(MockModel.state.captured().isEmpty)
        var model = try XCTUnwrap(store.workspace.models.first)
        model.supportsVision = true
        try store.saveModel(model)
        let valid = """
        {"title":"Does the treatment change the signal?","detail":"The image needs human review.","claims":[],"atomic_experiments":[],"evidence_links":[],"claim_links":[],"mainline":[]}
        """
        MockModel.state.reset([(200, "application/json", try response("experimental")), (200, "application/json", try response(paperJSON)), (200, "application/json", try response(valid))])
        _ = try await store.proposeScienceGraph(from: pages, fileName: "scan.pdf", fingerprint: "abc", modelID: model.id,
            images: [SciencePDFImage(number: 1, jpeg: tinyJPEG)])
        let body = try XCTUnwrap(MockModel.state.captured().first?.httpBody)
        let root = try JSONDecoder().decode(JSONValue.self, from: body)
        let messages = try XCTUnwrap(root["messages"].array)
        let parts = try XCTUnwrap(messages[1]["content"].array)
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(parts[0]["text"].string?.contains("[PAGE 1; NO LOCAL TEXT]") == true)
        XCTAssertEqual(parts[2]["type"].string, "image_url")
        XCTAssertTrue(parts[2]["image_url"]["url"].string?.hasPrefix("data:image/jpeg;base64,") == true)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("application/pdf"))
    }
    @MainActor func testEnglishSchedulingBranchUsesEnglishPromptAndLocalResult() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("language-route-schedule-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir); try store.setLanguage(.english)
        let procedure = Procedure(name: "Fluorescence check", steps: [ProcedureStep(title: "Acquire image", minutes: 30)])
        try store.saveProcedure(procedure)
        let request = try scheduleJSON(["procedure_id": .string(procedure.id.uuidString), "experiment_name": .string("Imaging experiment")])
        MockModel.state.reset([
            (200, "application/json", try response("schedule")),
            (200, "application/json", try response(request)),
        ])
        store.startAssistant("安排荧光观察实验")
        await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertFalse(AppLanguage.containsHan(store.activeSession?.messages.last?.content ?? ""))
        let artifact = try XCTUnwrap(store.workspace.artifacts.last)
        XCTAssertFalse(AppLanguage.containsHan(artifact.title + artifact.candidates[0].label + artifact.candidates[0].rationale))
        let wire = try JSONDecoder().decode(JSONValue.self, from: MockModel.state.captured()[1].httpBody!)
        XCTAssertTrue(wire["messages"].array!.first!["content"].string!.contains("extract requirements for the scheduling branch"))
    }
    @MainActor func testIntentThenReadOnlyAnswerActuallyPersists() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harness-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        MockModel.state.reset([(200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response("{\"answer\":\"工作区已读取\",\"referenced_protocol_ids\":[]}"))])
        store.startAssistant("查看我的工作区"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed); XCTAssertEqual(store.activeSession?.messages.last?.content, "工作区已读取")
        XCTAssertEqual(store.workspace.runs.last?.intent?.userIntent, .questionAnswer)
        XCTAssertEqual(try store.file.load()?.sessions, store.workspace.sessions)
        XCTAssertEqual(try store.file.load()?.runs.last?.intent, store.workspace.runs.last?.intent)
        let wires = try MockModel.state.captured().map { try JSONDecoder().decode(JSONValue.self, from: $0.httpBody!) }
        XCTAssertEqual(wires.count, 2)
        XCTAssertTrue(wires[0]["messages"].array!.first!["content"].string!.contains("意图分类器"))
        XCTAssertTrue(wires[1]["messages"].array!.first!["content"].string!.contains("只读询问"))
        XCTAssertTrue(wires.allSatisfy { $0["tools"] == .null })
        XCTAssertTrue(store.workspace.artifacts.isEmpty)
    }
    @MainActor func testScientificQuestionIsInReadOnlyAssistantContext() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("science-context-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try store(dir)
        let claim = ScienceClaim(kind: .hypothesis, text: "光照可能影响生长", confidence: 0.35)
        let question = ScientificQuestion(title: "光照是否影响生长？", claims: [claim])
        try store.saveScientificQuestion(question)
        XCTAssertEqual(try store.file.load()?.scientificQuestions.first?.claims.first?.text, claim.text)
        XCTAssertThrowsError(try store.saveScientificQuestion(question))
        MockModel.state.reset([(200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response("{\"answer\":\"目前只有一条假设，没有实验记录\",\"referenced_protocol_ids\":[]}"))])
        store.startAssistant("光照是否影响生长？目前有什么证据？")
        await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed)
        let wires = try MockModel.state.captured().map { try JSONDecoder().decode(JSONValue.self, from: $0.httpBody!) }
        let answerContext = wires[1]["messages"].array!.map { $0["content"].string ?? "" }.joined(separator: "\n")
        XCTAssertTrue(answerContext.contains(question.title))
        XCTAssertTrue(answerContext.contains(claim.text))
        XCTAssertTrue(answerContext.contains("确信度仅为自评"))
    }
    @MainActor func testTypedRoutesWithoutNativeToolsOrJSONMode() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fallback-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var model = store.workspace.models[0]; model.supportsTools = false; model.supportsJSON = false; try store.saveModel(model)
        MockModel.state.reset([(200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response("{\"answer\":\"已读取\",\"referenced_protocol_ids\":[]}"))])
        store.startAssistant("查看工作区"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed); XCTAssertEqual(store.activeSession?.messages.last?.content, "已读取")
        let wire = try JSONDecoder().decode(JSONValue.self, from: MockModel.state.captured()[0].httpBody!)
        XCTAssertEqual(wire["tools"], .null); XCTAssertEqual(wire["response_format"], .null)
    }
    @MainActor func testStructuredProtocolBuildKeepsHierarchyAndNeedsReview() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("protocol-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var content = ProtocolContent(blocks: [ProtocolBlock(title: "制备", subblocks: [ProtocolSubblock(title: "准备样品", steps: [ProtocolStep(title: "称量", minutes: 0)])]), ProtocolBlock(title: "测量", subblocks: [ProtocolSubblock(title: "读数", steps: [ProtocolStep(title: "测量", minutes: 20)])])]); content.renumber()
        content.objective = "测量样品的吸光度。"
        content.materials = [ProtocolMaterial(name: "样品", category: .sample, quantity: "待确认"), ProtocolMaterial(name: "酶标仪", category: .equipment, quantity: "1 台")]
        content.principles = ["吸光度反映样品对指定波长光的吸收。"]
        content.precautions = ["先确认测量波长与样品适用范围。"]
        let json = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
        MockModel.state.reset([(200, "application/json", try response(intent("protocol_generation"))), (200, "application/json", try response("{\"action\":\"generate\",\"name\":\"示例\",\"source\":\"说明\"}")), (200, "application/json", try response(json))])
        store.startAssistant("构建标准 Protocol", operation: .protocolDraft(name: "示例", source: "说明", procedureID: nil)); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.workspace.runs.last?.intent?.userIntent, .protocolGeneration)
        let artifact = try XCTUnwrap(store.workspace.artifacts.last)
        XCTAssertEqual(artifact.procedure?.currentVersion.content, content); XCTAssertEqual(store.workspace.procedures.count, 0)
        try store.saveProtocolArtifact(artifact.id, published: false); XCTAssertEqual(store.workspace.procedures[0].currentVersion.status, .draft)
        XCTAssertEqual(MockModel.state.captured().count, 3)
    }
    @MainActor func testScheduleIdempotencyLatestConflictAndStaleVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("schedule-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let p = Procedure(name: "测量", steps: [ProcedureStep(title: "操作", minutes: 30)]); try store.saveProcedure(p)
        let future = Date().addingTimeInterval(86400 * 2)
        let artifact = try store.scheduleArtifact(name: "实验", procedureID: p.id, date: future, preferences: SchedulePreferences())
        let candidate = artifact.candidates[0]
        try store.saveBusy(BusyInterval(title: "冲突", start: candidate.steps[0].start, end: candidate.steps[0].end))
        XCTAssertThrowsError(try store.applySchedule(artifactID: artifact.id, candidateID: candidate.id)); XCTAssertTrue(store.workspace.experiments.isEmpty)
        store.removeBusy(store.workspace.busyIntervals[0].id)
        let id = try store.applySchedule(artifactID: artifact.id, candidateID: candidate.id)
        XCTAssertEqual(try store.applySchedule(artifactID: artifact.id, candidateID: candidate.id), id); XCTAssertEqual(store.workspace.experiments.count, 1)
        let stale = try store.scheduleArtifact(name: "过期", procedureID: p.id, date: future, preferences: SchedulePreferences())
        var modified = store.workspace.procedures[0]; modified.versions.append(ProcedureVersion(number: 2, content: p.currentVersion.content)); try store.saveProcedure(modified)
        XCTAssertThrowsError(try store.applySchedule(artifactID: stale.id, candidateID: stale.candidates[0].id))
        XCTAssertEqual(store.workspace.experiments[0].versionID, p.currentVersion.id)
    }
    @MainActor func testBuilderRepairsMaterialsMisclassifiedAsSteps() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parts-repair-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var bad = ProtocolContent(blocks: [ProtocolBlock(title: "准备", subblocks: [ProtocolSubblock(title: "配液", steps: [ProtocolStep(title: "PBS", minutes: 5)])])])
        bad.objective = "配制工作液。"; bad.materials = [ProtocolMaterial(name: "PBS", quantity: "待确认")]; bad.renumber()
        var good = bad; good.blocks[0].subblocks[0].steps[0].title = "稀释 PBS 工作液"; good.blocks[0].subblocks[0].steps[0].description = "按已确认的目标浓度稀释。"
        let responses = try [bad, good].map { try response(String(decoding: JSONEncoder().encode($0), as: UTF8.self)) }
        MockModel.state.reset([(200, "application/json", try response(intent("protocol_generation"))), (200, "application/json", try response("{\"action\":\"generate\",\"name\":\"配液\",\"source\":\"PBS工作液\"}")), (200, "application/json", responses[0]), (200, "application/json", responses[1])])
        store.startAssistant("构建配液 Protocol"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.workspace.artifacts.last?.procedure?.currentVersion.content, good)
        XCTAssertEqual(MockModel.state.captured().count, 4)
        let repair = try JSONValue.decode(String(decoding: MockModel.state.captured().last!.httpBody!, as: UTF8.self))
        XCTAssertTrue(repair["messages"].array!.last!["content"].string!.contains("材料放 materials"))
        XCTAssertTrue(store.workspace.procedures.isEmpty)
    }
    @MainActor func testBuilderRejectsMissingDocumentPartsInsteadOfSilentlyDefaulting() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parts-missing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var content = ProtocolContent(blocks: [ProtocolBlock(title: "准备", subblocks: [ProtocolSubblock(title: "称量", steps: [ProtocolStep(title: "称量样品", minutes: 5)])])]); content.renumber()
        var raw = try XCTUnwrap(JSONValue.decode(String(decoding: JSONEncoder().encode(content), as: UTF8.self)).object)
        for key in ["objective", "materials", "principles", "precautions"] { raw.removeValue(forKey: key) }
        let reply = try response(JSONValue.object(raw).text())
        MockModel.state.reset([(200, "application/json", try response(intent("protocol_generation"))), (200, "application/json", try response("{\"action\":\"generate\",\"name\":\"示例\",\"source\":\"称量样品\"}")), (200, "application/json", reply), (200, "application/json", reply)])
        store.startAssistant("生成示例 Protocol"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .failed)
        XCTAssertTrue(store.workspace.runs.last?.error?.contains("五部分") == true || store.workspace.runs.last?.error?.contains("objective") == true)
        XCTAssertTrue(store.workspace.artifacts.isEmpty); XCTAssertTrue(store.workspace.procedures.isEmpty)
    }
    @MainActor func testBuilderRepairsMaterialTypeWithExactFieldPath() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parts-type-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var good = ProtocolContent(blocks: [ProtocolBlock(title: "制备", subblocks: [ProtocolSubblock(title: "配液", steps: [ProtocolStep(title: "稀释缓冲液", minutes: 5)])])]); good.renumber()
        good.objective = "制备缓冲工作液。"; good.materials = [ProtocolMaterial(name: "缓冲液", quantity: "10 mL")]
        var json = try XCTUnwrap(JSONValue.decode(String(decoding: JSONEncoder().encode(good), as: UTF8.self)).object)
        var material = try XCTUnwrap(json["materials"]?.array?.first?.object)
        material["quantity"] = .number(10); json["materials"] = .array([.object(material)])
        MockModel.state.reset([(200, "application/json", try response(intent("protocol_generation"))), (200, "application/json", try response("{\"action\":\"generate\",\"name\":\"配液\",\"source\":\"缓冲液10mL\"}")), (200, "application/json", try response(JSONValue.object(json).text())), (200, "application/json", try response(String(decoding: JSONEncoder().encode(good), as: UTF8.self)))])
        store.startAssistant("构建配液 Protocol"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        XCTAssertEqual(store.workspace.artifacts.last?.procedure?.currentVersion.content, good)
        let repair = try JSONValue.decode(String(decoding: MockModel.state.captured().last!.httpBody!, as: UTF8.self))
        let message = try XCTUnwrap(repair["messages"].array?.last?["content"].string)
        XCTAssertTrue(message.contains("materials")); XCTAssertTrue(message.contains("quantity")); XCTAssertTrue(message.contains("类型错误"))
    }
    @MainActor func testMaterialChecksPersistWithoutMutatingHistoricalVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("material-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var content = ProtocolContent(blocks: [ProtocolBlock(title: "制备", subblocks: [ProtocolSubblock(title: "配液", steps: [ProtocolStep(title: "稀释", minutes: 5)])])]); content.renumber()
        content.materials = [ProtocolMaterial(name: "缓冲液", quantity: "待确认")]
        let procedure = Procedure(name: "配液", content: content, status: .published)
        try store.saveProcedure(procedure)
        let version = procedure.currentVersion, material = content.materials[0]
        try store.setMaterialPrepared(material.id, versionID: version.id, prepared: true)
        try store.setMaterialPrepared(material.id, versionID: version.id, prepared: true)
        XCTAssertEqual(store.workspace.materialPreparation[version.id.uuidString], [material.id])
        XCTAssertEqual(store.workspace.procedures[0].versions, procedure.versions)
        XCTAssertEqual(try store.file.load()?.materialPreparation, store.workspace.materialPreparation)
        let restarted = PersonalStore(directory: dir, demo: false)
        XCTAssertEqual(restarted.workspace.materialPreparation[version.id.uuidString], [material.id])
        XCTAssertThrowsError(try store.setMaterialPrepared("unknown-material", versionID: version.id, prepared: true))
        XCTAssertThrowsError(try store.setMaterialPrepared(material.id, versionID: UUID(), prepared: true))
        try store.setMaterialPrepared(material.id, versionID: version.id, prepared: false)
        XCTAssertNil(store.workspace.materialPreparation[version.id.uuidString])
    }
    @MainActor func testHistoricalVersionsCannotBeOverwrittenAndRestartInterrupts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var p = Procedure(name: "原版", steps: [ProcedureStep(title: "操作", minutes: 30)]); try store.saveProcedure(p)
        p.versions[0].content.blocks[0].title = "偷偷覆盖"; XCTAssertThrowsError(try store.saveProcedure(p))
        let session = try store.newSession(); try store.commit { $0.runs.append(AssistantRun(sessionID: session, input: "未完成", modelID: nil, modelName: "模型")) }
        let reopened = PersonalStore(directory: dir, demo: false); XCTAssertEqual(reopened.workspace.runs.last?.status, .interrupted)
    }
    @MainActor func testCancelDuringWriteConfirmationDoesNotCreateExperiment() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let p = Procedure(name: "测试", steps: [ProcedureStep(title: "操作", minutes: 30)]); try store.saveProcedure(p)
        let artifact = try store.scheduleArtifact(name: "实验", procedureID: p.id, date: Date().addingTimeInterval(86400), preferences: SchedulePreferences())
        let args = try scheduleJSON(["action": .string("apply"), "artifact_id": .string(artifact.id.uuidString)])
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(args))])
        store.startAssistant("采用排程")
        for _ in 0..<200 { if store.pendingApproval != nil || store.runningRunID == nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(store.pendingApproval); XCTAssertTrue(store.workspace.experiments.isEmpty)
        store.cancelAssistant(); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .cancelled); XCTAssertTrue(store.workspace.experiments.isEmpty); XCTAssertNil(store.pendingApproval)
    }
    @MainActor func testConfirmedWriteCreatesExactlyOneExperiment() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("confirm-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let p = Procedure(name: "测试", steps: [ProcedureStep(title: "操作", minutes: 30)]); try store.saveProcedure(p)
        let artifact = try store.scheduleArtifact(name: "实验", procedureID: p.id, date: Date().addingTimeInterval(86400), preferences: SchedulePreferences())
        let args = try scheduleJSON(["action": .string("apply"), "artifact_id": .string(artifact.id.uuidString)])
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(args))])
        store.startAssistant("采用排程")
        for _ in 0..<200 { if store.pendingApproval != nil || store.runningRunID == nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(store.pendingApproval); store.approveTool(true); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed); XCTAssertEqual(store.workspace.experiments.count, 1)
        _ = try store.applySchedule(artifactID: artifact.id, candidateID: artifact.candidates[0].id); XCTAssertEqual(store.workspace.experiments.count, 1)
    }
    @MainActor func testEndToEndBuildSaveScheduleAndApply() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("e2e-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var content = ProtocolContent(blocks: [ProtocolBlock(title: "阶段", subblocks: [ProtocolSubblock(title: "分组", steps: [ProtocolStep(title: "操作", minutes: 30)])])]); content.renumber()
        content.objective = "验证完整构建与排程流程。"
        let tree = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
        let request = try scheduleJSON(["action": .string("generate"), "experiment_name": .string("完整实验"), "new_protocol": .object(["name": .string("完整工作流"), "source": .string("操作30分钟，保留三层")]), "apply_after_generation": .bool(true)])
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(request)), (200, "application/json", try response(tree))])
        store.startAssistant("构建 Protocol，创建实验并安排时间")
        var approvals = 0
        for _ in 0..<400 {
            if store.pendingApproval != nil { approvals += 1; store.approveTool(true) }
            if store.runningRunID == nil { break }; try await Task.sleep(for: .milliseconds(5))
        }
        if store.runningRunID != nil { store.cancelAssistant() }; await store.runningTask?.value
        XCTAssertEqual(approvals, 2); XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        let procedure = try XCTUnwrap(store.workspace.procedures.first)
        let plan = try XCTUnwrap(store.workspace.plan.first)
        XCTAssertEqual(store.workspace.procedures.count, 1); XCTAssertEqual(store.workspace.experiments.count, 1)
        XCTAssertEqual(store.workspace.plan.count, 1); XCTAssertEqual(procedure.currentVersion.content, content)
        XCTAssertEqual(plan.stepID, content.atomicSteps[0].id)
        XCTAssertEqual(try store.file.load()?.experiments, store.workspace.experiments)
        XCTAssertEqual(MockModel.state.captured().count, 3) // No LLM-generated timestamps or tool loop.
    }
    @MainActor func testAskingWhatProtocolIsUsesRealTreeAndNeverCreatesDraft() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qa-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let procedure = Procedure(name: "样本处理", steps: [ProcedureStep(title: "离心", minutes: 10)]); try store.saveProcedure(procedure)
        let answer = try JSONValue.object(["answer": .string("样本处理的 Protocol 包含离心 10 分钟。"), "referenced_protocol_ids": .array([.string(procedure.id.uuidString)])]).text()
        MockModel.state.reset([(200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response(answer))])
        store.startAssistant("这个样本处理的 protocol 是什么？"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed); XCTAssertTrue(store.workspace.artifacts.isEmpty); XCTAssertEqual(store.workspace.procedures.count, 1)
        let wire = try JSONDecoder().decode(JSONValue.self, from: MockModel.state.captured()[1].httpBody!)
        let system = try XCTUnwrap(wire["messages"].array?.first?["content"].string)
        XCTAssertTrue(system.contains("离心")); XCTAssertTrue(system.contains("schema_version")); XCTAssertTrue(system.contains("只读"))
        XCTAssertTrue(IntentPrompts.classifier.contains("这个的 protocol 是什么"))
    }
    @MainActor func testInvalidIntentIsRepairedBeforeDispatch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("repair-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        MockModel.state.reset([(200, "application/json", try response(intent("delete_workspace"))), (200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response("{\"answer\":\"你好\",\"referenced_protocol_ids\":[]}"))])
        store.startAssistant("你好"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed); XCTAssertEqual(MockModel.state.captured().count, 3)
        XCTAssertEqual(store.workspace.runs.last?.intent?.userIntent, .questionAnswer); XCTAssertTrue(store.workspace.artifacts.isEmpty)
    }
    @MainActor func testUnknownIntentTwiceFailsClosedWithoutBranch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        MockModel.state.reset([(200, "application/json", try response(intent("run_shell"))), (200, "application/json", try response(intent("run_shell")))])
        store.startAssistant("帮我看看"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .failed); XCTAssertNil(store.workspace.runs.last?.intent)
        XCTAssertTrue(store.workspace.artifacts.isEmpty); XCTAssertTrue(store.workspace.experiments.isEmpty); XCTAssertEqual(MockModel.state.captured().count, 2)
    }
    @MainActor func testQuestionAnswerRejectsInjectedWriteFields() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qa-write-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let bad = "{\"answer\":\"已采用\",\"referenced_protocol_ids\":[],\"calls\":[{\"name\":\"apply_schedule\"}]}"
        MockModel.state.reset([(200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response(bad)), (200, "application/json", try response(bad))])
        store.startAssistant("解释这个排程"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .failed); XCTAssertTrue(store.workspace.experiments.isEmpty); XCTAssertTrue(store.workspace.artifacts.isEmpty); XCTAssertNil(store.pendingApproval)
    }
    @MainActor func testSchedulingMissingProtocolAsksForInformationNotAMode() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(scheduleJSON([:])))])
        store.startAssistant("帮我安排明天的实验"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed)
        XCTAssertTrue(store.activeSession?.messages.last?.content.contains("哪项实验") == true)
        XCTAssertFalse(store.activeSession?.messages.last?.content.contains("选择功能") == true); XCTAssertTrue(store.workspace.artifacts.isEmpty)
    }
    @MainActor func testEveryTurnReclassifiesAndCarriesConversationHistory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("turns-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        MockModel.state.reset([(200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response("{\"answer\":\"PCR 是扩增方法\",\"referenced_protocol_ids\":[]}")), (200, "application/json", try response(intent("protocol_generation"))), (200, "application/json", try response("{\"action\":\"generate\",\"clarification\":\"请提供样本和实验步骤要求。\"}"))])
        store.startAssistant("PCR 是什么"); await store.runningTask?.value
        store.startAssistant("那请生成标准 Protocol"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.map { $0.intent?.userIntent }, [.questionAnswer, .protocolGeneration])
        XCTAssertEqual(MockModel.state.captured().count, 4)
        let wire = try JSONDecoder().decode(JSONValue.self, from: MockModel.state.captured()[2].httpBody!)
        XCTAssertTrue(wire["messages"].array!.contains { $0["role"].string == "assistant" && $0["content"].string == "PCR 是扩增方法" })
    }
    @MainActor func testSchedulingUsesDedicatedModelAndHardConstraints() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var model = ModelProfile(connectionID: store.workspace.connections[0].id, name: "规划模型", model: "planner-model"); model.stream = false; try store.saveModel(model)
        var routing = store.workspace.routing; routing.scheduling = model.id; try store.saveRouting(routing)
        let p = Procedure(name: "测量", steps: [ProcedureStep(title: "检测", minutes: 30)]); try store.saveProcedure(p)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let day = calendar.startOfDay(for: Date().addingTimeInterval(86400 * 3))
        let begin = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!, busyEnd = begin.addingTimeInterval(3600)
        let formatter = ISO8601DateFormatter()
        let args = try scheduleJSON(["procedure_id": .string(p.id.uuidString), "start_time": .string(formatter.string(from: begin)), "latest_finish": .string(formatter.string(from: begin.addingTimeInterval(7200))), "allow_overnight": .bool(false), "blocked_times": .array([.object(["title": .string("会议"), "start": .string(formatter.string(from: begin)), "end": .string(formatter.string(from: busyEnd))])])])
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(args))])
        store.startAssistant("明天安排测量，避开9–10点会议，11点前完成，不允许过夜"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed, store.workspace.runs.last?.error ?? "")
        let candidate = try XCTUnwrap(store.workspace.artifacts.last?.candidates.first)
        XCTAssertEqual(candidate.steps.first?.start, busyEnd); XCTAssertFalse(candidate.preferences.allowOvernight)
        XCTAssertEqual(candidate.additionalBusyIntervals?.count, 1); XCTAssertNotNil(candidate.latestFinish)
        XCTAssertTrue(store.workspace.busyIntervals.isEmpty); XCTAssertTrue(store.workspace.plan.isEmpty)
        let wires = try MockModel.state.captured().map { try JSONDecoder().decode(JSONValue.self, from: $0.httpBody!) }
        XCTAssertEqual(wires[0]["model"].string, "mock-model"); XCTAssertEqual(wires[1]["model"].string, "planner-model")
        XCTAssertEqual(wires.count, 2); XCTAssertTrue(store.workspace.runs.last!.events.contains { $0.title.contains("经典算法") })
    }
    @MainActor func testScheduleRejectsLLMGeneratedTimestamps() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("timestamps-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let bad = try scheduleJSON(["steps": .array([.object(["start": .string("tomorrow")])])])
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(bad)), (200, "application/json", try response(bad))])
        store.startAssistant("安排实验"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .failed); XCTAssertTrue(store.workspace.plan.isEmpty); XCTAssertTrue(store.workspace.artifacts.isEmpty)
    }
    @MainActor func testUnknownProtocolDurationReturnsUsefulConversation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("duration-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let p = Procedure(name: "待确认", steps: [ProcedureStep(title: "检测", minutes: 0)]); try store.saveProcedure(p)
        let args = try scheduleJSON(["procedure_id": .string(p.id.uuidString)])
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(args))])
        store.startAssistant("安排待确认实验"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed)
        XCTAssertTrue(store.activeSession?.messages.last?.content.contains("耗时未知") == true); XCTAssertTrue(store.workspace.artifacts.isEmpty)
    }
    @MainActor func testNaturalSaveProtocolIsClassifiedAndConfirmed() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var artifact = AssistantArtifact(kind: .protocolDraft, title: "草稿"); artifact.procedure = Procedure(name: "草稿", steps: [ProcedureStep(title: "测量", minutes: 20)])
        try store.commit { $0.artifacts.append(artifact) }
        let args = try JSONValue.object(["action": .string("save"), "artifact_id": .string(artifact.id.uuidString), "published": .bool(true)]).text()
        MockModel.state.reset([(200, "application/json", try response(intent("protocol_generation"))), (200, "application/json", try response(args))])
        store.startAssistant("保存刚才的草稿，确认为可排程版本")
        for _ in 0..<200 { if store.pendingApproval != nil || store.runningRunID == nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(store.pendingApproval); XCTAssertTrue(store.workspace.procedures.isEmpty)
        store.approveTool(true); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed); XCTAssertEqual(store.workspace.procedures.first?.currentVersion.status, .published)
    }
    @MainActor func testRevisingCandidateKeepsUnchangedHardConstraints() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("revise-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let p = Procedure(name: "测量", steps: [ProcedureStep(title: "检测", minutes: 30)]); try store.saveProcedure(p)
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400 * 3))
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day)!, deadline = start.addingTimeInterval(10800)
        let busy = BusyInterval(title: "会议", start: start, end: start.addingTimeInterval(3600))
        var preferences = SchedulePreferences(); preferences.allowOvernight = false
        let original = try store.scheduleArtifact(name: "原实验", procedureID: p.id, date: start, preferences: preferences, latestFinish: deadline, additionalBusyIntervals: [busy])
        let args = try scheduleJSON(["action": .string("revise"), "artifact_id": .string(original.id.uuidString), "start_time": .string(ISO8601DateFormatter().string(from: start.addingTimeInterval(1800)))])
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(args))])
        store.startAssistant("刚才的安排稍微推迟，其他要求不变"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed)
        let revised = try XCTUnwrap(store.workspace.artifacts.last?.candidates.first)
        XCTAssertEqual(store.workspace.artifacts.count, 2); XCTAssertEqual(revised.latestFinish, deadline)
        XCTAssertEqual(revised.additionalBusyIntervals, [busy]); XCTAssertFalse(revised.preferences.allowOvernight)
        XCTAssertEqual(revised.steps.first?.start, busy.end); XCTAssertTrue(store.workspace.experiments.isEmpty)
    }
    @MainActor func testNaturalSecondCandidateAdoptsSpecifiedPlan() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("second-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var step = ProtocolStep(title: "孵育", minutes: 300); step.canPause = true; step.unattended = true; step.overnightSafe = true
        var content = ProtocolContent(blocks: [ProtocolBlock(title: "制备", subblocks: [ProtocolSubblock(title: "反应", steps: [step])])]); content.renumber()
        let p = Procedure(name: "孵育", content: content, status: .published); try store.saveProcedure(p)
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400 * 3)), start = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: day)!
        let artifact = try store.scheduleArtifact(name: "孵育实验", procedureID: p.id, date: start, preferences: SchedulePreferences())
        XCTAssertEqual(artifact.candidates.count, 2); let second = try XCTUnwrap(artifact.candidates.dropFirst().first)
        let sessionID = try store.newSession(); try store.commit { w in
            let i = w.sessions.firstIndex { $0.id == sessionID }!; w.sessions[i].messages.append(ChatMessage(role: "assistant", content: "这是两个安排", artifactIDs: [artifact.id]))
        }
        MockModel.state.reset([(200, "application/json", try response(intent("schedule"))), (200, "application/json", try response(scheduleJSON(["action": .string("apply"), "artifact_id": .string(artifact.id.uuidString), "candidate_id": .string(second.id.uuidString)])))])
        store.startAssistant("采用第二个方案")
        for _ in 0..<200 { if store.pendingApproval != nil || store.runningRunID == nil { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(store.pendingApproval?.contains(second.label) == true); store.approveTool(true); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed); XCTAssertEqual(store.workspace.plan, second.steps)
    }
    @MainActor func testReportEntryAlsoClassifiesBeforeReadOnlySummary() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let p = Procedure(name: "测量", steps: [ProcedureStep(title: "检测", minutes: 30)]); try store.saveProcedure(p)
        try store.addExperiment(name: "记录实验", procedureID: p.id, date: Date().addingTimeInterval(86400 * 2))
        let experimentID = try XCTUnwrap(store.workspace.experiments.first?.id); try store.saveNote(experimentID, "观察记录：未检测到信号")
        let originalArtifacts = store.workspace.artifacts.count
        MockModel.state.reset([(200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response("{\"answer\":\"记录显示未检测到信号，不等于没有样本。\",\"referenced_protocol_ids\":[]}"))])
        store.startAssistant("总结该实验", operation: .report(experimentID)); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.intent?.userIntent, .questionAnswer); XCTAssertEqual(store.workspace.artifacts.count, originalArtifacts)
        let payload = try JSONDecoder().decode(JSONValue.self, from: MockModel.state.captured()[1].httpBody!)
        XCTAssertTrue(payload["messages"].array!.first!["content"].string!.contains("未检测到信号"))
    }
    @MainActor func testProtocolBuilderRejectsFlatOutputInsteadOfFlatteningTree() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("flat-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let flat = "{\"steps\":[{\"title\":\"测量\",\"minutes\":30}]}"
        MockModel.state.reset([(200, "application/json", try response(intent("protocol_generation"))), (200, "application/json", try response("{\"action\":\"generate\",\"name\":\"测量\",\"source\":\"测量30分钟\"}")), (200, "application/json", try response(flat)), (200, "application/json", try response(flat))])
        store.startAssistant("生成三层标准 Protocol"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .failed); XCTAssertTrue(store.workspace.artifacts.isEmpty); XCTAssertTrue(store.workspace.procedures.isEmpty)
    }
    @MainActor func testQuestionCanReadCurrentSessionDraftWithoutCreatingAnother() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("draft-qa-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        var artifact = AssistantArtifact(kind: .protocolDraft, title: "未保存草稿"); let p = Procedure(name: "未保存草稿", steps: [ProcedureStep(title: "离心", minutes: 15)]); artifact.procedure = p
        let session = try store.newSession(); try store.commit { w in
            w.artifacts.append(artifact); let index = w.sessions.firstIndex { $0.id == session }!
            w.sessions[index].messages.append(ChatMessage(role: "assistant", content: "草稿已生成", artifactIDs: [artifact.id]))
        }
        let answer = try JSONValue.object(["answer": .string("草稿的离心步骤为15分钟，尚未保存为正式版本。"), "referenced_protocol_ids": .array([.string(p.id.uuidString)])]).text()
        MockModel.state.reset([(200, "application/json", try response(intent("question_answer"))), (200, "application/json", try response(answer))])
        store.startAssistant("刚才这个 protocol 的离心是多久"); await store.runningTask?.value
        XCTAssertEqual(store.workspace.runs.last?.status, .completed); XCTAssertEqual(store.workspace.artifacts.count, 1); XCTAssertTrue(store.workspace.procedures.isEmpty)
        let wire = try JSONDecoder().decode(JSONValue.self, from: MockModel.state.captured()[1].httpBody!)
        XCTAssertTrue(wire["messages"].array!.first!["content"].string!.contains("离心"))
    }
    @MainActor func testLegacyRunAndCandidateDecodeWithoutNewFields() throws {
        let run = AssistantRun(sessionID: UUID(), input: "旧任务", modelID: nil, modelName: "旧模型")
        var json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(run)).object!
        json.removeValue(forKey: "intent")
        XCTAssertNil(try JSONDecoder().decode(AssistantRun.self, from: JSONEncoder().encode(JSONValue.object(json))).intent)
        let p = Procedure(name: "旧版", steps: [ProcedureStep(title: "测量", minutes: 20)])
        let candidate = ScheduleCandidate(procedure: p, experiment: Experiment(name: "旧版", procedureID: p.id), steps: [], preferences: SchedulePreferences(), label: "旧候选", rationale: "旧记录")
        var c = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(candidate)).object!
        for key in ["objective", "notBefore", "latestFinish", "additionalBusyIntervals"] { c.removeValue(forKey: key) }
        let loaded = try JSONDecoder().decode(ScheduleCandidate.self, from: JSONEncoder().encode(JSONValue.object(c)))
        XCTAssertNil(loaded.objective); XCTAssertNil(loaded.additionalBusyIntervals)
    }
    @MainActor func testBackupRestorePreservesPreRestoreSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID())"); defer { try? FileManager.default.removeItem(at: dir) }; let store = try store(dir)
        let backup = dir.appendingPathComponent("export.json"); try store.file.export(store.workspace, to: backup)
        try store.saveInstrument(Instrument(name: "新仪器")); try store.restore(backup)
        XCTAssertTrue(store.workspace.instruments.isEmpty)
        let snapshot = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("before-restore-") })
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: snapshot)).instruments.count, 1)
    }
    func testStreamingToolFragmentsAndTokenParameter() async throws {
        let connection = ProviderConnection(baseURL: "http://localhost:1234/v1"); var model = ModelProfile(connectionID: connection.id, model: "mock"); model.tokenParameter = "max_completion_tokens"; model.temperature = nil
        let sse = """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"read_workspace","arguments":"{"}}]}}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"}"}}]},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """
        MockModel.state.reset([(200, "text/event-stream", sse)])
        let reply = try await ModelClient.complete(connection: connection, model: model, apiKey: nil, messages: [], using: session())
        XCTAssertEqual(reply.toolCalls[0].function.arguments, "{}"); XCTAssertEqual(reply.toolCalls[0].function.name, "read_workspace")
        let body = try JSONDecoder().decode(JSONValue.self, from: MockModel.state.captured()[0].httpBody!)
        XCTAssertEqual(body["max_completion_tokens"].int, 4096); XCTAssertEqual(body["temperature"], .null)
    }
    func testHTTPErrorRedactsKeyAndTruncatedStreamFails() async throws {
        let c = ProviderConnection(baseURL: "http://localhost:1234/v1"); var m = ModelProfile(connectionID: c.id, model: "mock"); m.stream = false
        MockModel.state.reset([(429, "application/json", "{\"error\":{\"message\":\"secret-key exceeded\"}}")])
        do { _ = try await ModelClient.complete(connection: c, model: m, apiKey: "secret-key", messages: [], using: session()); XCTFail() } catch { XCTAssertFalse(error.localizedDescription.contains("secret-key")) }
        m.stream = true; MockModel.state.reset([(200, "text/event-stream", "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n")])
        do { _ = try await ModelClient.complete(connection: c, model: m, apiKey: nil, messages: [], using: session()); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("中断")) }
    }
}
