import Foundation
import PersonalCore
import SwiftUI

struct ExperimentTimingEditor: View {
    private struct Entry {
        var minutes = ""; var included = true; var note = ""
    }
    let store: PersonalStore
    let experiment: Experiment
    private let items: [ExecutionItem]
    private let version: ProcedureVersion?
    private let plannedMinutes: [String: Int]
    @Environment(\.dismiss) private var dismiss
    @State private var sampleText: String
    @State private var entries: [String: Entry]
    @State private var note: String
    @State private var error: String?
    init(store: PersonalStore, experiment: Experiment) {
        self.store = store; self.experiment = experiment
        let version = store.workspace.procedures.first { $0.id == experiment.procedureID }?.versions.first { $0.id == experiment.versionID }
        self.version = version; items = (try? version?.content.executionItems()) ?? []
        plannedMinutes = Dictionary(grouping: store.workspace.plan.filter { $0.experimentID == experiment.id },
            by: { StepTimingRecord(stepID: $0.stepID ?? "", iteration: $0.iteration, actualMinutes: 1).id })
            .mapValues { $0.reduce(0) { $0 + $1.minutes } }
        _sampleText = State(initialValue: experiment.sampleCount.map(String.init) ?? "")
        _note = State(initialValue: experiment.note)
        _entries = State(initialValue: Dictionary(uniqueKeysWithValues: experiment.stepTimings.map {
            ($0.id, Entry(minutes: String(format: "%g", $0.actualMinutes), included: $0.includeInLearning, note: $0.note))
        }))
    }
    var body: some View {
        EditorShell(title: store.assistantText("实验耗时与观察", "Experiment timings & observations"),
                    subtitle: experiment.name + (version.map { " · Protocol v\($0.number)" } ?? ""),
                    error: error, width: 850, save: save) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(store.assistantText("本次实际样品数", "Actual sample count"))
                        TextField(store.assistantText("必填", "Required"), text: $sampleText).frame(width: 100).textFieldStyle(.roundedBorder)
                        Spacer()
                        if let planned = experiment.scheduledSampleCount {
                            Text(store.assistantText("原排程按 \(planned) 个样品计算", "Original schedule used \(planned) samples")).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    Text(store.assistantText("填写每个步骤的实际操作或规定过程耗时，单位为分钟，可用小数；不计会议、休息、无关中断或资源等待。留空表示未记录，不代表 0。分段排程在这里合并为一次执行；循环逐轮记录。", "Enter actual handling or prescribed process time in minutes; decimals are allowed. Exclude meetings, breaks, unrelated interruptions and resource waits. Blank means unrecorded, not zero. Split calendar segments are combined per occurrence; record each loop iteration separately."))
                        .font(.caption).foregroundStyle(Palette.muted)
                    if version == nil {
                        Text(store.assistantText("此历史实验未绑定准确版本；可保存观察，但不能推测原步骤或学习耗时。", "This legacy experiment has no exact version. Notes can be saved, but steps and timings cannot be inferred."))
                            .font(.caption).foregroundStyle(Palette.warning)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in occurrenceRow(item) }
                        }
                    }
                    Text(store.assistantText("实验观察", "Experimental observations")).font(.headline)
                    TextEditor(text: $note).frame(height: 130).padding(6).background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(store.assistantText("仅已完成实验、有效样品数和完整的对应步骤记录参与学习。排程、AI 建议、未填写和取消的实验都不是实测耗时。取消「用于校准」可以保留异常记录，但不让它影响预测。", "Only completed experiments with valid sample counts and complete records for a step contribute to learning. Plans, AI suggestions, missing records and cancelled experiments are not measurements. Excluding a record preserves it without affecting predictions."))
                        .font(.caption).foregroundStyle(Palette.muted)
                }.padding(24)
            }.frame(height: 530)
        }
    }
    private func binding<T>(_ id: String, _ path: WritableKeyPath<Entry, T>, fallback: T) -> Binding<T> {
        Binding(get: { entries[id]?[keyPath: path] ?? fallback }, set: { value in
            var entry = entries[id] ?? Entry(); entry[keyPath: path] = value; entries[id] = entry
        })
    }
    private func occurrenceRow(_ item: ExecutionItem) -> some View {
        let id = StepTimingRecord(stepID: item.step.id, iteration: item.iteration, actualMinutes: 1).id
        let block = version?.content.blocks.first { $0.id == item.blockID }
        let group = block?.subblocks.first { $0.id == item.subblockID }
        let measured = !(entries[id]?.minutes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(item.step.order). \(item.step.title)").font(.system(size: 13, weight: .medium))
                    Text([block?.title, group?.title].compactMap { $0 }.joined(separator: " / ") + " · \(item.iteration)")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(plannedMinutes[id].map { store.assistantText("计划 \($0) 分钟", "Planned \($0) min") } ?? store.assistantText("无计划快照", "No plan snapshot"))
                    .font(.caption).foregroundStyle(Palette.muted).frame(width: 115, alignment: .trailing)
                TextField(store.assistantText("实际分钟", "Actual min"), text: binding(id, \.minutes, fallback: ""))
                    .textFieldStyle(.roundedBorder).frame(width: 100)
                Toggle(store.assistantText("用于校准", "Use for learning"), isOn: binding(id, \.included, fallback: true))
                    .toggleStyle(.checkbox).disabled(!measured)
            }
            TextField(store.assistantText("中断、异常或排除原因（可选）", "Interruptions, unusual conditions or exclusion reason (optional)"), text: binding(id, \.note, fallback: ""))
                .textFieldStyle(.roundedBorder).font(.caption)
        }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
    }
    private func save() {
        do {
            guard version != nil else { try store.saveNote(experiment.id, note); dismiss(); return }
            guard let sampleCount = Int(sampleText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw WorkspaceError.invalid(store.assistantText("请填写本次实际样品数。", "Enter the actual sample count."))
            }
            var records: [StepTimingRecord] = []
            for item in items {
                let id = StepTimingRecord(stepID: item.step.id, iteration: item.iteration, actualMinutes: 1).id
                let entry = entries[id] ?? Entry(), text = entry.minutes.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                guard let minutes = Double(text.replacingOccurrences(of: ",", with: ".")) else {
                    throw WorkspaceError.invalid(store.assistantText("「\(item.step.title)」的实际耗时不是有效数字。", "Actual minutes for “\(item.step.title)” are not a valid number."))
                }
                var record = StepTimingRecord(stepID: item.step.id, iteration: item.iteration, actualMinutes: minutes)
                record.includeInLearning = entry.included; record.note = entry.note
                if let prior = experiment.stepTimings.first(where: { $0.id == id }), prior.actualMinutes == minutes,
                   prior.includeInLearning == record.includeInLearning, prior.note == record.note { record.recordedAt = prior.recordedAt }
                records.append(record)
            }
            try store.saveExperimentTimings(experiment.id, sampleCount: sampleCount, records: records, note: note, expected: experiment)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
