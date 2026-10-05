import Foundation
import XCTest
import PersonalCore
@testable import PersonalMac

final class ExperimentTimingStoreTests: XCTestCase {
    private func directory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/TestWorkspaces/timing-\(UUID())", isDirectory: true)
    }
    @MainActor private func seed(_ store: PersonalStore) throws -> (Procedure, StepTimingConfiguration) {
        let procedure = Procedure(name: "Preparation", steps: [ProcedureStep(title: "Pipette", minutes: 20)])
        try store.saveProcedure(procedure)
        let original = StepTimingConfiguration(versionID: procedure.currentVersion.id, step: procedure.currentVersion.content.atomicSteps[0])
        var config = original; config.mode = .learnedSamples; config.referenceSampleCount = 4
        try store.saveTimingConfiguration(config, expected: original)
        return (procedure, config)
    }
    @MainActor private func addRecordedRun(_ store: PersonalStore, procedure: Procedure, minutes: Double) throws {
        var experiment = Experiment(name: "Measured", procedureID: procedure.id, versionID: procedure.currentVersion.id)
        experiment.sampleCount = 4; experiment.status = .completed
        experiment.stepTimings = [StepTimingRecord(stepID: procedure.currentVersion.content.atomicSteps[0].id, actualMinutes: minutes)]
        let value = experiment
        try store.commit { $0.experiments.append(value) }
    }
    @MainActor func testCalibrationPersistsWithoutChangingRecipeVersionOrRevision() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let (procedure, config) = try seed(store)
        XCTAssertEqual(store.workspace.procedures[0], procedure)
        XCTAssertEqual(try store.file.load()?.stepTimingConfigurations, [config])
        let loaded = PersonalStore(directory: dir, demo: false)
        XCTAssertEqual(loaded.workspace.stepTimingConfigurations, [config]); XCTAssertFalse(loaded.readOnly)
        XCTAssertEqual(loaded.workspace.procedures[0], procedure)
    }
    @MainActor func testCreatesProtocolDerivedExperimentWithExplicitSamplesAndSnapshot() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let (procedure, _) = try seed(store)
        try store.addExperiment(name: "Eight samples", procedureID: procedure.id, date: Date().addingTimeInterval(86400), sampleCount: 8)
        let experiment = try XCTUnwrap(store.workspace.experiments.first)
        XCTAssertEqual(experiment.sampleCount, 8); XCTAssertEqual(experiment.scheduledSampleCount, 8)
        XCTAssertEqual(experiment.versionID, procedure.currentVersion.id)
        XCTAssertEqual(experiment.durationEstimates[0].planningMinutes, 40)
        XCTAssertTrue(experiment.stepTimings.isEmpty, "A plan must never fabricate actual timings.")
        XCTAssertEqual(store.workspace.plan.reduce(0) { $0 + $1.minutes }, 40)
    }
    @MainActor func testActualRecordingPreservesCalendarAndLearnsOnlyAfterCompletion() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let (procedure, _) = try seed(store)
        for duration in [8.0, 10] { try addRecordedRun(store, procedure: procedure, minutes: duration) }
        let artifact = try store.scheduleArtifact(name: "Third run", procedureID: procedure.id,
            date: Date().addingTimeInterval(86400), preferences: SchedulePreferences(), sampleCount: 4)
        let experimentID = try store.applySchedule(artifactID: artifact.id, candidateID: artifact.candidates[0].id)
        let experiment = try XCTUnwrap(store.workspace.experiments.first { $0.id == experimentID })
        let plan = store.workspace.plan, estimates = experiment.durationEstimates
        let record = StepTimingRecord(stepID: procedure.currentVersion.content.atomicSteps[0].id, actualMinutes: 12)
        try store.saveExperimentTimings(experimentID, sampleCount: 4, records: [record], note: "Measured", expected: experiment)
        XCTAssertEqual(try ProtocolTiming.estimates(version: procedure.currentVersion, sampleCount: 4, workspace: store.workspace)[0].source, .scaledBaseline)
        store.setStatus(experimentID, .completed)
        let updated = try ProtocolTiming.estimates(version: procedure.currentVersion, sampleCount: 4, workspace: store.workspace)[0]
        XCTAssertEqual(updated.source, .history); XCTAssertEqual(updated.typicalMinutes, 10); XCTAssertEqual(updated.planningMinutes, 12)
        XCTAssertEqual(store.workspace.plan, plan)
        XCTAssertEqual(store.workspace.experiments.last?.durationEstimates, estimates)
        XCTAssertEqual(store.workspace.procedures.first, procedure)
        XCTAssertEqual(try store.applySchedule(artifactID: artifact.id, candidateID: artifact.candidates[0].id), experimentID)
        XCTAssertEqual(store.workspace.experiments.count, 3)
    }
    @MainActor func testInvalidTimingSaveIsAtomicAndDoesNotChangeDatabase() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let (procedure, _) = try seed(store)
        try store.addExperiment(name: "Run", procedureID: procedure.id, date: Date().addingTimeInterval(86400), sampleCount: 4)
        let experiment = try XCTUnwrap(store.workspace.experiments.first), before = store.workspace
        for badRecord in [StepTimingRecord(stepID: "wrong", actualMinutes: 2),
                          StepTimingRecord(stepID: procedure.currentVersion.content.atomicSteps[0].id, actualMinutes: 0)] {
            XCTAssertThrowsError(try store.saveExperimentTimings(experiment.id, sampleCount: 4, records: [badRecord], note: "Invalid", expected: experiment))
        }
        XCTAssertThrowsError(try store.saveExperimentTimings(experiment.id, sampleCount: 0, records: [], note: "", expected: experiment))
        XCTAssertEqual(store.workspace, before); XCTAssertEqual(try store.file.load(), before)
    }
    @MainActor func testConflictingExperimentEditsCannotOverwriteNewRecords() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let (procedure, _) = try seed(store)
        try store.addExperiment(name: "Run", procedureID: procedure.id, date: Date().addingTimeInterval(86400), sampleCount: 4)
        let original = try XCTUnwrap(store.workspace.experiments.first)
        store.setStatus(original.id, .active)
        let before = store.workspace
        XCTAssertThrowsError(try store.saveExperimentTimings(original.id, sampleCount: 4, records: [], note: "Stale edit", expected: original))
        XCTAssertEqual(store.workspace, before)
    }
    @MainActor func testChangedCalibrationRejectsUnadoptedCandidateWithoutWriting() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let (procedure, config) = try seed(store)
        let artifact = try store.scheduleArtifact(name: "Candidate", procedureID: procedure.id,
            date: Date().addingTimeInterval(86400), preferences: SchedulePreferences(), sampleCount: 4)
        var changed = config; changed.baselineMinutes = 25
        try store.saveTimingConfiguration(changed, expected: config)
        let before = store.workspace
        XCTAssertThrowsError(try store.applySchedule(artifactID: artifact.id, candidateID: artifact.candidates[0].id))
        XCTAssertEqual(store.workspace, before); XCTAssertTrue(store.workspace.experiments.isEmpty)
    }
    @MainActor func testFixedPolicyCannotShortenRecipeAndConfigCASProtectsChanges() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let (_, config) = try seed(store)
        let before = store.workspace
        var unsafe = config; unsafe.mode = .fixed; unsafe.baselineMinutes = 1
        XCTAssertThrowsError(try store.saveTimingConfiguration(unsafe, expected: config))
        XCTAssertEqual(store.workspace, before)
        var changed = config; changed.baselineMinutes = 22
        try store.saveTimingConfiguration(changed, expected: config)
        XCTAssertThrowsError(try store.saveTimingConfiguration(config, expected: config))
        XCTAssertEqual(store.workspace.stepTimingConfigurations, [changed])
    }
    @MainActor func testReadOnlyWorkspaceCannotRecordOrCalibrate() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = PersonalStore(directory: dir, demo: false)
        let (_, config) = try seed(store)
        let readOnly = PersonalStore(previewDirectory: dir, previewWorkspace: store.workspace)
        XCTAssertThrowsError(try readOnly.saveTimingConfiguration(config, expected: config))
    }
    @MainActor func testFictionalTimingPreviewIsValidWithoutDatabaseAccess() throws {
        let workspace = try Workspace.experimentTimingPreview()
        try workspace.validated()
        XCTAssertTrue(workspace.isDemo)
        XCTAssertEqual(workspace.experiments.count, 7)
        XCTAssertEqual(workspace.experiments.last?.scheduledSampleCount, 8)
        XCTAssertEqual(workspace.experiments.last?.durationEstimates[0].source, .interpolated)
    }
}
