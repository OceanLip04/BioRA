import Foundation
import PersonalCore

/// In-memory fictional UI fixture: never loads a database, credential or model.
extension Workspace {
    static func experimentTimingPreview() throws -> Workspace {
        var workspace = Workspace(); workspace.isDemo = true
        var content = ProtocolContent(blocks: [
            ProtocolBlock(title: "样品准备", subblocks: [ProtocolSubblock(title: "配制与分装", steps: [
                ProtocolStep(title: "准备并分装样品", minutes: 10),
                ProtocolStep(title: "固定过程时间（虚构示例）", minutes: 30),
                ProtocolStep(title: "整理观察记录", minutes: 5)
            ])])
        ]); content.renumber()
        content.objective = "虚构界面预览：展示逐步实测时间如何校准下一次排程，不是实际实验方案或操作建议。"
        content.precautions = ["所有时间和记录均为虚构，不代表经过验证的生命科学条件。"]
        let procedure = Procedure(name: "样品处理 · 时间校准演示", content: content, status: .published)
        workspace.procedures = [procedure]
        var handling = StepTimingConfiguration(versionID: procedure.currentVersion.id, step: content.atomicSteps[0])
        handling.mode = .learnedSamples; handling.referenceSampleCount = 4
        var notes = StepTimingConfiguration(versionID: procedure.currentVersion.id, step: content.atomicSteps[2])
        notes.mode = .learnedBatch
        workspace.stepTimingConfigurations = [handling, notes]
        for (samples, values) in [(4, [6.0, 8, 10]), (12, [18.0, 20, 22])] {
            for minutes in values {
                var experiment = Experiment(name: "虚构实测 · \(samples) 个样品", procedureID: procedure.id, versionID: procedure.currentVersion.id)
                experiment.sampleCount = samples; experiment.status = .completed
                experiment.note = "虚构界面数据，不是实验观察。"
                experiment.stepTimings = [
                    StepTimingRecord(stepID: content.atomicSteps[0].id, actualMinutes: minutes),
                    StepTimingRecord(stepID: content.atomicSteps[1].id, actualMinutes: 30),
                    StepTimingRecord(stepID: content.atomicSteps[2].id, actualMinutes: 4)
                ]; workspace.experiments.append(experiment)
            }
        }
        let candidate = try Planner.candidates(name: "下一次实验 · 8 个样品（虚构）", procedure: procedure, workspace: workspace,
            starting: Date().addingTimeInterval(86400), preferences: SchedulePreferences(), sampleCount: 8)[0]
        workspace.experiments.append(candidate.experiment); workspace.plan = candidate.steps
        try workspace.validated()
        return workspace
    }
}
