import CryptoKit
import Foundation

/// Calibration belongs to one immutable recipe version; it never edits that recipe.
public enum StepTimingMode: String, Codable, CaseIterable, Sendable {
    case fixed, learnedBatch, learnedSamples
}
public struct StepTimingConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var versionID: UUID
    public var stepID: String
    public var mode: StepTimingMode = .fixed
    public var baselineMinutes: Int
    public var referenceSampleCount = 1
    public var id: String { versionID.uuidString + ":" + stepID }
    public init(versionID: UUID, step: ProtocolStep) {
        self.versionID = versionID; stepID = step.id; baselineMinutes = step.durationMinutes
    }
    public func validated() throws {
        guard !stepID.isEmpty, stepID.count <= 128, (1...7200).contains(baselineMinutes),
              (1...100_000).contains(referenceSampleCount) else {
            throw WorkspaceError.invalid("请填写有效的基准时间和样品数。 / Enter valid baseline minutes and sample count.")
        }
    }
}
public struct StepTimingRecord: Codable, Equatable, Identifiable, Sendable {
    public var stepID: String
    public var iteration: String
    public var actualMinutes: Double
    public var includeInLearning = true
    public var note = ""
    public var recordedAt = Date()
    public var id: String { "\(stepID.count):\(stepID):\(iteration)" }
    public init(stepID: String, iteration: String = "1.1", actualMinutes: Double) {
        self.stepID = stepID; self.iteration = iteration; self.actualMinutes = actualMinutes
    }
}
public enum TimingEstimateSource: String, Codable, Sendable {
    case fixed, baseline, scaledBaseline, history, interpolated
}
public struct StepDurationEstimate: Codable, Equatable, Identifiable, Sendable {
    public var stepID: String
    public var typicalMinutes: Double
    public var planningMinutes: Int
    public var source: TimingEstimateSource
    /// Independent experiments, not loop iterations or split calendar segments.
    public var observationCount: Int
    public var id: String { stepID }
}

