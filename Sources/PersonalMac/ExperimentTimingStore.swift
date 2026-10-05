import Foundation
import PersonalCore

@MainActor extension PersonalStore {
    func saveTimingConfiguration(_ configuration: StepTimingConfiguration, expected: StepTimingConfiguration) throws {
        try configuration.validated()
        try commit { workspace in
            guard let version = workspace.procedures.flatMap(\.versions).first(where: { $0.id == configuration.versionID }),
                  let step = version.content.atomicSteps.first(where: { $0.id == configuration.stepID }),
                  ProtocolTiming.configuration(versionID: version.id, step: step, in: workspace) == expected else {
                throw WorkspaceError.invalid("此步骤的校准已改变，请重新打开。 / Timing calibration changed; reopen this step.")
            }
            guard configuration.mode != .fixed || configuration.baselineMinutes == step.durationMinutes else {
                throw WorkspaceError.invalid("固定时长须遵循 Protocol；请创建新版本修改。 / Fixed durations must follow the Protocol; edit a new version to change them.")
            }
            workspace.stepTimingConfigurations.removeAll { $0.id == configuration.id }
            workspace.stepTimingConfigurations.append(configuration)
        }
    }
    func saveExperimentTimings(_ experimentID: UUID, sampleCount: Int, records: [StepTimingRecord], note: String, expected: Experiment) throws {
        try commit { workspace in
            guard let index = workspace.experiments.firstIndex(where: { $0.id == experimentID }), workspace.experiments[index] == expected else {
                throw WorkspaceError.invalid("实验记录已改变，请重新打开后再保存。 / The experiment changed; reopen it before saving.")
            }
            workspace.experiments[index].sampleCount = sampleCount
            workspace.experiments[index].stepTimings = records
            workspace.experiments[index].note = note
            // Workspace validation checks occurrence identities, finite values and version.
            // Actual observations never overwrite the adopted calendar or recipe.
        }
    }
}
