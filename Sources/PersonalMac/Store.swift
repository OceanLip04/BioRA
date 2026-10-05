import AppKit
import CryptoKit
import Observation
import PersonalCore
import SwiftUI

@MainActor @Observable final class PersonalStore {
    private(set) var workspace = Workspace()
    var errorMessage: String?
    private(set) var readOnly = false
    private(set) var isLoading = false
    private(set) var isPreview = false
    @ObservationIgnored private var loadingStarted = false
    let file: WorkspaceFile
    var activeSessionID: UUID?
    var runningRunID: UUID?
    var streamingText = ""
    @ObservationIgnored var runningTask: Task<Void, Never>?
    @ObservationIgnored var networkSession: URLSession?
    var researchFetching = false
    var researchMessage: String?
    var researchFailure: String?
    @ObservationIgnored var researchNextAttempt: [String: Date] = [:]
    var pendingApproval: String?
    var requestedPage: String?
    var requestedDataAction: String?
    @ObservationIgnored var approvalContinuation: CheckedContinuation<Bool, Never>?

    init(directory: URL, demo: Bool, loadImmediately: Bool = true) {
        file = WorkspaceFile(directory: directory)
        if !loadImmediately { isLoading = true; readOnly = true; return }
        do {
            workspace = try Self.loadedWorkspace(file: file, demo: demo)
            activeSessionID = workspace.sessions.last?.id
        } catch { readOnly = true; errorMessage = "工作区无法读取，已停止写入以保护原数据。\n\(error.localizedDescription)" }
    }

    /// Isolated, read-only UI review: no SQLite load, migration, key lookup, or persistence.
    init(previewDirectory: URL, previewWorkspace: Workspace) {
        file = WorkspaceFile(directory: previewDirectory)
        workspace = previewWorkspace
        readOnly = true; isPreview = true
    }

