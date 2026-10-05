import Foundation

public struct Instrument: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var location: String; public var note: String; public var available: Bool
    public init(id: UUID = UUID(), name: String, location: String = "", note: String = "", available: Bool = true) { self.id = id; self.name = name; self.location = location; self.note = note; self.available = available }
}
public enum ExperimentStatus: String, Codable, CaseIterable, Sendable {
    case planned, active, completed, cancelled
    public var title: String { switch self { case .planned: "待开始"; case .active: "进行中"; case .completed: "已完成"; case .cancelled: "已取消" } }
}
public struct Experiment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var procedureID: UUID; public var versionID: UUID?
    public var status: ExperimentStatus = .planned; public var note = ""
    public var sampleCount: Int?
    public var scheduledSampleCount: Int?
    public var stepTimings: [StepTimingRecord] = []
    public var durationEstimates: [StepDurationEstimate] = []
    public var timingFingerprint: String?
    public init(id: UUID = UUID(), name: String, procedureID: UUID, versionID: UUID? = nil) { self.id = id; self.name = name; self.procedureID = procedureID; self.versionID = versionID }
    enum CodingKeys: String, CodingKey { case id, name, procedureID, versionID, status, note, sampleCount, scheduledSampleCount, stepTimings, durationEstimates, timingFingerprint }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name); procedureID = try c.decode(UUID.self, forKey: .procedureID)
        versionID = try c.decodeIfPresent(UUID.self, forKey: .versionID); status = try c.decodeIfPresent(ExperimentStatus.self, forKey: .status) ?? .planned
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        sampleCount = try c.decodeIfPresent(Int.self, forKey: .sampleCount)
        scheduledSampleCount = try c.decodeIfPresent(Int.self, forKey: .scheduledSampleCount)
        stepTimings = try c.decodeIfPresent([StepTimingRecord].self, forKey: .stepTimings) ?? []
        durationEstimates = try c.decodeIfPresent([StepDurationEstimate].self, forKey: .durationEstimates) ?? []
        timingFingerprint = try c.decodeIfPresent(String.self, forKey: .timingFingerprint)
    }
}
public struct PlannedStep: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var experimentID: UUID; public var title: String; public var instrumentID: UUID?
    public var instrumentIDs: [UUID] = []; public var start: Date; public var end: Date
    public var versionID: UUID?; public var blockID: String?; public var subblockID: String?; public var stepID: String?
    public var iteration = "1.1"; public var requiresAttention = true; public var isPause = false
    public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
    public var resources: Set<UUID> { Set(instrumentIDs + (instrumentID.map { [$0] } ?? [])) }
    public init(experimentID: UUID, title: String, instrumentID: UUID?, start: Date, end: Date) { self.experimentID = experimentID; self.title = title; self.instrumentID = instrumentID; self.start = start; self.end = end }
    enum CodingKeys: String, CodingKey { case id, experimentID, title, instrumentID, instrumentIDs, start, end, versionID, blockID, subblockID, stepID, iteration, requiresAttention, isPause }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); experimentID = try c.decode(UUID.self, forKey: .experimentID); title = try c.decode(String.self, forKey: .title)
        instrumentID = try c.decodeIfPresent(UUID.self, forKey: .instrumentID); instrumentIDs = try c.decodeIfPresent([UUID].self, forKey: .instrumentIDs) ?? []
        start = try c.decode(Date.self, forKey: .start); end = try c.decode(Date.self, forKey: .end)
        versionID = try c.decodeIfPresent(UUID.self, forKey: .versionID); blockID = try c.decodeIfPresent(String.self, forKey: .blockID)
        subblockID = try c.decodeIfPresent(String.self, forKey: .subblockID); stepID = try c.decodeIfPresent(String.self, forKey: .stepID)
        iteration = try c.decodeIfPresent(String.self, forKey: .iteration) ?? "1.1"
        requiresAttention = try c.decodeIfPresent(Bool.self, forKey: .requiresAttention) ?? true; isPause = try c.decodeIfPresent(Bool.self, forKey: .isPause) ?? false
    }
}
public struct AssistantConfiguration: Codable, Equatable, Sendable {
    public var provider = "OpenAI"; public var baseURL = "https://api.openai.com/v1"; public var model = "gpt-4.1-mini"
    public var temperature = 0.4; public var maxOutputTokens = 2048
    public init() {}
    enum CodingKeys: String, CodingKey { case provider, baseURL, model, temperature, maxOutputTokens }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "OpenAI"
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.openai.com/v1"
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "gpt-4.1-mini"
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.4
        maxOutputTokens = try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 2048
    }
}
public struct Workspace: Codable, Equatable, Sendable {
    public var schemaVersion = 2; public var revision = 0; public var isDemo = false
    public var language: AppLanguage = .chinese
    public var theme: AppTheme = .paper
    public var laboratory = LaboratoryConfiguration()
    public var researchDigests: [CachedResearchDigest] = []
    public var instruments: [Instrument] = []; public var procedures: [Procedure] = []; public var experiments: [Experiment] = []; public var plan: [PlannedStep] = []
    public var connections: [ProviderConnection] = []; public var models: [ModelProfile] = []; public var routing = ModelRouting()
    public var sessions: [ChatSession] = []; public var runs: [AssistantRun] = []; public var artifacts: [AssistantArtifact] = []
    public var scientificQuestions: [ScientificQuestion] = []
    public var literatureReadings: [LiteratureReading] = []
    public var busyIntervals: [BusyInterval] = []; public var preferences = SchedulePreferences()
    public var materialPreparation: [String: [String]] = [:]
    public var stepTimingConfigurations: [StepTimingConfiguration] = []
    public init() {
        let connection = ProviderConnection(name: "OpenAI")
        let model = ModelProfile(connectionID: connection.id, name: "默认模型", model: "gpt-4.1-mini")
        connections = [connection]; models = [model]; routing.assistant = model.id
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, revision, isDemo, language, theme, laboratory, researchDigests, instruments, procedures, experiments, plan, assistant, connections, models, routing, sessions, runs, artifacts, scientificQuestions, literatureReadings, busyIntervals, preferences, materialPreparation, stepTimingConfigurations }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 || version == 2 else { throw WorkspaceError.invalid("不支持此工作区版本，源文件不会被覆盖。") }
        schemaVersion = 2; revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        isDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .chinese
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .paper
        laboratory = try c.decodeIfPresent(LaboratoryConfiguration.self, forKey: .laboratory) ?? LaboratoryConfiguration()
        researchDigests = try c.decodeIfPresent([CachedResearchDigest].self, forKey: .researchDigests) ?? []
        materialPreparation = try c.decodeIfPresent([String: [String]].self, forKey: .materialPreparation) ?? [:]
        stepTimingConfigurations = try c.decodeIfPresent([StepTimingConfiguration].self, forKey: .stepTimingConfigurations) ?? []
        scientificQuestions = try c.decodeIfPresent([ScientificQuestion].self, forKey: .scientificQuestions) ?? []
        literatureReadings = try c.decodeIfPresent([LiteratureReading].self, forKey: .literatureReadings) ?? []
        instruments = try c.decode([Instrument].self, forKey: .instruments); procedures = try c.decode([Procedure].self, forKey: .procedures)
        experiments = try c.decode([Experiment].self, forKey: .experiments); plan = try c.decode([PlannedStep].self, forKey: .plan)
        if version == 1 {
            let old = try c.decodeIfPresent(AssistantConfiguration.self, forKey: .assistant) ?? AssistantConfiguration()
            var connection = ProviderConnection(name: old.provider, baseURL: old.baseURL); connection.legacyKey = true
            connection.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            var model = ModelProfile(connectionID: connection.id, name: old.model, model: old.model)
            model.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!; model.temperature = old.temperature; model.maxOutputTokens = old.maxOutputTokens
            connections = [connection]; models = [model]; routing.assistant = model.id
            for i in experiments.indices { experiments[i].versionID = procedures.first { $0.id == experiments[i].procedureID }?.currentVersion.id }
        } else {
            connections = try c.decode([ProviderConnection].self, forKey: .connections); models = try c.decode([ModelProfile].self, forKey: .models); routing = try c.decode(ModelRouting.self, forKey: .routing)
            sessions = try c.decodeIfPresent([ChatSession].self, forKey: .sessions) ?? []; runs = try c.decodeIfPresent([AssistantRun].self, forKey: .runs) ?? []; artifacts = try c.decodeIfPresent([AssistantArtifact].self, forKey: .artifacts) ?? []
            busyIntervals = try c.decodeIfPresent([BusyInterval].self, forKey: .busyIntervals) ?? []; preferences = try c.decodeIfPresent(SchedulePreferences.self, forKey: .preferences) ?? SchedulePreferences()
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(revision, forKey: .revision); try c.encode(isDemo, forKey: .isDemo)
        try c.encode(language, forKey: .language)
        try c.encode(theme, forKey: .theme)
        try c.encode(laboratory, forKey: .laboratory); try c.encode(researchDigests, forKey: .researchDigests)
        try c.encode(instruments, forKey: .instruments); try c.encode(procedures, forKey: .procedures); try c.encode(experiments, forKey: .experiments); try c.encode(plan, forKey: .plan)
        try c.encode(connections, forKey: .connections); try c.encode(models, forKey: .models); try c.encode(routing, forKey: .routing)
        try c.encode(sessions, forKey: .sessions); try c.encode(runs, forKey: .runs); try c.encode(artifacts, forKey: .artifacts)
        try c.encode(scientificQuestions, forKey: .scientificQuestions)
        try c.encode(literatureReadings, forKey: .literatureReadings)
        try c.encode(busyIntervals, forKey: .busyIntervals); try c.encode(preferences, forKey: .preferences)
        try c.encode(materialPreparation, forKey: .materialPreparation)
        try c.encode(stepTimingConfigurations, forKey: .stepTimingConfigurations)
    }
    public func validated() throws {
        try laboratory.validated()
        guard researchDigests.count <= 30, Set(researchDigests.map(\.key)).count == researchDigests.count,
              try JSONEncoder().encode(researchDigests).count <= 12_000_000 else { throw WorkspaceError.invalid("Research digest cache exceeds its limits.") }
        for digest in researchDigests { try digest.validated() }
        for (version, ids) in materialPreparation {
            guard UUID(uuidString: version) != nil, ids.count <= 500, Set(ids).count == ids.count,
                  ids.allSatisfy({ !$0.isEmpty && $0.count <= 128 }) else { throw WorkspaceError.invalid("材料准备清单的版本或条目无效。") }
        }
        guard schemaVersion == 2, revision >= 0 else { throw WorkspaceError.invalid("无效工作区版本。") }; try preferences.validated()
        func unique<T: Hashable>(_ values: [T]) throws { guard Set(values).count == values.count else { throw WorkspaceError.invalid("工作区包含重复记录。") } }
        try unique(instruments.map(\.id)); try unique(procedures.map(\.id)); try unique(experiments.map(\.id)); try unique(plan.map(\.id))
        try unique(connections.map(\.id)); try unique(models.map(\.id)); try unique(sessions.map(\.id)); try unique(runs.map(\.id)); try unique(artifacts.map(\.id)); try unique(busyIntervals.map(\.id))
        try unique(scientificQuestions.map(\.id))
        try unique(literatureReadings.map(\.id))
        for connection in connections { try connection.validated() }
        for model in models { try model.validated(); guard connections.contains(where: { $0.id == model.connectionID }) else { throw WorkspaceError.invalid("模型连接不存在。") } }
        for id in [routing.assistant, routing.protocolBuilder, routing.scheduling, routing.report].compactMap({ $0 }) { guard models.contains(where: { $0.id == id }) else { throw WorkspaceError.invalid("默认模型不存在。") } }
        guard instruments.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw WorkspaceError.invalid("仪器名称不能为空。") }
        for procedure in procedures {
            guard !procedure.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !procedure.versions.isEmpty else { throw WorkspaceError.invalid("Protocol 名称或版本为空。") }
            try unique(procedure.versions.map(\.id)); try unique(procedure.versions.map(\.number))
            for version in procedure.versions { try version.content.validated(); for step in version.content.atomicSteps { if let id = step.instrumentID, !instruments.contains(where: { $0.id == id }) { throw WorkspaceError.invalid("Protocol 引用了不存在的仪器。") } } }
        }
        for experiment in experiments {
            guard !experiment.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let procedure = procedures.first(where: { $0.id == experiment.procedureID }), experiment.versionID.map({ id in procedure.versions.contains { $0.id == id } }) ?? true else { throw WorkspaceError.invalid("实验引用无效的 Protocol 版本。") }
            try ProtocolTiming.validateExperiment(experiment, procedure: procedure)
        }
        guard stepTimingConfigurations.count <= 10000 else { throw WorkspaceError.invalid("Too many timing configurations.") }
        try unique(stepTimingConfigurations.map(\.id))
        for configuration in stepTimingConfigurations {
            try configuration.validated()
            guard procedures.flatMap(\.versions).contains(where: { $0.id == configuration.versionID && $0.content.atomicSteps.contains { $0.id == configuration.stepID && (configuration.mode != .fixed || configuration.baselineMinutes == $0.durationMinutes) } }) else {
                throw WorkspaceError.invalid("Timing configuration references a missing Protocol step/version.")
            }
        }
        for question in scientificQuestions { try question.validated(experimentIDs: Set(experiments.map(\.id))) }
        for reading in literatureReadings { try reading.validated() }
        for step in plan { guard experiments.contains(where: { $0.id == step.experimentID }), step.start < step.end, step.resources.allSatisfy({ id in instruments.contains { $0.id == id } }) else { throw WorkspaceError.invalid("排程引用或时间无效。") } }
        for busy in busyIntervals { guard !busy.title.isEmpty, busy.start < busy.end, busy.instrumentID.map({ id in instruments.contains { $0.id == id } }) ?? true else { throw WorkspaceError.invalid("忙碌时段设置无效。") } }
        for session in sessions {
            try unique(session.messages.map(\.id))
            guard session.modelID.map({ id in models.contains { $0.id == id } }) ?? true,
                  session.messages.allSatisfy({ ["user", "assistant"].contains($0.role) }) else { throw WorkspaceError.invalid("会话模型或消息角色无效。") }
        }
        for run in runs { guard sessions.contains(where: { $0.id == run.sessionID }) else { throw WorkspaceError.invalid("任务引用的会话不存在。") }; try run.intent?.validated() }
        for artifact in artifacts {
            try artifact.paper?.validated()
            guard !artifact.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.invalid("产物名称不能为空。") }
            if let p = artifact.procedure { guard !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.invalid("Protocol 草稿名称不能为空。") }; for v in p.versions { try v.content.validated() } }
            try unique(artifact.candidates.map(\.id))
            for c in artifact.candidates {
                if let p = procedures.first(where: { $0.id == c.procedureID }) { try ProtocolTiming.validateExperiment(c.experiment, procedure: p) }
                else if !c.experiment.durationEstimates.isEmpty || !c.experiment.stepTimings.isEmpty { throw WorkspaceError.invalid("Missing candidate Protocol.") }
                try c.preferences.validated()
                for busy in c.additionalBusyIntervals ?? [] {
                    guard !busy.title.isEmpty, busy.start < busy.end, busy.instrumentID.map({ id in instruments.contains { $0.id == id } }) ?? true else { throw WorkspaceError.invalid("候选忙碌约束无效。") }
                }
                guard c.notBefore.map({ date in c.steps.allSatisfy { $0.start >= date } }) ?? true,
                      c.latestFinish.map({ date in c.steps.allSatisfy { $0.end <= date } }) ?? true else { throw WorkspaceError.invalid("候选开始或截止约束无效。") }
                guard c.experiment.procedureID == c.procedureID, c.experiment.versionID == c.versionID,
                      !c.steps.isEmpty, c.steps.allSatisfy({ $0.experimentID == c.experiment.id && $0.versionID == c.versionID && $0.start < $0.end }) else { throw WorkspaceError.invalid("候选排程引用或时间无效。") }
            }
        }
    }
    public static func demo(now: Date = Date(), calendar: Calendar = .current) -> Workspace {
        var result = Workspace(); result.isDemo = true
        let centrifuge = Instrument(name: "台式离心机", location: "共享设备区 · 02"), microscope = Instrument(name: "荧光显微镜", location: "成像室 · 01"), reader = Instrument(name: "酶标仪", location: "分析台 · 03")
        result.instruments = [centrifuge, microscope, reader]
        var content = ProtocolContent(blocks: [
            ProtocolBlock(title: "样本准备", subblocks: [ProtocolSubblock(title: "制备与分离", steps: [ProtocolStep(title: "准备样本与试剂", minutes: 30), ProtocolStep(title: "离心与样本分离", minutes: 20, instrumentID: centrifuge.id)])]),
            ProtocolBlock(title: "染色与成像", subblocks: [ProtocolSubblock(title: "荧光观察", steps: [ProtocolStep(title: "荧光染色", minutes: 45), ProtocolStep(title: "显微成像", minutes: 50, instrumentID: microscope.id)])])
        ]); content.renumber()
        content.objective = "观察样本的荧光标记分布，熟悉样本制备与显微成像的完整流程。此为界面演示，不是已验证的实验方法。"
        content.materials = [
            ProtocolMaterial(name: "待观察样本", category: .sample, specification: "样本类型待确认", quantity: "待确认"),
            ProtocolMaterial(name: "荧光染色试剂", specification: "具体试剂与浓度待确认", quantity: "待确认"),
            ProtocolMaterial(name: "离心管", category: .consumable, specification: "与样本及设备兼容", quantity: "待确认"),
            ProtocolMaterial(name: "台式离心机", category: .equipment, quantity: "1 台"),
            ProtocolMaterial(name: "荧光显微镜", category: .equipment, quantity: "1 台")
        ]
        content.principles = ["离心利用沉降特性的差异分离样本组分；实际条件须根据样本与设备确定。", "荧光标记在相应激发条件下产生可检测的发射信号，用于观察标记分布。"]
        content.precautions = ["演示时间仅用于查看排程界面；样本、染色方法与设备参数均需由实验人员确认。", "离心前检查转子、管材兼容性与配平；成像时注意避光及样本的光漂白。"]
        let preparation = Procedure(name: "样本制备与荧光观察", note: "演示三层 Protocol", content: content, status: .published)
        let assay = Procedure(name: "微孔板吸光度测定", steps: [ProcedureStep(title: "配制标准品", minutes: 25), ProcedureStep(title: "加样与孵育", minutes: 35), ProcedureStep(title: "读取吸光度", minutes: 20, instrumentID: reader.id)])
        result.procedures = [preparation, assay]
        let day = calendar.startOfDay(for: now)
        for (name, procedure, offset, hour) in [("样本 A · 荧光观察", preparation, 0, 9), ("标准曲线 · 吸光度", assay, 0, 14), ("样本 B · 重复观察", preparation, 1, 10)] {
            let experiment = Experiment(name: name, procedureID: procedure.id, versionID: procedure.currentVersion.id)
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: offset, to: day)!)!
            if let steps = try? Planner.schedule(experiment: experiment, procedure: procedure, in: result, starting: start, calendar: calendar) { result.experiments.append(experiment); result.plan += steps }
        }
        let finding = ScienceClaim(kind: .observation, text: "演示观察：样本 A 的中心区域荧光信号高于样本 B。", confidence: 0.65,
            sourceNote: "界面演示用虚构数据，不是实测结果。")
        let alternative = ScienceClaim(kind: .hypothesis, text: "曝光设置差异也可能解释部分信号变化。", confidence: 0.5,
            sourceNote: "演示备选解释，待真实实验检验。")
        let conclusion = ScienceClaim(kind: .conclusion, text: "两组样本的荧光分布可能不同，仍需控制成像参数后重复验证。", confidence: 0.35,
            sourceNote: "仅用于展示证据链，不是科学结论。")
        let imageA = AtomicExperiment(title: "样本 A 独立成像（演示）", method: "固定视野后采集图像", status: .recorded,
            observedResult: "虚构演示：中心区域信号较强。", sourceNote: "虚构界面数据，非真实实验。")
        let imageB = AtomicExperiment(title: "样本 B 独立成像（演示）", method: "使用相同标称成像流程", status: .recorded,
            observedResult: "虚构演示：信号分布较均匀。", sourceNote: "虚构界面数据，非真实实验。")
        let exposure = AtomicExperiment(title: "曝光参数复核（演示）", method: "比较两次采集设置", status: .recorded,
            observedResult: "虚构演示：曝光值不一致。", sourceNote: "虚构界面数据，非真实实验。")
        let repeatTest = AtomicExperiment(title: "统一参数复测（尚未执行）", method: "同一曝光、增益和染色条件下重复采集")
        let settings = ScienceClaim(kind: .observation, text: "演示复核：两次成像的曝光设置不一致。", sourceNote: "虚构界面数据，非真实实验。")
        let reliability = ScienceClaim(kind: .conclusion, text: "现有样本差异不能排除成像设置混杂，需要统一参数复测。", sourceNote: "演示逻辑，非真实科学结论。")
        result.scientificQuestions = [ScientificQuestion(title: "演示：两组样本的荧光分布是否不同？",
            detail: "以下观察均为界面演示用虚构数据。图中的连线表示待核实的研究判断，不构成真实证据或证明。",
            claims: [conclusion, reliability, finding, alternative, settings],
            relations: [ScienceRelation(fromClaimID: finding.id, toClaimID: conclusion.id, kind: .supports, explanation: "两组示例图像呈现不同空间分布，只支持测量条件内的差异。", limitations: "尚未排除曝光设置混杂。"),
                        ScienceRelation(fromClaimID: settings.id, toClaimID: alternative.id, kind: .supports, explanation: "采集参数不一致，使成像混杂成为需要排除的解释。"),
                        ScienceRelation(fromClaimID: alternative.id, toClaimID: reliability.id, kind: .supports, explanation: "已有参数混杂可能性，所以不能把现有差异归因于样本本身。"),
                        ScienceRelation(fromClaimID: alternative.id, toClaimID: conclusion.id, kind: .contradicts, explanation: "跨树证据：采集混杂挑战第一结果的样本差异解释。")],
            atomicExperiments: [imageA, imageB, exposure, repeatTest],
            evidenceLinks: [AtomicEvidenceLink(atomicExperimentID: imageA.id, claimID: finding.id, kind: .supports, explanation: "示例A中心信号较强，与B的分布构成比较。"),
                            AtomicEvidenceLink(atomicExperimentID: imageB.id, claimID: finding.id, kind: .supports, explanation: "示例B分布较均匀，补充A/B比较。"),
                            AtomicEvidenceLink(atomicExperimentID: exposure.id, claimID: settings.id, kind: .supports, explanation: "示例采集元数据记录不同曝光值。")],
            mainline: [ScienceMainlineStep(claimID: conclusion.id, question: "两组图像是否呈现分布差异？", motivation: "先描述测到的差异，再讨论差异来自哪里。", origin: .inferred),
                       ScienceMainlineStep(claimID: reliability.id, question: "差异能否归因于样本，而非成像设置？", motivation: "第一结果描述了差异，但尚未排除采集参数混杂；因此核对成像条件。", origin: .inferred)])]
        return result
    }
}
public enum WorkspaceError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
