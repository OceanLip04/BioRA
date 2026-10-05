import Foundation

/// A model proposal only. It has no authority to write workspace records.
public struct SciencePDFImport: Codable, Sendable {
    public struct Claim: Codable, Sendable {
        public var key: String
        public var kind: ScienceClaimKind
        public var text: String
        public var sourcePage: Int?
        enum CodingKeys: String, CodingKey { case key, kind, text; case sourcePage = "source_page" }
    }
    public struct AtomicTest: Codable, Sendable {
        public var key: String
        public var title: String
        public var method: String
        public var status: AtomicExperimentStatus
        public var observedResult: String
        public var sourcePage: Int?
        enum CodingKeys: String, CodingKey {
            case key, title, method, status
            case observedResult = "observed_result", sourcePage = "source_page"
        }
    }
    public struct EvidenceLink: Codable, Sendable {
        public var atomKey: String
        public var claimKey: String
        public var kind: ScienceRelationKind
        public var explanation: String?
        public var limitations: String?
        enum CodingKeys: String, CodingKey { case kind, explanation, limitations; case atomKey = "atom_key", claimKey = "claim_key" }
    }
    public struct ClaimLink: Codable, Sendable {
        public var fromKey: String
        public var toKey: String
        public var kind: ScienceRelationKind
        public var explanation: String?
        public var limitations: String?
        enum CodingKeys: String, CodingKey { case kind, explanation, limitations; case fromKey = "from_key", toKey = "to_key" }
    }
    public struct MainlineStep: Codable, Sendable {
        public var claimKey: String
        public var question: String
        public var motivation: String
        public var origin: ScienceNarrativeOrigin
        public var role: ScienceMainlineRole?
        enum CodingKeys: String, CodingKey { case question, motivation, origin, role; case claimKey = "claim_key" }
    }

    public var title: String
    public var detail: String
    public var claims: [Claim]
    public var atomicExperiments: [AtomicTest]
    public var evidenceLinks: [EvidenceLink]
    public var claimLinks: [ClaimLink]
    public var mainline: [MainlineStep]?
    public var analysis: PaperAnalysis?
    enum CodingKeys: String, CodingKey {
        case title, detail, claims, analysis, mainline
        case atomicExperiments = "atomic_experiments", evidenceLinks = "evidence_links", claimLinks = "claim_links"
    }

    /// The model must use the new full contract. Optional decoding remains for saved legacy drafts only.
    public static func validateShape(_ json: JSONValue, requireDiscussion: Bool = false) throws {
        func object(_ value: JSONValue, keys: Set<String>) throws {
            guard let fields = value.object, Set(fields.keys) == keys else {
                throw WorkspaceError.invalid("Graph JSON must contain exactly the mainline contract fields.")
            }
        }
        try object(json, keys: ["title", "detail", "claims", "atomic_experiments", "evidence_links", "claim_links", "mainline"])
        let arrays: [(String, Set<String>)] = [
            ("claims", ["key", "kind", "text", "source_page"]),
            ("atomic_experiments", ["key", "title", "method", "status", "observed_result", "source_page"]),
            ("evidence_links", ["atom_key", "claim_key", "kind", "explanation", "limitations"]),
            ("claim_links", ["from_key", "to_key", "kind", "explanation", "limitations"]),
            ("mainline", ["claim_key", "question", "motivation", "origin"])
        ]
        for (name, keys) in arrays {
            guard let values = json[name].array else { throw WorkspaceError.invalid("Missing graph array: \(name).") }
            for value in values {
                if name == "mainline", !requireDiscussion, value.object?["role"] != nil {
                    try object(value, keys: keys.union(["role"]))
                } else { try object(value, keys: name == "mainline" && requireDiscussion ? keys.union(["role"]) : keys) }
            }
        }
        if requireDiscussion, !(json["claims"].array ?? []).isEmpty {
            guard let steps = json["mainline"].array, !steps.isEmpty,
                  steps.last?["role"].string == "discussion",
                  steps.filter({ $0["role"].string == "discussion" }).count == 1 else {
                throw WorkspaceError.invalid("The paper mainline must end with exactly one Discussion synthesis.")
            }
        }
    }

