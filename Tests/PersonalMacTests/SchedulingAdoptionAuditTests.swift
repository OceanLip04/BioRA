import Foundation
import XCTest
import PersonalCore
@testable import PersonalMac

final class SchedulingAdoptionAuditTests: XCTestCase {
    private func directory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/TestWorkspaces/scheduling-audit-\(UUID())", isDirectory: true)
    }
    @MainActor func testInstrumentBecomingUnavailableRejectsAdoptionWithoutWritingExperiment() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        var instrument = Instrument(name: "Detector"); try store.saveInstrument(instrument)
        let p = Procedure(name: "Measurement", steps: [ProcedureStep(title: "Read", minutes: 30, instrumentID: instrument.id)])
        try store.saveProcedure(p)
        let artifact = try store.scheduleArtifact(name: "Audit", procedureID: p.id, date: Date().addingTimeInterval(86400), preferences: SchedulePreferences())
        instrument.available = false; try store.saveInstrument(instrument)
        let before = store.workspace
        XCTAssertThrowsError(try store.applySchedule(artifactID: artifact.id, candidateID: artifact.candidates[0].id))
        XCTAssertEqual(store.workspace, before)
        XCTAssertEqual(try store.file.load(), before)
    }

    @MainActor func testExpiredUnadoptedCandidateMustNotCreateAnExperimentInThePast() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let p = Procedure(name: "Measurement", steps: [ProcedureStep(title: "Read", minutes: 30)])
        try store.saveProcedure(p)
        // Reconstruct a saved, never-adopted candidate from yesterday. No clock sleeps,
        // real workspace, credentials, or model service are involved.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: yesterday)!
        var artifact = AssistantArtifact(kind: .schedule, title: "Expired candidate")
        artifact.candidates = try Planner.candidates(name: "Audit", procedure: p, workspace: store.workspace,
            starting: start, preferences: SchedulePreferences())
        try store.commit { $0.artifacts.append(artifact) }
        let before = store.workspace
        XCTAssertLessThan(try XCTUnwrap(artifact.candidates[0].steps.last?.end), Date())
        XCTAssertThrowsError(try store.applySchedule(artifactID: artifact.id, candidateID: artifact.candidates[0].id),
            "A candidate whose entire schedule has expired must require regeneration.")
        XCTAssertTrue(store.workspace == before, "Rejecting expired adoption must not change the workspace.")
    }
}
