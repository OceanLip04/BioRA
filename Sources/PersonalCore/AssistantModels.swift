import Foundation

public struct ProviderConnection: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name = "自定义连接"
    public var baseURL = "https://api.openai.com/v1"
    public var legacyKey = false
    public init(name: String = "自定义连接", baseURL: String = "https://api.openai.com/v1") { self.name = name; self.baseURL = baseURL }
    public var isLocal: Bool { URLComponents(string: baseURL)?.host.map { ["localhost", "127.0.0.1", "::1", "[::1]"].contains($0.lowercased()) } ?? false }
    public func validated() throws {
        guard let c = URLComponents(string: baseURL), let scheme = c.scheme?.lowercased(), let host = c.host, !host.isEmpty,
              c.url != nil, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              scheme == "https" || (scheme == "http" && isLocal),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.invalid("连接需要名称和 HTTPS API 地址；本机可用 HTTP。") }
    }
    public func endpoint(_ suffix: String) throws -> URL {
        try validated(); var c = URLComponents(string: baseURL)!
        var path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") { path = String(path.dropLast("chat/completions".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        c.path = "/" + [path, suffix].filter { !$0.isEmpty }.joined(separator: "/")
        return c.url!
    }
}
public struct ModelProfile: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var connectionID: UUID; public var name: String; public var model: String
    public var temperature: Double? = 0.4; public var maxOutputTokens = 4096
    public var supportsTools = true; public var supportsJSON = false; public var supportsVision = false; public var stream = true
    public var tokenParameter = "max_tokens"
    public init(connectionID: UUID, name: String = "新模型", model: String = "") { self.connectionID = connectionID; self.name = name; self.model = model }
    enum CodingKeys: String, CodingKey { case id, connectionID, name, model, temperature, maxOutputTokens, supportsTools, supportsJSON, supportsVision, stream, tokenParameter }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); connectionID = try c.decode(UUID.self, forKey: .connectionID)
        name = try c.decode(String.self, forKey: .name); model = try c.decode(String.self, forKey: .model)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        maxOutputTokens = try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 4096
        supportsTools = try c.decodeIfPresent(Bool.self, forKey: .supportsTools) ?? true
        supportsJSON = try c.decodeIfPresent(Bool.self, forKey: .supportsJSON) ?? false
        supportsVision = try c.decodeIfPresent(Bool.self, forKey: .supportsVision) ?? false
        stream = try c.decodeIfPresent(Bool.self, forKey: .stream) ?? true
        tokenParameter = try c.decodeIfPresent(String.self, forKey: .tokenParameter) ?? "max_tokens"
    }
    public func validated() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (256...32768).contains(maxOutputTokens), ["max_tokens", "max_completion_tokens"].contains(tokenParameter), temperature.map({ $0.isFinite && (0...2).contains($0) }) ?? true else { throw WorkspaceError.invalid("模型需要显示名、模型 ID 和有效生成参数。") }
    }
}
public struct ModelRouting: Codable, Equatable, Sendable {
    public var assistant: UUID?; public var protocolBuilder: UUID?; public var scheduling: UUID?; public var report: UUID?
    public init() {}
}
public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var role: String; public var content: String; public var artifactIDs: [UUID] = []
    public var createdAt = Date()
    public init(role: String, content: String, artifactIDs: [UUID] = []) { self.role = role; self.content = content; self.artifactIDs = artifactIDs }
}
public struct ChatSession: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title = "新的实验任务"; public var modelID: UUID?
    public var messages: [ChatMessage] = []; public var updatedAt = Date()
    public init(modelID: UUID? = nil) { self.modelID = modelID }
}
public struct RunEvent: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var date = Date()
    public var modelProfile: ModelProfile?
    public init(_ title: String, model: ModelProfile? = nil) { self.title = title; modelProfile = model }
}
public enum RunStatus: String, Codable, Sendable { case running, completed, failed, cancelled, interrupted }
public struct AssistantRun: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var sessionID: UUID; public var input: String
    public var modelID: UUID?; public var modelName: String; public var status: RunStatus = .running
    public var events: [RunEvent] = []; public var artifactIDs: [UUID] = []; public var error: String?
    public var createdAt = Date(); public var inputTokens = 0; public var outputTokens = 0
    public var modelProfile: ModelProfile?
    public var endpoint: String?
    public var intent: IntentDecision?
    public init(sessionID: UUID, input: String, modelID: UUID?, modelName: String) {
        self.sessionID = sessionID; self.input = input; self.modelID = modelID; self.modelName = modelName
    }
}
public struct BusyInterval: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var start: Date; public var end: Date
    public var instrumentID: UUID?
    public init(title: String, start: Date, end: Date, instrumentID: UUID? = nil) { self.title = title; self.start = start; self.end = end; self.instrumentID = instrumentID }
}
public struct SchedulePreferences: Codable, Equatable, Sendable {
    public var workStartMinute = 540; public var workEndMinute = 1080
    public var allowOvernight = true; public var breakEveryMinutes = 240; public var breakMinutes = 15
    public init() {}
    public func validated() throws {
        guard (0..<1440).contains(workStartMinute), (1...1440).contains(workEndMinute), workStartMinute < workEndMinute,
              (30...1440).contains(breakEveryMinutes), (0...120).contains(breakMinutes) else { throw WorkspaceError.invalid("请检查工作时段和休息设置。") }
    }
}
public struct ScheduleCandidate: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var procedureID: UUID; public var versionID: UUID; public var sourceRevision: Int
    public var experiment: Experiment; public var steps: [PlannedStep]; public var preferences: SchedulePreferences
    public var label: String; public var rationale: String
    public var objective: ScheduleObjective?
    public var notBefore: Date?
    public var latestFinish: Date?
    public var additionalBusyIntervals: [BusyInterval]?
    public init(procedure: Procedure, experiment: Experiment, steps: [PlannedStep], preferences: SchedulePreferences, label: String, rationale: String) {
        procedureID = procedure.id; versionID = procedure.currentVersion.id; sourceRevision = procedure.revision
        self.experiment = experiment; self.steps = steps; self.preferences = preferences; self.label = label; self.rationale = rationale
    }
}
public enum ArtifactKind: String, Codable, Sendable { case protocolDraft, schedule, report, paperDraft }
public struct AssistantArtifact: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var kind: ArtifactKind; public var title: String
    public var procedure: Procedure?; public var expectedRevision: Int?
    public var candidates: [ScheduleCandidate] = []; public var text = ""
    public var appliedID: UUID?; public var createdAt = Date()
    public var paper: LiteratureReading?
    public init(kind: ArtifactKind, title: String) { self.kind = kind; self.title = title }
}