    /// Enforced for newly generated papers, not retroactively for saved legacy graphs.
    /// Evidence flows toward a mainline root; presentation order is not an edge.
    public func validateMainlineCoverage(language: AppLanguage) throws {
        let steps = mainline ?? []
        let roots = Set(steps.map(\.claimKey))
        let resultRoots = Set(steps.filter { $0.role != .discussion }.map(\.claimKey))
        func ancestors(of targets: Set<String>) -> Set<String> {
            var reached = targets, queue = Array(targets), cursor = 0
            let incoming = Dictionary(grouping: claimLinks, by: \.toKey)
            while cursor < queue.count {
                let target = queue[cursor]; cursor += 1
                for link in incoming[target] ?? [] where reached.insert(link.fromKey).inserted {
                    queue.append(link.fromKey)
                }
            }
            return reached
        }
        let connected = ancestors(of: roots), resultConnected = ancestors(of: resultRoots)
        let orphanClaims = claims.filter { !connected.contains($0.key) }.map(\.key)
        let orphanTests = atomicExperiments.filter { atom in
            atom.status == .recorded && !evidenceLinks.contains { $0.atomKey == atom.key && resultConnected.contains($0.claimKey) }
        }.map(\.key)
        guard orphanClaims.isEmpty, orphanTests.isEmpty else {
            let claimKeys = orphanClaims.joined(separator: ", "), testKeys = orphanTests.joined(separator: ", ")
            throw WorkspaceError.invalid(language == .english
                ? "Mainline coverage failed. Unconnected claims: [\(claimKeys)]; reported experiments without a directed path to a mainline result: [\(testKeys)]. Organize the missing result tree and give source-grounded warrants; do not delete results, reverse arrows, invent links, or use Discussion as a shortcut."
                : "主线覆盖校验失败。未关联论断：[\(claimKeys)]；没有经结论树指向主线结果的已记录实验：[\(testKeys)]。请补全相应结果树及原文依据，不得删除结果、反转箭头、编造连线或用 Discussion 绕过结果树。")
        }
        if !(analysis?.findings.isEmpty ?? true), resultRoots.isEmpty || claims.isEmpty {
            throw WorkspaceError.invalid(language == .english
                ? "The reading contains findings but the graph has no mainline results. Cover those findings; an empty graph or Discussion-only graph is not a complete analysis."
                : "详细阅读已有研究发现，图谱却没有主线结果。必须覆盖这些发现，不能返回空图谱或仅有 Discussion 的图谱。")
        }
    }

