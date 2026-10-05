import Foundation

public enum Planner {
    public static func resources(for step: ProtocolStep, in workspace: Workspace) throws -> Set<UUID> {
        var ids = Set(step.instrumentID.map { [$0] } ?? [])
        for name in step.equipmentNeeded where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matches = workspace.instruments.filter { $0.name.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
            guard matches.count == 1 else { throw WorkspaceError.invalid("设备「\(name)」需要先添加到仪器清单或明确匹配。") }; ids.insert(matches[0].id)
        }
        for id in ids { guard workspace.instruments.contains(where: { $0.id == id && $0.available }) else { throw WorkspaceError.invalid("步骤「\(step.title)」所需仪器不可用。") } }
        return ids
    }
    private static func conflicts(start: Date, end: Date, attention: Bool, resources: Set<UUID>, workspace: Workspace, excluding: UUID?) -> [(Date, Date)] {
        let active = Set(workspace.experiments.filter { $0.status != .cancelled && $0.id != excluding }.map(\.id))
        let planned = workspace.plan.filter { active.contains($0.experimentID) && $0.start < end && $0.end > start && ((attention && $0.requiresAttention) || !resources.isDisjoint(with: $0.resources)) }.map { ($0.start, $0.end) }
        let busy = workspace.busyIntervals.filter { $0.start < end && $0.end > start && ($0.instrumentID.map(resources.contains) ?? attention) }.map { ($0.start, $0.end) }
        return (planned + busy).sorted { $0.0 < $1.0 }
    }
    private static func workBounds(_ date: Date, _ preferences: SchedulePreferences, _ calendar: Calendar) throws -> (Date, Date) {
        let day = calendar.startOfDay(for: date)
        let closing = preferences.workEndMinute == 1440 ? calendar.date(byAdding: .day, value: 1, to: day) : calendar.date(bySettingHour: preferences.workEndMinute / 60, minute: preferences.workEndMinute % 60, second: 0, of: day)
        guard let start = calendar.date(bySettingHour: preferences.workStartMinute / 60, minute: preferences.workStartMinute % 60, second: 0, of: day), let end = closing else { throw WorkspaceError.invalid("无法计算工作时段。") }
        return (start, end)
    }
    public static func schedule(experiment: Experiment, procedure: Procedure, in workspace: Workspace, starting date: Date, calendar: Calendar = .current, preferences: SchedulePreferences? = nil) throws -> [PlannedStep] {
        let prefs = preferences ?? workspace.preferences; try prefs.validated()
        let version = experiment.versionID.flatMap { id in procedure.versions.first { $0.id == id } } ?? procedure.currentVersion
        try ProtocolTiming.validateExperiment(experiment, procedure: procedure)
        let items = try ProtocolTiming.executionItems(version: version, estimates: experiment.durationEstimates)
        var result: [PlannedStep] = []; var cursor = Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 / 60) * 60); var continuous = 0
        for item in items {
            let step = item.step; guard step.durationMinutes > 0 else { throw WorkspaceError.invalid("步骤「\(step.title)」耗时未知，请补齐后排程。") }
            let equipment = try resources(for: step, in: workspace)
            let overnight = step.unattended && step.overnightSafe && prefs.allowOvernight
            let pausable = step.canPause && !step.requiresContinuous
            guard overnight || pausable || step.durationMinutes <= prefs.workEndMinute - prefs.workStartMinute else { throw WorkspaceError.invalid("步骤「\(step.title)」无法在工作时段内连续完成；请设置有效的暂停或过夜条件。") }
            if !step.unattended && continuous >= prefs.breakEveryMinutes && prefs.breakMinutes > 0 {
                cursor = cursor.addingTimeInterval(Double(prefs.breakMinutes * 60)); continuous = 0
            }
            var remaining = step.durationMinutes; var attempts = 0
            while remaining > 0 {
                attempts += 1; guard attempts <= 5000, cursor.timeIntervalSince(date) < 730 * 86400 else { throw WorkspaceError.invalid("没有找到可用排程，请检查工作时间和资源占用。") }
                let (opening, closing) = try workBounds(cursor, prefs, calendar)
                if cursor < opening { cursor = opening; continuous = 0 }
                if cursor >= closing { cursor = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!; continuous = 0; continue }
                var end = cursor.addingTimeInterval(Double(remaining * 60))
                if !overnight && end > closing {
                    if pausable { end = closing }
                    else { cursor = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!; continuous = 0; continue }
                }
                if pausable && !step.unattended && prefs.breakMinutes > 0 {
                    let available = max(1, prefs.breakEveryMinutes - continuous)
                    end = min(end, cursor.addingTimeInterval(Double(available * 60)))
                }
                let blocked = conflicts(start: cursor, end: end, attention: !step.unattended, resources: equipment, workspace: workspace, excluding: experiment.id)
                if let first = blocked.first {
                    if pausable && first.0 > cursor { end = min(end, first.0) }
                    else { cursor = blocked.filter { $0.0 <= cursor || !pausable }.map(\.1).max() ?? first.1; continuous = 0; continue }
                }
                let minutes = Int(floor(end.timeIntervalSince(cursor) / 60))
                guard minutes > 0 else { cursor = end.addingTimeInterval(60); continue }
                end = cursor.addingTimeInterval(Double(minutes * 60))
                var planned = PlannedStep(experimentID: experiment.id, title: step.title.isEmpty ? step.description : step.title, instrumentID: equipment.sorted { $0.uuidString < $1.uuidString }.first, start: cursor, end: end)
                planned.instrumentIDs = equipment.sorted { $0.uuidString < $1.uuidString }; planned.versionID = version.id
                planned.blockID = item.blockID; planned.subblockID = item.subblockID; planned.stepID = step.id; planned.iteration = item.iteration; planned.requiresAttention = !step.unattended
                result.append(planned); remaining -= minutes; cursor = end
                continuous = step.unattended ? 0 : continuous + minutes
                if remaining > 0 && !step.unattended && continuous >= prefs.breakEveryMinutes && prefs.breakMinutes > 0 { cursor = cursor.addingTimeInterval(Double(prefs.breakMinutes * 60)); continuous = 0 }
            }
        }
        try validate(result, procedure: procedure, versionID: version.id, workspace: workspace, preferences: prefs, excluding: experiment.id, calendar: calendar, durationEstimates: experiment.durationEstimates)
        return result
    }
    public static func validate(_ steps: [PlannedStep], procedure: Procedure, versionID: UUID, workspace: Workspace, preferences: SchedulePreferences, excluding: UUID? = nil, calendar: Calendar = .current, durationEstimates: [StepDurationEstimate] = []) throws {
        try preferences.validated()
        guard let version = procedure.versions.first(where: { $0.id == versionID }), !steps.isEmpty else { throw WorkspaceError.invalid("排程版本不存在或没有执行项。") }
        let expected = try ProtocolTiming.executionItems(version: version, estimates: durationEstimates)
        func key(_ item: ExecutionItem) -> String { "\(item.blockID)/\(item.subblockID)/\(item.step.id)/\(item.iteration)" }
        var index = 0; var consumed = 0; var previousEnd: Date?
        for planned in steps {
            guard index < expected.count else { throw WorkspaceError.invalid("排程增加了额外步骤。") }
            let item = expected[index]; let step = item.step
            let actualKey = "\(planned.blockID ?? "")/\(planned.subblockID ?? "")/\(planned.stepID ?? "")/\(planned.iteration)"
            let required = try resources(for: step, in: workspace)
            guard planned.versionID == versionID, actualKey == key(item), planned.start < planned.end, planned.minutes > 0,
                  abs(planned.end.timeIntervalSince(planned.start) - Double(planned.minutes * 60)) < 0.001,
                  planned.resources == required, planned.requiresAttention == !step.unattended,
                  previousEnd.map({ $0 <= planned.start }) ?? true else { throw WorkspaceError.invalid("排程的步骤、时间、设备或顺序不符合 Protocol。") }
            if consumed > 0 && (!step.canPause || step.requiresContinuous) { throw WorkspaceError.invalid("连续步骤不能拆分。") }
            if !(step.unattended && step.overnightAllowed(preferences)) {
                let (opening, closing) = try workBounds(planned.start, preferences, calendar)
                guard planned.start >= opening, planned.end <= closing else { throw WorkspaceError.invalid("步骤超出允许工作时段。") }
            }
            guard conflicts(start: planned.start, end: planned.end, attention: planned.requiresAttention, resources: required, workspace: workspace, excluding: excluding).isEmpty else { throw WorkspaceError.invalid("排程与最新个人时间或仪器占用冲突，请重新生成。") }
            consumed += planned.minutes; guard consumed <= step.durationMinutes else { throw WorkspaceError.invalid("排程改变了步骤耗时。") }
            if consumed == step.durationMinutes { index += 1; consumed = 0 }
            previousEnd = planned.end
        }
        guard index == expected.count, consumed == 0 else { throw WorkspaceError.invalid("排程遗漏了 Protocol 步骤。") }
    }
    /// Serial schedule generation with event-boundary insertion. Feasibility is hard;
    /// objectives rank only validated candidates (this is a heuristic, not a global optimum).
    public static func candidates(name: String, procedure: Procedure, workspace: Workspace, starting date: Date, preferences: SchedulePreferences, calendar: Calendar = .current, objective: ScheduleObjective = .earliestFinish, latestFinish: Date? = nil, additionalBusyIntervals: [BusyInterval] = [], sampleCount: Int? = nil) throws -> [ScheduleCandidate] {
        var workspace = workspace
        let english = workspace.language == .english
        for interval in additionalBusyIntervals {
            guard interval.start < interval.end, interval.instrumentID.map({ id in workspace.instruments.contains { $0.id == id } }) ?? true else { throw WorkspaceError.invalid("排程附加忙碌约束无效。") }
        }
        workspace.busyIntervals += additionalBusyIntervals
        if let latestFinish, latestFinish <= date { throw WorkspaceError.invalid("截止时间必须晚于最早开始时间。") }
        guard procedure.currentVersion.status == .published else { throw WorkspaceError.invalid("请先将 Protocol 确认为可用版本。") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.invalid("实验名称不能为空。") }
        var experiment = Experiment(name: name, procedureID: procedure.id, versionID: procedure.currentVersion.id)
        if let sampleCount {
            experiment.sampleCount = sampleCount; experiment.scheduledSampleCount = sampleCount
            experiment.durationEstimates = try ProtocolTiming.estimates(version: procedure.currentVersion, sampleCount: sampleCount, workspace: workspace)
            experiment.timingFingerprint = try ProtocolTiming.fingerprint(version: procedure.currentVersion, workspace: workspace)
        }
        var values: [ScheduleCandidate] = []
        var failures: [String] = []
        func add(_ prefs: SchedulePreferences, starting: Date, label: String) {
            do {
                let steps = try schedule(experiment: experiment, procedure: procedure, in: workspace, starting: starting, calendar: calendar, preferences: prefs)
                if let latestFinish, (steps.last?.end ?? .distantFuture) > latestFinish { failures.append("无法在要求的截止时间前完成。") ; return }
                if values.contains(where: { $0.steps.map(\.start) == steps.map(\.start) && $0.steps.map(\.end) == steps.map(\.end) }) { return }
                var candidate = ScheduleCandidate(procedure: procedure, experiment: experiment, steps: steps, preferences: prefs, label: label,
                    rationale: english ? "Generated by serial scheduling. Step order, full durations, working hours, personal conflicts, and instrument occupancy were checked." : "串行调度生成：已校验步骤顺序、完整耗时、工作时段、个人时间和仪器占用。")
                candidate.objective = objective; candidate.notBefore = date; candidate.latestFinish = latestFinish; candidate.additionalBusyIntervals = additionalBusyIntervals
                values.append(candidate)
            } catch { failures.append(error.localizedDescription) }
        }
        add(preferences, starting: date, label: english ? "Earliest feasible schedule" : "最早可行安排")
        var alternative = preferences; alternative.allowOvernight = false
        if preferences.allowOvernight { add(alternative, starting: date, label: english ? "Avoid overnight work" : "避免过夜") }
        // Delaying to an opening boundary can reduce fragmentation near a closing or busy boundary.
        if objective == .minimizeFragmentation {
            for offset in 0...2 {
                let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
                let start = try workBounds(day, preferences, calendar).0
                if start > date { add(preferences, starting: start, label: english ? "Full work period · \(offset + 1)" : "完整工作时段 · \(offset + 1)") }
            }
        }
        guard !values.isEmpty else { throw WorkspaceError.invalid(failures.first ?? "未找到满足硬约束的方案。") }
        func score(_ candidate: ScheduleCandidate) -> [Double] {
            let finish = candidate.steps.last!.end.timeIntervalSince1970
            let fragments = Double(candidate.steps.count)
            let overnightCount = Double(candidate.steps.filter {
                // Count any spill into non-working hours, including an evening before midnight.
                guard let bounds = try? workBounds($0.start, candidate.preferences, calendar) else { return true }
                return $0.end > bounds.1
            }.count)
            switch objective {
            case .earliestFinish: return [finish, fragments, overnightCount]
            case .avoidOvernight: return [overnightCount, finish, fragments]
            case .minimizeFragmentation: return [fragments, finish, overnightCount]
            }
        }
        var ranked = values.enumerated().sorted { a, b in
            let lhs = score(a.element), rhs = score(b.element)
            for i in lhs.indices { if lhs[i] != rhs[i] { return lhs[i] < rhs[i] } }
            return a.offset < b.offset
        }.map(\.element)
        let formatter = ISO8601DateFormatter()
        for i in ranked.indices {
            ranked[i].rationale += english
                ? " Objective: \(objective.rawValue); \(ranked[i].steps.count) execution segments; finish \(formatter.string(from: ranked[i].steps.last!.end))."
                : " 目标：\(objective.rawValue)；\(ranked[i].steps.count) 个执行片段，结束 \(formatter.string(from: ranked[i].steps.last!.end))。"
        }
        ranked[0].label = (english ? "Recommended · " : "推荐 · ") + ranked[0].label
        return ranked
    }
    public static func validateCandidate(_ candidate: ScheduleCandidate, procedure: Procedure, workspace: Workspace, calendar: Calendar = .current) throws {
        var workspace = workspace; workspace.busyIntervals += candidate.additionalBusyIntervals ?? []
        try ProtocolTiming.validateExperiment(candidate.experiment, procedure: procedure)
        if let fingerprint = candidate.experiment.timingFingerprint {
            guard let version = procedure.versions.first(where: { $0.id == candidate.versionID }),
                  try ProtocolTiming.fingerprint(version: version, workspace: workspace) == fingerprint else {
                throw WorkspaceError.invalid("耗时校准已更新，请重新生成排程；不会悄悄调整已审阅的时间。 / Timing calibration changed; regenerate this schedule. Reviewed times are not silently shifted.")
            }
        }
        try validate(candidate.steps, procedure: procedure, versionID: candidate.versionID, workspace: workspace, preferences: candidate.preferences, calendar: calendar, durationEstimates: candidate.experiment.durationEstimates)
        guard candidate.steps.allSatisfy({ $0.experimentID == candidate.experiment.id }),
              candidate.notBefore.map({ (candidate.steps.first?.start ?? .distantPast) >= $0 }) ?? true,
              candidate.latestFinish.map({ (candidate.steps.last?.end ?? .distantFuture) <= $0 }) ?? true else { throw WorkspaceError.invalid("候选不符合实验归属、最早开始或截止约束。") }
    }
}
private extension ProtocolStep { func overnightAllowed(_ preferences: SchedulePreferences) -> Bool { overnightSafe && preferences.allowOvernight } }