public enum ProtocolTiming {
    private struct Observation: Codable {
        var experimentID: UUID; var samples: Int; var minutes: Double
    }
    private struct Fingerprint: Codable {
        var algorithm = 1; var versionID: UUID; var configurations: [StepTimingConfiguration]
        var observations: [String: [Observation]]
    }
    public static func configuration(versionID: UUID, step: ProtocolStep, in workspace: Workspace) -> StepTimingConfiguration {
        workspace.stepTimingConfigurations.first { $0.versionID == versionID && $0.stepID == step.id }
            ?? StepTimingConfiguration(versionID: versionID, step: step)
    }
    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted(), middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
    private static func upperBudget(_ values: [Double]) -> Double {
        // Empirical 80th percentile is a planning allowance, not a confidence interval.
        values.sorted()[max(0, Int(ceil(Double(values.count) * 0.8)) - 1)]
    }
    private static func observations(version: ProcedureVersion, stepID: String, occurrences: Set<String>, workspace: Workspace) -> [Observation] {
        guard !occurrences.isEmpty else { return [] }
        return workspace.experiments.filter { $0.status == .completed && $0.versionID == version.id }.suffix(120).compactMap { experiment in
            guard experiment.status == .completed, experiment.versionID == version.id,
                  let samples = experiment.sampleCount, (1...100_000).contains(samples) else { return nil }
            let records = experiment.stepTimings.filter { $0.stepID == stepID && $0.includeInLearning }
            // A partially recorded loop is not a complete independent observation.
            guard Set(records.map(\.iteration)) == occurrences, records.count == occurrences.count,
                  records.allSatisfy({ $0.actualMinutes.isFinite && $0.actualMinutes > 0 && $0.actualMinutes <= 7200 }) else { return nil }
            return Observation(experimentID: experiment.id, samples: samples, minutes: median(records.map(\.actualMinutes)))
        }.sorted { $0.experimentID.uuidString < $1.experimentID.uuidString }
    }
    public static func fingerprint(version: ProcedureVersion, workspace: Workspace) throws -> String {
        var observationsByStep: [String: [Observation]] = [:]
        let occurrences = Dictionary(grouping: try version.content.executionItems(), by: { $0.step.id }).mapValues { Set($0.map(\.iteration)) }
        let configurations = version.content.atomicSteps.map { configuration(versionID: version.id, step: $0, in: workspace) }
        for configuration in configurations where configuration.mode != .fixed {
            observationsByStep[configuration.stepID] = observations(version: version, stepID: configuration.stepID, occurrences: occurrences[configuration.stepID] ?? [], workspace: workspace)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let value = Fingerprint(versionID: version.id, configurations: configurations, observations: observationsByStep)
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
    public static func estimates(version: ProcedureVersion, sampleCount: Int, workspace: Workspace) throws -> [StepDurationEstimate] {
        guard (1...100_000).contains(sampleCount) else { throw WorkspaceError.invalid("样品数应为 1–100000。 / Sample count must be 1–100000.") }
        let occurrences = Dictionary(grouping: try version.content.executionItems(), by: { $0.step.id }).mapValues { Set($0.map(\.iteration)) }
        return try version.content.atomicSteps.map { step in
            let config = configuration(versionID: version.id, step: step, in: workspace)
            guard config.baselineMinutes > 0 else {
                throw WorkspaceError.invalid("步骤「\(step.title)」耗时未知，请先补齐基准时间。 / The step duration is unknown; complete its baseline before scheduling.")
            }
            try config.validated()
            let records = config.mode == .fixed ? [] : observations(version: version, stepID: step.id, occurrences: occurrences[step.id] ?? [], workspace: workspace)
            var typical = Double(config.baselineMinutes), allowance = typical
            var source: TimingEstimateSource = config.mode == .fixed ? .fixed : .baseline
            var count = 0
            if config.mode == .learnedBatch {
                if records.count >= 3 {
                    let values = records.map(\.minutes)
                    typical = median(values); allowance = upperBudget(values); source = .history; count = records.count
                }
            } else if config.mode == .learnedSamples {
                typical *= Double(sampleCount) / Double(config.referenceSampleCount)
                allowance = typical; source = .scaledBaseline
                let groups = Dictionary(grouping: records, by: \.samples).filter { $0.value.count >= 3 }
                if let exact = groups[sampleCount] {
                    typical = median(exact.map(\.minutes)); allowance = upperBudget(exact.map(\.minutes))
                    source = .history; count = exact.count
                } else if let lower = groups.keys.filter({ $0 < sampleCount }).max(),
                          let upper = groups.keys.filter({ $0 > sampleCount }).min(),
                          let lhs = groups[lower], let rhs = groups[upper] {
                    let ratio = Double(sampleCount - lower) / Double(upper - lower)
                    typical = median(lhs.map(\.minutes)) * (1 - ratio) + median(rhs.map(\.minutes)) * ratio
                    allowance = upperBudget(lhs.map(\.minutes)) * (1 - ratio) + upperBudget(rhs.map(\.minutes)) * ratio
                    source = .interpolated; count = lhs.count + rhs.count
                }
                // Never extrapolate a learned curve outside observed, verified sample sizes.
            }
            let budget = ceil(max(typical, allowance))
            guard typical.isFinite, typical > 0, budget <= 7200 else {
                throw WorkspaceError.invalid("步骤时间超过支持范围，请检查样品数和基准时间。 / Step duration exceeds supported limits; check sample count and baseline.")
            }
            return StepDurationEstimate(stepID: step.id, typicalMinutes: typical, planningMinutes: max(1, Int(budget)), source: source, observationCount: count)
        }
    }
    public static func executionItems(version: ProcedureVersion, estimates: [StepDurationEstimate]) throws -> [ExecutionItem] {
        var items = try version.content.executionItems()
        guard !estimates.isEmpty else { return items } // Legacy plans retain their original recipe durations.
        guard Set(estimates.map(\.stepID)).count == estimates.count,
              Set(estimates.map(\.stepID)) == Set(version.content.atomicSteps.map(\.id)),
              estimates.allSatisfy({ (1...7200).contains($0.planningMinutes) }) else {
            throw WorkspaceError.invalid("Invalid or duplicate scheduling duration snapshot.")
        }
        let index = Dictionary(uniqueKeysWithValues: estimates.map { ($0.stepID, $0.planningMinutes) })
        for i in items.indices {
            guard let minutes = index[items[i].step.id] else { throw WorkspaceError.invalid("Missing step timing snapshot.") }
            items[i].step.durationMinutes = minutes
        }
        return items
    }
    public static func validateExperiment(_ experiment: Experiment, procedure: Procedure) throws {
        guard experiment.sampleCount.map({ (1...100_000).contains($0) }) ?? true,
              experiment.scheduledSampleCount.map({ (1...100_000).contains($0) }) ?? true,
              experiment.stepTimings.count <= 10000, experiment.durationEstimates.count <= 2000,
              Set(experiment.stepTimings.map(\.id)).count == experiment.stepTimings.count,
              Set(experiment.durationEstimates.map(\.id)).count == experiment.durationEstimates.count else {
            throw WorkspaceError.invalid("实验样品数或步骤时间记录无效。 / Invalid experiment samples or timings.")
        }
        if experiment.stepTimings.isEmpty && experiment.durationEstimates.isEmpty { return }
        guard let version = procedure.versions.first(where: { $0.id == experiment.versionID }), experiment.sampleCount != nil else {
            throw WorkspaceError.invalid("记录耗时需要准确的 Protocol 版本和样品数。 / Timing records need an exact Protocol version and sample count.")
        }
        let items = try version.content.executionItems()
        let keys = Set(items.map { StepTimingRecord(stepID: $0.step.id, iteration: $0.iteration, actualMinutes: 1).id })
        for record in experiment.stepTimings {
            guard keys.contains(record.id), record.actualMinutes.isFinite, record.actualMinutes > 0, record.actualMinutes <= 7200,
                  record.note.count <= 2000, record.recordedAt.timeIntervalSince1970.isFinite else {
                throw WorkspaceError.invalid("实测耗时须大于 0；缺失或跳过步骤请留空，不可填造耗时。 / Actual minutes must be positive; leave unmeasured steps blank.")
            }
        }
        if !experiment.durationEstimates.isEmpty {
            guard Set(experiment.durationEstimates.map(\.stepID)) == Set(version.content.atomicSteps.map(\.id)),
                  experiment.scheduledSampleCount != nil,
                  experiment.timingFingerprint.map({ $0.count == 64 && $0.allSatisfy { $0.isHexDigit } }) ?? false else {
                throw WorkspaceError.invalid("Invalid immutable scheduling timing snapshot.")
            }
            for estimate in experiment.durationEstimates {
                guard estimate.typicalMinutes.isFinite, estimate.typicalMinutes > 0,
                      (1...7200).contains(estimate.planningMinutes), Double(estimate.planningMinutes) >= estimate.typicalMinutes,
                      estimate.observationCount >= 0 else { throw WorkspaceError.invalid("Invalid timing estimate.") }
            }
        }
    }
}