    public func materialize(fileName: String, pageCount: Int, fingerprint: String, language: AppLanguage) throws -> ScientificQuestion {
        try analysis?.validated(pageCount: pageCount, language: language)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 300,
              detail.count <= 20_000, (1...500).contains(pageCount), claims.count <= 60,
              atomicExperiments.count <= 100, evidenceLinks.count <= 300, claimLinks.count <= 300 else {
            throw WorkspaceError.invalid(language == .english ? "The PDF graph is too large or incomplete." : "PDF 图谱过大或缺少内容。")
        }
        func validKey(_ key: String) -> Bool {
            !key.isEmpty && key.count <= 40 && key.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
            }
        }
        let keys = claims.map(\.key) + atomicExperiments.map(\.key)
        guard keys.allSatisfy(validKey), Set(keys).count == keys.count else {
            throw WorkspaceError.invalid(language == .english ? "PDF graph node keys must be unique ASCII identifiers." : "PDF 图谱节点标识必须是唯一的 ASCII 字符串。")
        }
        let source = language == .english
            ? "AI-extracted from PDF “\(fileName)” (SHA-256 prefix \(fingerprint)); page citations need human verification. This is literature evidence, not a record of your own experiment."
            : "AI 从 PDF《\(fileName)》提取（SHA-256 前缀 \(fingerprint)）；页码需人工核对。这是文献证据，不是本人实验记录。"
        let confidenceNotice = language == .english
            ? "Imported claims start at a neutral 50% self-rating placeholder, not an AI confidence estimate. Review and edit each rating."
            : "导入论断的 50% 自评仅为中性占位值，不是模型置信度；请逐条核对并修改。"
        func note(_ page: Int?) throws -> String {
            if let page {
                guard (1...pageCount).contains(page) else { throw WorkspaceError.invalid(language == .english ? "A cited PDF page is outside the document." : "引用页码超出 PDF 范围。") }
                return source + (language == .english ? " Page \(page)." : " 第 \(page) 页。")
            }
            return source + (language == .english ? " No page citation was supplied." : " 模型未提供页码。")
        }
        var claimIDs: [String: UUID] = [:], atomIDs: [String: UUID] = [:]
        let builtClaims = try claims.map { item -> ScienceClaim in
            try language.requiresEnglish(item.text)
            guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.invalid(language == .english ? "A PDF claim is empty." : "PDF 论断为空。") }
            let id = UUID(); claimIDs[item.key] = id
            return ScienceClaim(id: id, kind: item.kind, text: item.text, confidence: 0.5, sourceNote: try note(item.sourcePage))
        }
        let builtAtoms = try atomicExperiments.map { item -> AtomicExperiment in
            try language.requiresEnglish(item.title); try language.requiresEnglish(item.method); try language.requiresEnglish(item.observedResult)
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.invalid(language == .english ? "An atomic test has no title." : "原子实验缺少标题。") }
            if item.status == .recorded && (item.sourcePage == nil || item.method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.observedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                throw WorkspaceError.invalid(language == .english ? "Every reported result needs a method, observation, and verifiable PDF page." : "文献中的已记录结果必须同时有方法、观察结果和可核对的页码。")
            }
            if item.status == .planned && !item.observedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw WorkspaceError.invalid(language == .english ? "A planned test cannot contain an observed result." : "计划中的检验不能包含观察结果。")
            }
            let id = UUID(); atomIDs[item.key] = id
            return AtomicExperiment(id: id, title: item.title, method: item.method, status: item.status,
                observedResult: item.observedResult, sourceNote: try note(item.sourcePage))
        }
        let builtEvidence = try evidenceLinks.map { item -> AtomicEvidenceLink in
            guard let atomID = atomIDs[item.atomKey], let claimID = claimIDs[item.claimKey] else {
                throw WorkspaceError.invalid(language == .english ? "A PDF evidence link points to a missing node." : "PDF 证据连线指向不存在的节点。")
            }
            try language.requiresEnglish(item.explanation); try language.requiresEnglish(item.limitations)
            return AtomicEvidenceLink(atomicExperimentID: atomID, claimID: claimID, kind: item.kind,
                explanation: item.explanation ?? "", limitations: item.limitations ?? "")
        }
        let builtRelations = try claimLinks.map { item -> ScienceRelation in
            guard let fromID = claimIDs[item.fromKey], let toID = claimIDs[item.toKey] else {
                throw WorkspaceError.invalid(language == .english ? "A PDF claim link points to a missing node." : "PDF 论断连线指向不存在的节点。")
            }
            try language.requiresEnglish(item.explanation); try language.requiresEnglish(item.limitations)
            return ScienceRelation(fromClaimID: fromID, toClaimID: toID, kind: item.kind,
                explanation: item.explanation ?? "", limitations: item.limitations ?? "")
        }
        let builtMainline = try (mainline ?? []).map { item -> ScienceMainlineStep in
            guard let id = claimIDs[item.claimKey], !item.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.motivation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.origin != .reported || claims.first(where: { $0.key == item.claimKey })?.sourcePage != nil else {
                throw WorkspaceError.invalid("Each mainline result needs a real claim, research question, transition reason, and a citation for reported logic.")
            }
            try language.requiresEnglish(item.question); try language.requiresEnglish(item.motivation)
            return ScienceMainlineStep(claimID: id, question: item.question, motivation: item.motivation, origin: item.origin, role: item.role ?? .result)
        }
        if mainline != nil {
            guard claims.isEmpty || !builtMainline.isEmpty,
                  evidenceLinks.allSatisfy({ !($0.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  claimLinks.allSatisfy({ !($0.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw WorkspaceError.invalid("A new graph needs an explicit result mainline and an explanation for every evidence link.")
            }
        }
        try language.requiresEnglish(title); try language.requiresEnglish(detail)
        let question = ScientificQuestion(title: title, detail: detail + "\n\n" + source + "\n" + confidenceNotice,
            claims: builtClaims, relations: builtRelations, atomicExperiments: builtAtoms, evidenceLinks: builtEvidence, mainline: builtMainline)
        try question.validated(experimentIDs: [])
        return question
    }
}
