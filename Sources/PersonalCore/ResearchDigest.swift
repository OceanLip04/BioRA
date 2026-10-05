import Foundation

/// Opt-in, download-only central research feed. Credentials never belong to Workspace.
public struct LaboratoryConfiguration: Codable, Equatable, Sendable {
    public var enabled = false
    public var automatic = true
    public var baseURL = ""
    public var feed = "default"
    public var timezone = "Asia/Shanghai"
    public init() {}
    public func validated() throws {
        guard TimeZone(identifier: timezone) != nil, Self.identifier(feed), baseURL.count <= 2048 else {
            throw WorkspaceError.invalid("Invalid laboratory feed or time zone. / 实验室频道或时区无效。")
        }
        if !baseURL.isEmpty { _ = try serverURL() }
    }
    public func serverURL() throws -> URL {
        guard let parts = URLComponents(string: baseURL), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, let url = parts.url,
              !parts.path.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }),
              !parts.percentEncodedPath.lowercased().contains("%2f"),
              !parts.percentEncodedPath.lowercased().contains("%2e") else {
            throw WorkspaceError.invalid("Use an HTTPS server base URL without credentials, query or fragment. / 请填写 HTTPS 服务器根地址，不含凭据、查询或锚点。")
        }
        return url
    }
    public static func identifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 || $0 == 46
        }
    }
    public func day(_ date: Date) -> String {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian); format.timeZone = TimeZone(identifier: timezone)
        format.dateFormat = "yyyy-MM-dd"; return format.string(from: date)
    }
    public static func validDay(_ value: String) -> Bool {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian); format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        guard value.count == 10, let date = format.date(from: value) else { return false }
        return format.string(from: date) == value
    }
}

public struct ResearchDigestSource: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var page_count: Int
    public func validated() throws {
        guard LaboratoryConfiguration.identifier(id), !title.isEmpty, title.count <= 1000,
              (1...500).contains(page_count), url.count <= 2048,
              let parts = URLComponents(string: url), parts.scheme == "https", parts.host != nil,
              parts.user == nil, parts.password == nil, parts.url != nil else {
            throw WorkspaceError.invalid("Invalid research source. / 研究来源无效。")
        }
    }
}

public struct ResearchDigestCitation: Codable, Equatable, Sendable {
    public var node_key: String
    public var source_id: String
    public var page: Int
}

/// Wire v1: stable ASCII keys, not local database UUIDs; graph uses the established mainline contract.
public struct DailyResearchDigest: Codable, Equatable, Sendable {
    public var schema_version: Int
    public var id: String
    public var date: String
    public var timezone: String
    public var language: String
    public var feed: String
    public var revision: Int
    public var title: String
    public var summary: String
    public var published_at: String
    public var sources: [ResearchDigestSource]
    public var citations: [ResearchDigestCitation]
    public var graph: JSONValue