    /// Filesystem authorization or a slow external drive must not block AppKit's main thread.
    func loadWorkspace(demo: Bool) async {
        guard isLoading, !loadingStarted else { return }
        loadingStarted = true
        let source = file
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { try Self.loadedWorkspace(file: source, demo: demo) }.value
            workspace = loaded; activeSessionID = loaded.sessions.last?.id; readOnly = false
        } catch { readOnly = true; errorMessage = "Workspace could not be loaded. Existing data are protected. / 工作区无法读取，原数据受到保护。\n\(error.localizedDescription)" }
        isLoading = false
    }

    private nonisolated static func loadedWorkspace(file: WorkspaceFile, demo: Bool) throws -> Workspace {
            var workspace: Workspace
            if let existing = try file.load() { workspace = existing }
            else { workspace = demo ? .demo() : Workspace(); try file.save(workspace) }
            let legacyReadings = workspace.scientificQuestions.compactMap(LiteratureReading.fromLegacyPDFQuestion)
            if !legacyReadings.isEmpty {
                let backup = file.directory.appendingPathComponent("before-literature-migration.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try file.export(workspace, to: backup) }
                let revision = workspace.revision
                do {
                    var current = workspace
                    let existingIDs = Set(current.literatureReadings.map(\.id))
                    current.literatureReadings += legacyReadings.filter { !existingIDs.contains($0.id) }
                    let movedIDs = Set(legacyReadings.map(\.id))
                    current.scientificQuestions.removeAll { movedIDs.contains($0.id) }
                    current.revision += 1; try file.save(current, expectedRevision: revision); workspace = current
                }
            }
            if workspace.runs.contains(where: { $0.status == .running }) {
                let revision = workspace.revision
                    for index in workspace.runs.indices where workspace.runs[index].status == .running {
                        workspace.runs[index].status = .interrupted
                        workspace.runs[index].events.append(RunEvent("App 已重启；已保存结果保留，可从会话继续任务。"))
                    }
                workspace.revision += 1; try file.save(workspace, expectedRevision: revision)
            }
            return workspace
    }
    func commit(_ change: (inout Workspace) throws -> Void) throws {
        guard !readOnly else { throw WorkspaceError.invalid("工作区处于只读保护状态。") }
        var next = workspace; try change(&next); next.revision += 1
        try file.save(next, expectedRevision: workspace.revision); workspace = next
    }
    func setLanguage(_ language: AppLanguage) throws {
        guard runningRunID == nil else { throw WorkspaceError.invalid("Wait for the current assistant task to finish before changing the language. / 请等待当前助手任务结束后再切换语言。") }
        try commit { $0.language = language }
    }
    func setTheme(_ theme: AppTheme) throws {
        if isPreview { workspace.theme = theme; ThemeAppearance.shared.theme = theme; return }
        try commit { $0.theme = theme }
        ThemeAppearance.shared.theme = theme
    }
    func assistantText(_ chinese: String, _ english: String) -> String {
        workspace.language == .english ? english : chinese
    }
    func displayModelName(_ name: String) -> String {
        workspace.language == .english && name == "默认模型" ? "Default Model" : name
    }
    func assistantReference(_ title: String, id: UUID) -> String {
        workspace.language == .english && AppLanguage.containsHan(title) ? "record \(id.uuidString)" : title
    }
    func saveInstrument(_ instrument: Instrument) throws {
        try commit { workspace in
            if let index = workspace.instruments.firstIndex(where: { $0.id == instrument.id }) { workspace.instruments[index] = instrument }
            else { workspace.instruments.append(instrument) }
        }
    }
    func saveScientificQuestion(_ question: ScientificQuestion) throws {
        try commit { workspace in
            try question.validated(experimentIDs: Set(workspace.experiments.map(\.id)))
            if let index = workspace.scientificQuestions.firstIndex(where: { $0.id == question.id }) {
                guard workspace.scientificQuestions[index].revision == question.revision else { throw WorkspaceError.invalid("科学问题已在别处更新，请重新打开后再编辑。") }
                workspace.scientificQuestions[index] = question
                workspace.scientificQuestions[index].revision += 1
                workspace.scientificQuestions[index].updatedAt = Date()
            } else {
                guard question.revision == 0 else { throw WorkspaceError.invalid("新建科学问题的版本无效。") }
                var created = question; created.revision = 1
                workspace.scientificQuestions.append(created)
            }
        }
    }
    func saveLiteratureReading(_ reading: LiteratureReading, originalPDF: Data) throws {
        guard originalPDF.count <= 20_000_000 else { throw WorkspaceError.invalid("PDF 超出文献阅读库的 20 MB 上限。") }
        let digest = SHA256.hash(data: originalPDF).map { String(format: "%02x", $0) }.joined()
        guard digest.hasPrefix(reading.fingerprint.lowercased()) else { throw WorkspaceError.invalid("PDF 内容与解析记录不匹配。") }
        let storageName = digest + ".pdf"
        let directory = file.directory.appendingPathComponent("LiteraturePDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(storageName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            try originalPDF.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        var saved = reading
        saved.pdfStorageName = storageName
        try commit { workspace in
            try saved.validated()
            guard !workspace.literatureReadings.contains(where: { $0.id == saved.id }) else {
                throw WorkspaceError.invalid("这条文献阅读记录已经保存。")
            }
            workspace.literatureReadings.append(saved)
        }
    }
    func setLiteratureGraphPosition(readingID: UUID, nodeID: UUID, point: ScienceGraphPoint?) throws {
        try commit { workspace in
            guard let index = workspace.literatureReadings.firstIndex(where: { $0.id == readingID }) else {
                throw WorkspaceError.invalid("文献阅读记录不存在，请重新打开。")
            }
            let graph = workspace.literatureReadings[index].graph
            let validIDs = [graph.id] + graph.claims.map(\.id) + graph.atomicExperiments.map(\.id)
            guard validIDs.contains(nodeID) else { throw WorkspaceError.invalid("图谱节点不存在，请重新打开。") }
            workspace.literatureReadings[index].graph.graphPositions[nodeID.uuidString] = point
        }
    }
    func resetLiteratureGraphLayout(readingID: UUID) throws {
        try commit { workspace in
            guard let index = workspace.literatureReadings.firstIndex(where: { $0.id == readingID }) else {
                throw WorkspaceError.invalid("文献阅读记录不存在，请重新打开。")
            }
            workspace.literatureReadings[index].graph.graphPositions = [:]
        }
    }
    func deleteScientificQuestion(_ id: UUID) throws {
        try commit { $0.scientificQuestions.removeAll { $0.id == id } }
    }
    func saveProcedure(_ procedure: Procedure) throws {
        try commit { workspace in
            if let index = workspace.procedures.firstIndex(where: { $0.id == procedure.id }) {
                let old = workspace.procedures[index]
                guard old.revision == procedure.revision, old.versions.allSatisfy({ previous in procedure.versions.contains(previous) }) else { throw WorkspaceError.invalid("Protocol 已有更新，或正在修改历史版本；请重新打开编辑器。") }
                workspace.procedures[index] = procedure; workspace.procedures[index].revision += 1
            } else { workspace.procedures.append(procedure) }
        }
    }
    func setMaterialPrepared(_ materialID: String, versionID: UUID, prepared: Bool) throws {
        try commit { workspace in
            let versions = workspace.procedures.flatMap(\.versions) + workspace.artifacts.compactMap(\.procedure).flatMap(\.versions)
            guard let version = versions.first(where: { $0.id == versionID }), version.content.materials.contains(where: { $0.id == materialID }) else {
                throw WorkspaceError.invalid("材料或 Protocol 版本已变化，请重新打开清单。")
            }
            let key = versionID.uuidString
            var ids = Set(workspace.materialPreparation[key] ?? [])
            if prepared { ids.insert(materialID) } else { ids.remove(materialID) }
            if ids.isEmpty { workspace.materialPreparation.removeValue(forKey: key) }
            else { workspace.materialPreparation[key] = ids.sorted() }
        }
    }
    func saveConnection(_ connection: ProviderConnection) throws {
        try commit { workspace in
            if let i = workspace.connections.firstIndex(where: { $0.id == connection.id }) { workspace.connections[i] = connection }
            else { workspace.connections.append(connection) }
        }
    }
    func saveModel(_ model: ModelProfile) throws {
        try commit { workspace in
            if let i = workspace.models.firstIndex(where: { $0.id == model.id }) { workspace.models[i] = model }
            else { workspace.models.append(model) }
            if workspace.routing.assistant == nil { workspace.routing.assistant = model.id }
        }
    }
    func saveRouting(_ routing: ModelRouting) throws { try commit { $0.routing = routing } }
    func deleteModel(_ id: UUID) throws {
        try commit { workspace in
            workspace.models.removeAll { $0.id == id }
            if workspace.routing.assistant == id { workspace.routing.assistant = workspace.models.first?.id }
            if workspace.routing.protocolBuilder == id { workspace.routing.protocolBuilder = nil }
            if workspace.routing.scheduling == id { workspace.routing.scheduling = nil }
            if workspace.routing.report == id { workspace.routing.report = nil }
            for index in workspace.sessions.indices where workspace.sessions[index].modelID == id { workspace.sessions[index].modelID = nil }
        }
    }
    func keyAccount(_ connection: ProviderConnection) -> String { file.directory.standardizedFileURL.path + "/connection/" + connection.id.uuidString }
    func apiKey(_ connection: ProviderConnection) throws -> String? {
        let saved = try AssistantKeychain().read(account: keyAccount(connection))
        if saved != nil { return saved }
        return connection.legacyKey ? try AssistantKeychain().read(account: file.directory.standardizedFileURL.path) : nil
    }
    func resolveModel(_ id: UUID?) throws -> (ProviderConnection, ModelProfile, String?) {
        guard let model = workspace.models.first(where: { $0.id == (id ?? workspace.routing.assistant) }), let connection = workspace.connections.first(where: { $0.id == model.connectionID }) else { throw WorkspaceError.invalid("请先添加连接和模型。") }
        let key = try apiKey(connection)
        guard connection.isLocal || !(key ?? "").isEmpty else { throw WorkspaceError.invalid("请为连接「\(connection.name)」配置 API Key。") }
        return (connection, model, key)
    }
    func addExperiment(name: String, procedureID: UUID, date: Date, sampleCount: Int? = nil) throws {
        let artifact = try scheduleArtifact(name: name, procedureID: procedureID, date: date, preferences: workspace.preferences, sampleCount: sampleCount)
        _ = try applySchedule(artifactID: artifact.id, candidateID: artifact.candidates[0].id)
    }
    func scheduleArtifact(name: String, procedureID: UUID, date: Date, preferences: SchedulePreferences, objective: ScheduleObjective = .earliestFinish, latestFinish: Date? = nil, additionalBusyIntervals: [BusyInterval] = [], sampleCount: Int? = nil) throws -> AssistantArtifact {
        guard let procedure = workspace.procedures.first(where: { $0.id == procedureID }) else { throw WorkspaceError.invalid("请选择 Protocol。") }
        var artifact = AssistantArtifact(kind: .schedule, title: name)
        artifact.candidates = try Planner.candidates(name: name, procedure: procedure, workspace: workspace, starting: max(date, Date()), preferences: preferences, objective: objective, latestFinish: latestFinish, additionalBusyIntervals: additionalBusyIntervals, sampleCount: sampleCount)
        try commit { $0.artifacts.append(artifact) }; return artifact
    }
    @discardableResult func applySchedule(artifactID: UUID, candidateID: UUID) throws -> UUID {
        var result: UUID?
        try commit { workspace in
            guard let index = workspace.artifacts.firstIndex(where: { $0.id == artifactID }), let candidate = workspace.artifacts[index].candidates.first(where: { $0.id == candidateID }) else { throw WorkspaceError.invalid("排程候选不存在。") }
            if let applied = workspace.artifacts[index].appliedID { result = applied; return }
            guard (candidate.steps.first?.start ?? .distantPast) >= Date() else {
                throw WorkspaceError.invalid("此排程已过开始时间，请重新生成；不会自动移动已审阅的步骤。 / This schedule's start has passed; regenerate it rather than silently moving reviewed steps.")
            }
            guard let procedure = workspace.procedures.first(where: { $0.id == candidate.procedureID }), procedure.revision == candidate.sourceRevision else { throw WorkspaceError.invalid("Protocol 已更新，请重新生成排程。") }
            try Planner.validateCandidate(candidate, procedure: procedure, workspace: workspace)
            workspace.experiments.append(candidate.experiment); workspace.plan += candidate.steps
            workspace.artifacts[index].appliedID = candidate.experiment.id; result = candidate.experiment.id
        }
        return result!
    }
    @discardableResult func saveProtocolArtifact(_ id: UUID, published: Bool) throws -> UUID {
        var result: UUID?
        try commit { workspace in
            guard let i = workspace.artifacts.firstIndex(where: { $0.id == id }), var draft = workspace.artifacts[i].procedure else { throw WorkspaceError.invalid("Protocol 草稿不存在。") }
            if let applied = workspace.artifacts[i].appliedID { result = applied; return }
            var version = draft.versions.last!; version.status = published ? .published : .draft
            if let p = workspace.procedures.firstIndex(where: { $0.id == draft.id }) {
                guard workspace.procedures[p].revision == workspace.artifacts[i].expectedRevision else { throw WorkspaceError.invalid("原 Protocol 已改变，请重新生成修改。") }
                version.number = (workspace.procedures[p].versions.map(\.number).max() ?? 0) + 1
                workspace.procedures[p].versions.append(version); workspace.procedures[p].revision += 1
                workspace.procedures[p].name = draft.name; workspace.procedures[p].note = draft.note
            } else { draft.versions = [version]; workspace.procedures.append(draft) }
            workspace.artifacts[i].appliedID = draft.id; result = draft.id
        }
        return result!
    }
    func setStatus(_ id: UUID, _ status: ExperimentStatus) {
        do { try commit { workspace in if let index = workspace.experiments.firstIndex(where: { $0.id == id }) { workspace.experiments[index].status = status } } }
        catch { errorMessage = error.localizedDescription }
    }
    func saveBusy(_ busy: BusyInterval) throws { try commit { $0.busyIntervals.append(busy) } }
    func removeBusy(_ id: UUID) { do { try commit { $0.busyIntervals.removeAll { $0.id == id } } } catch { errorMessage = error.localizedDescription } }
    func savePreferences(_ preferences: SchedulePreferences) throws { try commit { $0.preferences = preferences } }
    func saveNote(_ id: UUID, _ note: String) throws { try commit { w in guard let i = w.experiments.firstIndex(where: { $0.id == id }) else { throw WorkspaceError.invalid("实验不存在。") }; w.experiments[i].note = note } }
    func restore(_ source: URL) throws {
        guard runningRunID == nil, (try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 50_000_000 else { throw WorkspaceError.invalid("请先停止任务；备份最多 50 MB。") }
        var restored = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: source)); try restored.validated()
        for i in restored.runs.indices where restored.runs[i].status == .running { restored.runs[i].status = .interrupted }
        for i in restored.connections.indices { restored.connections[i].legacyKey = false }
        let backup = file.directory.appendingPathComponent("before-restore-\(UUID().uuidString).json")
        try file.export(workspace, to: backup)
        restored.revision = workspace.revision
        try commit { $0 = restored }; activeSessionID = workspace.sessions.last?.id
    }
    @discardableResult func newSession() throws -> UUID {
        var session = ChatSession(modelID: workspace.routing.assistant)
        session.title = assistantText("新的实验任务", "New Experiment Task")
        try commit { $0.sessions.append(session) }; activeSessionID = session.id; return session.id
    }
    func selectModel(_ id: UUID?) {
        do { let sessionID = try activeSessionID ?? newSession(); try commit { workspace in if let i = workspace.sessions.firstIndex(where: { $0.id == sessionID }) { workspace.sessions[i].modelID = id } } }
        catch { errorMessage = error.localizedDescription }
    }
    var activeSession: ChatSession? { workspace.sessions.first { $0.id == activeSessionID } }
    var selectedModelID: UUID? { activeSession?.modelID ?? workspace.routing.assistant }
    func instrumentName(_ id: UUID?) -> String { workspace.instruments.first(where: { $0.id == id })?.name ?? "手动操作" }
    func experimentName(_ id: UUID) -> String { workspace.experiments.first(where: { $0.id == id })?.name ?? "实验" }
    var activePlan: [PlannedStep] { let active = Set(workspace.experiments.filter { $0.status != .cancelled }.map(\.id)); return workspace.plan.filter { active.contains($0.experimentID) }.sorted { $0.start < $1.start } }
}
