import PersonalCore
import SwiftUI

private func timingModeTitle(_ mode: StepTimingMode, language: AppLanguage) -> String {
    switch mode {
    case .fixed: language == .english ? "Fixed Protocol duration" : "固定方案时间（不学习）"
    case .learnedBatch: language == .english ? "Learn batch handling time" : "学习批次操作时间"
    case .learnedSamples: language == .english ? "Learn sample-dependent handling time" : "学习随样品数变化的操作时间"
    }
}
private func timingSourceTitle(_ source: TimingEstimateSource, language: AppLanguage) -> String {
    switch source {
    case .fixed: language == .english ? "Fixed" : "固定方案"
    case .baseline: language == .english ? "Baseline · insufficient history" : "基准估计 · 历史不足"
    case .scaledBaseline: language == .english ? "Scaled baseline · not history-verified" : "按样品数换算基准 · 尚未验证"
    case .history: language == .english ? "Recorded history" : "历史实测校准"
    case .interpolated: language == .english ? "Interpolated between verified sample sizes" : "已验证样品数之间插值"
    }
}

struct ProtocolTimingPanel: View {
    let store: PersonalStore
    let version: ProcedureVersion
    @State private var sampleCount = 1
    @State private var editing: StepTimingConfiguration?
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                Text(store.assistantText("只校准未来的时间估计，不修改操作层次、历史版本或已采用排程。孵育、反应等规定时长请保持固定；只有完成实验的实际记录参与学习。", "Calibrate future estimates without changing the recipe, historical versions or adopted schedules. Keep prescribed incubation/reaction durations fixed. Only actual records from completed experiments are learned."))
                    .font(.caption).foregroundStyle(Palette.muted)
                Stepper(store.assistantText("预览样品数：\(sampleCount)", "Preview sample count: \(sampleCount)"), value: $sampleCount, in: 1...100_000)
                let estimates = (try? ProtocolTiming.estimates(version: version, sampleCount: sampleCount, workspace: store.workspace)) ?? []
                ForEach(version.content.atomicSteps) { step in
                    let config = ProtocolTiming.configuration(versionID: version.id, step: step, in: store.workspace)
                    let estimate = estimates.first { $0.stepID == step.id }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(step.order). \(step.title)").font(.system(size: 12, weight: .medium))
                            Text(timingModeTitle(config.mode, language: store.workspace.language)).font(.caption2).foregroundStyle(Palette.muted)
                            if let estimate {
                                Text(timingSourceTitle(estimate.source, language: store.workspace.language) + store.assistantText(" · \(estimate.observationCount) 次用于估计的独立实验", " · \(estimate.observationCount) independent experiments used"))
                                    .font(.caption2).foregroundStyle(Palette.muted)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(estimate.map { store.assistantText("排程 \($0.planningMinutes) 分钟", "Plan \($0.planningMinutes) min") } ?? store.assistantText("基准 \(step.durationMinutes) 分钟", "Baseline \(step.durationMinutes) min"))
                                .font(.system(size: 12, design: .monospaced))
                            if let estimate { Text(store.assistantText("典型 \(String(format: "%.1f", estimate.typicalMinutes)) 分钟", "Typical \(String(format: "%.1f", estimate.typicalMinutes)) min")).font(.caption2).foregroundStyle(Palette.muted) }
                        }
                        Button(store.assistantText("设置", "Configure")) { editing = config }
                            .disabled(store.readOnly || !store.workspace.procedures.flatMap(\.versions).contains { $0.id == version.id })
                    }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(.top, 12)
        } label: {
            Label(store.assistantText("步骤时间与实测校准", "Step durations & recorded calibration"), systemImage: "clock.arrow.circlepath").font(.system(size: 13, weight: .medium))
        }.sheet(item: $editing) { configuration in TimingConfigurationEditor(store: store, initial: configuration) }
    }
}