    public static let maximumBytes = 2_000_000
    private static func validTimestamp(_ value: String) -> Bool {
        guard value.count <= 40 else { return false }
        let format = ISO8601DateFormatter()
        if format.date(from: value) != nil { return true }
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: value) != nil
    }
    public static func decode(_ data: Data) throws -> DailyResearchDigest {
        guard data.count <= maximumBytes else { throw WorkspaceError.invalid("Research digest exceeds 2 MB. / 研究摘要超过 2 MB。") }
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        func fields(_ value: JSONValue, _ keys: Set<String>) throws {
            guard let object = value.object, Set(object.keys) == keys else { throw WorkspaceError.invalid("Unknown or missing digest fields. / 摘要字段缺失或未知。") }
        }
        try fields(json, ["schema_version", "id", "date", "timezone", "language", "feed", "revision", "title", "summary", "published_at", "sources", "citations", "graph"])
        guard let sources = json["sources"].array, let citations = json["citations"].array else { throw WorkspaceError.invalid("Digest sources/citations must be arrays.") }
        for source in sources { try fields(source, ["id", "title", "url", "page_count"]) }
        for citation in citations { try fields(citation, ["node_key", "source_id", "page"]) }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public func materialize(language appLanguage: AppLanguage) throws -> ScientificQuestion {
        let expectedLanguage = appLanguage == .english ? "en" : "zh-Hans"
        guard schema_version == 1, LaboratoryConfiguration.identifier(id), LaboratoryConfiguration.identifier(feed),
              LaboratoryConfiguration.validDay(date), TimeZone(identifier: timezone) != nil,
              language == expectedLanguage, revision > 0, !title.isEmpty, title.count <= 300,
              summary.count <= 10_000, (1...50).contains(sources.count), citations.count <= 1000,
              Self.validTimestamp(published_at),
              Set(sources.map(\.id)).count == sources.count else {
            throw WorkspaceError.invalid("Invalid digest metadata/version/language. / 摘要元数据、版本或语言无效。")
        }
        try appLanguage.requiresEnglish(title); try appLanguage.requiresEnglish(summary)
        for source in sources { try source.validated() }
        try SciencePDFImport.validateShape(graph, requireDiscussion: true)
        // Legacy PDF proposals allow absent optional prose/role; the server v1 wire format does not.
        for field in ["evidence_links", "claim_links"] {
            for edge in graph[field].array ?? [] {
                guard edge["explanation"].string != nil, edge["limitations"].string != nil else {
                    throw WorkspaceError.invalid("Digest edge prose must be strings, not null. / 摘要连边说明须为字符串，不能为 null。")
                }
            }
        }
        guard (graph["mainline"].array ?? []).allSatisfy({ ["result", "discussion"].contains($0["role"].string ?? "") }) else {
            throw WorkspaceError.invalid("Every digest mainline role must be explicit. / 摘要主线角色必须明确。")
        }
        let proposal = try JSONDecoder().decode(SciencePDFImport.self, from: JSONEncoder().encode(graph))
        guard !(proposal.mainline ?? []).filter({ $0.role == .result }).isEmpty,
              !proposal.atomicExperiments.isEmpty,
              !(proposal.mainline ?? []).contains(where: { step in
                  proposal.claims.first(where: { $0.key == step.claimKey })?.kind != .conclusion
              }) else { throw WorkspaceError.invalid("A digest needs conclusion mainline results, evidence trees and Discussion. / 摘要需有结论主线、实验论证树及 Discussion。") }
        let nodeKeys = Set(proposal.claims.map(\.key) + proposal.atomicExperiments.map(\.key))
        let sourceIndex = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        var citationKeys = Set<String>()
        for citation in citations {
            guard nodeKeys.contains(citation.node_key), let source = sourceIndex[citation.source_id],
                  (1...source.page_count).contains(citation.page),
                  citationKeys.insert("\(citation.node_key)|\(citation.source_id)|\(citation.page)").inserted else {
                throw WorkspaceError.invalid("Invalid/duplicate node citation. / 节点来源引用无效或重复。")
            }
        }
        let citationIndex = Dictionary(grouping: citations, by: \.node_key)
        for (key, page) in proposal.claims.map({ ($0.key, $0.sourcePage) }) + proposal.atomicExperiments.map({ ($0.key, $0.sourcePage) }) {
            guard let referenced = citationIndex[key], !referenced.isEmpty,
                  page.map({ p in referenced.contains { $0.page == p } }) ?? true else {
                throw WorkspaceError.invalid("Each node needs a traceable source; source_page must match a citation. / 每个节点需可追溯来源，source_page 必须与引用一致。")
            }
        }
        try proposal.validateMainlineCoverage(language: appLanguage)
        var question = try proposal.materialize(fileName: title, pageCount: sources.map(\.page_count).max()!, fingerprint: id, language: appLanguage)
        func sourceNote(_ key: String) -> String {
            (citationIndex[key] ?? []).map { citation in
                let source = sourceIndex[citation.source_id]!
                return "\(source.title) · \(appLanguage == .english ? "PDF page" : "PDF 页码") \(citation.page)\n\(source.url)"
            }.joined(separator: "\n\n")
        }
        question.detail = proposal.detail + "\n\n" + (appLanguage == .english
            ? "Central-server literature summary, not your own experiment. Verify sources and warrants. 50% claim ratings are neutral placeholders, not calibrated confidence."
            : "中央服务器提供的文献摘要，不是本人实验记录。请核对来源与推理依据；50% 自评是中性占位，不是统计置信度。")
        for index in question.claims.indices { question.claims[index].sourceNote = sourceNote(proposal.claims[index].key) }
        for index in question.atomicExperiments.indices { question.atomicExperiments[index].sourceNote = sourceNote(proposal.atomicExperiments[index].key) }
        try question.validated(experimentIDs: [])
        let index = ScienceArgumentIndex(question: question)
        guard question.mainline.filter({ $0.role == .result }).allSatisfy({ !index.evidence(for: $0.claimID).isEmpty }) else {
            throw WorkspaceError.invalid("Every mainline result needs its own experimental evidence tree. / 每个主线结果都需要自己的实验论证树。")
        }
        return question
    }
}

public struct CachedResearchDigest: Codable, Equatable, Identifiable, Sendable {
    public var id: String { key }
    public var key: String
    public var digest: DailyResearchDigest
    public var graph: ScientificQuestion
    public var etag: String?
    public var checkedAt: Date
    public init(key: String, digest: DailyResearchDigest, graph: ScientificQuestion, etag: String?, checkedAt: Date) {
        self.key = key; self.digest = digest; self.graph = graph; self.etag = etag; self.checkedAt = checkedAt
    }
    public func validated() throws {
        guard key.count == 64, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              etag.map({ $0.utf8.count <= 512 && !$0.contains("\r") && !$0.contains("\n") }) ?? true else {
            throw WorkspaceError.invalid("Invalid digest cache identity/ETag.")
        }
        let language: AppLanguage = digest.language == "en" ? .english : .chinese
        _ = try digest.materialize(language: language)
        try graph.validated(experimentIDs: [])
    }
}
