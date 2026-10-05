import Foundation
import XCTest
@testable import PersonalCore

final class ProtocolTimingTests: XCTestCase {
    private func fixture(mode: StepTimingMode = .learnedSamples) -> (Workspace, Procedure, String) {
        var workspace = Workspace()
        let procedure = Procedure(name: "Sample preparation", steps: [
            ProcedureStep(title: "Pipette samples", minutes: 10), ProcedureStep(title: "Prescribed incubation", minutes: 30)
        ])
        workspace.procedures = [procedure]
        let step = procedure.currentVersion.content.atomicSteps[0]
        var config = StepTimingConfiguration(versionID: procedure.currentVersion.id, step: step)
        config.mode = mode; config.referenceSampleCount = 4
        workspace.stepTimingConfigurations = [config]
        return (workspace, procedure, step.id)
    }
    private func recorded(_ procedure: Procedure, stepID: String, samples: Int, minutes: Double,
                          status: ExperimentStatus = .completed, included: Bool = true) -> Experiment {
        var experiment = Experiment(name: "Recorded run", procedureID: procedure.id, versionID: procedure.currentVersion.id)
        experiment.status = status; experiment.sampleCount = samples
        var record = StepTimingRecord(stepID: stepID, actualMinutes: minutes); record.includeInLearning = included
        experiment.stepTimings = [record]
        return experiment
    }
    private func estimate(_ workspace: Workspace, _ procedure: Procedure, samples: Int) throws -> StepDurationEstimate {
        let values = try ProtocolTiming.estimates(version: procedure.currentVersion, sampleCount: samples, workspace: workspace)
        return try XCTUnwrap(values.first)
    }
    func testSameSampleSizeLearnsMedianWithConservativeBudget() throws {
        var (workspace, procedure, stepID) = fixture()
        workspace.experiments = [6.0, 8, 10].map { recorded(procedure, stepID: stepID, samples: 4, minutes: $0) }
        let original = procedure
        let value = try estimate(workspace, procedure, samples: 4)
        XCTAssertEqual(value.typicalMinutes, 8); XCTAssertEqual(value.planningMinutes, 10)
        XCTAssertEqual(value.source, .history); XCTAssertEqual(value.observationCount, 3)
        XCTAssertEqual(procedure, original)
        try workspace.validated()
    }
    func testDifferentSampleSizesInterpolateOnlyVerifiedAnchors() throws {
        var (workspace, procedure, stepID) = fixture()
        workspace.experiments = [6.0, 8, 10].map { recorded(procedure, stepID: stepID, samples: 4, minutes: $0) }
            + [18.0, 20, 22].map { recorded(procedure, stepID: stepID, samples: 12, minutes: $0) }
        let value = try estimate(workspace, procedure, samples: 8)
        XCTAssertEqual(value.typicalMinutes, 14); XCTAssertEqual(value.planningMinutes, 16)
        XCTAssertEqual(value.source, .interpolated); XCTAssertEqual(value.observationCount, 6)
        let outside = try estimate(workspace, procedure, samples: 16)
        XCTAssertEqual(outside.typicalMinutes, 40); XCTAssertEqual(outside.source, .scaledBaseline)
        XCTAssertEqual(outside.observationCount, 0)
    }
    func testInsufficientHistoryNeverPretendsToBeCalibrated() throws {
        var (workspace, procedure, stepID) = fixture()
        workspace.experiments = [1.0, 100].map { recorded(procedure, stepID: stepID, samples: 4, minutes: $0) }
        let value = try estimate(workspace, procedure, samples: 4)
        XCTAssertEqual(value.typicalMinutes, 10); XCTAssertEqual(value.source, .scaledBaseline)
        XCTAssertEqual(value.observationCount, 0)
    }
    func testBatchLearningDoesNotMultiplyBySampleCount() throws {
        var (workspace, procedure, stepID) = fixture(mode: .learnedBatch)
        workspace.experiments = [4, 12, 24].map { recorded(procedure, stepID: stepID, samples: $0, minutes: 8) }
        XCTAssertEqual(try estimate(workspace, procedure, samples: 60).planningMinutes, 8)
    }
    func testFixedIncubationNeverLearnsShorterOrScalesWithSamples() throws {
        var (workspace, procedure, _) = fixture()
        let fixedID = procedure.currentVersion.content.atomicSteps[1].id
        workspace.experiments = (0..<3).map { _ in recorded(procedure, stepID: fixedID, samples: 100, minutes: 2) }
        let values = try ProtocolTiming.estimates(version: procedure.currentVersion, sampleCount: 100, workspace: workspace)
        XCTAssertEqual(values[1].planningMinutes, 30); XCTAssertEqual(values[1].source, .fixed)
    }
    func testUnfinishedCancelledExcludedAndUnknownSamplesDoNotLearn() throws {
        var (workspace, procedure, stepID) = fixture()
        workspace.experiments = [.planned, .active, .cancelled].map { recorded(procedure, stepID: stepID, samples: 4, minutes: 1, status: $0) }
        workspace.experiments += (0..<3).map { _ in recorded(procedure, stepID: stepID, samples: 4, minutes: 1, included: false) }
        var unknown = recorded(procedure, stepID: stepID, samples: 4, minutes: 1); unknown.sampleCount = nil
        workspace.experiments.append(unknown)
        XCTAssertEqual(try estimate(workspace, procedure, samples: 4).source, .scaledBaseline)
    }
    func testVersionIsolationEvenIfStepIDsAreRetained() throws {
        var (workspace, procedure, stepID) = fixture()
        var previous = procedure
        previous.versions[0].id = UUID()
        workspace.experiments = (0..<3).map { _ in recorded(previous, stepID: stepID, samples: 4, minutes: 1) }
        XCTAssertEqual(try estimate(workspace, procedure, samples: 4).source, .scaledBaseline)
    }
    func testLoopOccurrencesCountAsOneIndependentRunAndNeedCompleteRecords() throws {
        var (workspace, procedure, stepID) = fixture()
        procedure.versions[0].content.blocks[0].kind = "loop"
        procedure.versions[0].content.blocks[0].loop = ProtocolLoop()
        workspace.procedures = [procedure]
        workspace.experiments = (0..<3).map { _ in recorded(procedure, stepID: stepID, samples: 4, minutes: 6) }
        XCTAssertEqual(try estimate(workspace, procedure, samples: 4).source, .scaledBaseline)
        for i in workspace.experiments.indices {
            workspace.experiments[i].stepTimings.append(StepTimingRecord(stepID: stepID, iteration: "2.1", actualMinutes: 10))
        }
        let value = try estimate(workspace, procedure, samples: 4)
        XCTAssertEqual(value.typicalMinutes, 8); XCTAssertEqual(value.observationCount, 3)
        try workspace.validated()
    }
    func testValidationRejectsMissingUnknownDuplicateAndNonfiniteMeasurements() throws {
        let (workspace, procedure, stepID) = fixture()
        for value in [0.0, -1, Double.nan, Double.infinity, 7201] {
            let experiment = recorded(procedure, stepID: stepID, samples: 4, minutes: value)
            XCTAssertThrowsError(try ProtocolTiming.validateExperiment(experiment, procedure: procedure))
        }
        var experiment = recorded(procedure, stepID: stepID, samples: 4, minutes: 10)
        experiment.stepTimings.append(experiment.stepTimings[0])
        XCTAssertThrowsError(try ProtocolTiming.validateExperiment(experiment, procedure: procedure))
        experiment.stepTimings = [StepTimingRecord(stepID: "not-in-recipe", actualMinutes: 1)]
        XCTAssertThrowsError(try ProtocolTiming.validateExperiment(experiment, procedure: procedure))
        experiment.stepTimings = [StepTimingRecord(stepID: stepID, iteration: "2.1", actualMinutes: 1)]
        XCTAssertThrowsError(try ProtocolTiming.validateExperiment(experiment, procedure: procedure))
        XCTAssertThrowsError(try estimate(workspace, procedure, samples: 0))
        XCTAssertThrowsError(try estimate(workspace, procedure, samples: 100001))
    }
    func testSchedulingUsesFrozenBudgetsAndRevalidatesChangedHistory() throws {
        var (workspace, procedure, stepID) = fixture()
        workspace.experiments = [6.0, 8, 10].map { recorded(procedure, stepID: stepID, samples: 4, minutes: $0) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 9))!
        let candidate = try XCTUnwrap(Planner.candidates(name: "Next run", procedure: procedure, workspace: workspace,
            starting: date, preferences: SchedulePreferences(), calendar: calendar, sampleCount: 4).first)
        XCTAssertEqual(candidate.experiment.sampleCount, 4)
        XCTAssertEqual(candidate.steps.reduce(0) { $0 + $1.minutes }, 40)
        try Planner.validateCandidate(candidate, procedure: procedure, workspace: workspace, calendar: calendar)
        let savedSteps = candidate.steps
        workspace.experiments[0].stepTimings[0].actualMinutes = 20
        XCTAssertThrowsError(try Planner.validateCandidate(candidate, procedure: procedure, workspace: workspace, calendar: calendar))
        XCTAssertEqual(candidate.steps, savedSteps)
        var tampered = candidate; tampered.experiment.durationEstimates.append(tampered.experiment.durationEstimates[0])
        XCTAssertThrowsError(try Planner.validateCandidate(tampered, procedure: procedure, workspace: workspace, calendar: calendar))
    }
    func testPausedSegmentsRemainOneMeasurementOccurrence() throws {
        var (workspace, procedure, stepID) = fixture(mode: .learnedBatch)
        procedure.versions[0].content.blocks[0].subblocks[0].steps[0].canPause = true
        workspace.procedures = [procedure]
        workspace.experiments = (0..<3).map { _ in recorded(procedure, stepID: stepID, samples: 4, minutes: 60) }
        var preferences = SchedulePreferences(); preferences.breakEveryMinutes = 30
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 9))!
        let candidate = try XCTUnwrap(Planner.candidates(name: "Paused", procedure: procedure, workspace: workspace,
            starting: date, preferences: preferences, calendar: calendar, sampleCount: 4).first)
        XCTAssertEqual(candidate.steps.filter { $0.stepID == stepID }.count, 2)
        XCTAssertEqual(Set(candidate.steps.filter { $0.stepID == stepID }.map(\.iteration)), ["1.1"])
        try Planner.validateCandidate(candidate, procedure: procedure, workspace: workspace, calendar: calendar)
    }
    func testOldWorkspaceLoadsUnknownCountsAndNewDataRoundTrips() throws {
        var (workspace, procedure, stepID) = fixture()
        let oldExperiment = Experiment(name: "Old run", procedureID: procedure.id, versionID: procedure.currentVersion.id)
        workspace.experiments = [oldExperiment]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        json.removeValue(forKey: "stepTimingConfigurations")
        var runs = try XCTUnwrap(json["experiments"] as? [[String: Any]])
        for key in ["sampleCount", "scheduledSampleCount", "stepTimings", "durationEstimates", "timingFingerprint"] { runs[0].removeValue(forKey: key) }
        json["experiments"] = runs
        let loaded = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(loaded.experiments[0].sampleCount); XCTAssertTrue(loaded.experiments[0].stepTimings.isEmpty)
        XCTAssertTrue(loaded.stepTimingConfigurations.isEmpty); try loaded.validated()
        workspace.experiments = [recorded(procedure, stepID: stepID, samples: 4, minutes: 8.5)]
        let roundTrip = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        XCTAssertEqual(roundTrip, workspace); try roundTrip.validated()
    }
    func testBilingualAssistantContractsIncludeMeasurementsWithoutInventingThem() {
        for language in [AppLanguage.chinese, .english] {
            let experiment = AssistantFunctionPrompts.contract(.experiments, language)
            let protocolContract = AssistantFunctionPrompts.contract(.protocols, language)
            XCTAssertTrue(experiment.keys.contains("sample_count")); XCTAssertTrue(experiment.keys.contains("step_timings"))
            XCTAssertTrue(protocolContract.keys.contains("timing_mode")); XCTAssertTrue(protocolContract.keys.contains("step_id"))
            XCTAssertTrue(IntentPrompts.scheduleRequest(language).contains("sample_count"))
        }
    }
}