private struct TimingConfigurationEditor: View {
    let store: PersonalStore
    let initial: StepTimingConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StepTimingConfiguration
    @State private var error: String?
    init(store: PersonalStore, initial: StepTimingConfiguration) {
        self.store = store; self.initial = initial; _draft = State(initialValue: initial)
    }
    var body: some View {
        EditorShell(title: store.assistantText("步骤时间校准", "Step timing calibration"), subtitle: store.assistantText("校准属于这个 Protocol 版本，其他版本不会自动继承。", "Calibration belongs to this Protocol version; other versions do not inherit it automatically."), error: error, save: save) {
            Form {
                Picker(store.assistantText("时间类型", "Timing policy"), selection: $draft.mode) {
                    ForEach(StepTimingMode.allCases, id: \.self) { mode in Text(timingModeTitle(mode, language: store.workspace.language)).tag(mode) }
                }
                TextField(store.assistantText("基准分钟", "Baseline minutes"), value: $draft.baselineMinutes, format: .number).disabled(draft.mode == .fixed)
                if draft.mode == .learnedSamples {
                    TextField(store.assistantText("此基准对应的样品数", "Samples at this baseline"), value: $draft.referenceSampleCount, format: .number)
                }
                Text(store.assistantText("固定时间遵循原 Protocol，修改请创建新版本。批次学习假设一批操作耗时不随样品数线性增长。逐样品学习至少需要同一样品数 3 次完整记录；可在两个已验证样品数之间插值，范围外回到明确标记的基准换算。异常或中断记录可不参与学习。", "Fixed durations follow the original Protocol; change them in a new version. Batch learning assumes handling time is independent of sample count. Sample-dependent learning requires 3 complete runs per sample size and interpolates only between verified sizes. Outside that range, estimates fall back to an explicitly labelled scaled baseline. Interrupted or unusual records can be excluded."))
                    .font(.caption).foregroundStyle(Palette.muted)
                Text(store.assistantText("学习只预测操作时间，不判断反应是否完成，也不改变温度、浓度、孵育时间等科学条件。", "Learning predicts handling time, not reaction completion. It does not alter temperature, concentration or prescribed scientific conditions."))
                    .font(.caption).foregroundStyle(Palette.warning)
            }.formStyle(.grouped)
        }.onChange(of: draft.mode) { _, mode in
            if mode == .fixed, let version = store.workspace.procedures.flatMap(\.versions).first(where: { $0.id == draft.versionID }),
               let step = version.content.atomicSteps.first(where: { $0.id == draft.stepID }) { draft.baselineMinutes = step.durationMinutes }
        }
    }
    private func save() {
        do { try store.saveTimingConfiguration(draft, expected: initial); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct TimingEstimateSummary: View {
    let store: PersonalStore
    let procedure: Procedure
    let sampleCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            doEstimates
        }
    }
    @ViewBuilder private var doEstimates: some View {
        if let estimates = try? ProtocolTiming.estimates(version: procedure.currentVersion, sampleCount: sampleCount, workspace: store.workspace),
           let items = try? procedure.currentVersion.content.executionItems() {
            let counts = Dictionary(grouping: items, by: { $0.step.id }).mapValues(\.count)
            let total = estimates.reduce(0) { $0 + $1.planningMinutes * (counts[$1.stepID] ?? 0) }
            Label(store.assistantText("\(sampleCount) 个样品 · 操作预留 \(total) 分钟", "\(sampleCount) samples · \(total) min of planned steps"), systemImage: "clock").font(.callout)
            let unverified = estimates.filter { $0.source == .baseline || $0.source == .scaledBaseline }.count
            Text(store.assistantText("已校准 \(estimates.filter { $0.source == .history || $0.source == .interpolated }.count) 个步骤；\(unverified) 个步骤仍使用未验证基准。以上不含会议、休息或资源等待。", "\(estimates.filter { $0.source == .history || $0.source == .interpolated }.count) calibrated steps; \(unverified) steps use unverified baselines. Totals exclude meetings, breaks and resource waits."))
                .font(.caption).foregroundStyle(Palette.muted)
        } else {
            Text(store.assistantText("请先补齐所有步骤的基准时间，并检查样品数。", "Complete the step baselines and check sample count before scheduling.")).font(.caption).foregroundStyle(Palette.warning)
        }
    }
}
