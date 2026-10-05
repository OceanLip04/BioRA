import Foundation

public enum ScienceQuestionStatus: String, Codable, CaseIterable, Sendable {
    case open, investigating, resolved
    public var title: String { switch self { case .open: "待探索"; case .investigating: "研究中"; case .resolved: "已解决" } }
    public func title(_ language: AppLanguage) -> String {
        guard language == .english else { return title }
        return switch self { case .open: "Open"; case .investigating: "Investigating"; case .resolved: "Resolved" }
    }
}

public enum ScienceClaimKind: String, Codable, CaseIterable, Sendable {
    case assertion, hypothesis, observation, conclusion
    public var title: String { switch self { case .assertion: "论断"; case .hypothesis: "假设"; case .observation: "观察"; case .conclusion: "结论" } }
    public func title(_ language: AppLanguage) -> String {
        guard language == .english else { return title }
        return switch self { case .assertion: "Claim"; case .hypothesis: "Hypothesis"; case .observation: "Observation"; case .conclusion: "Conclusion" }
    }
}

public struct ScienceClaim: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ScienceClaimKind
    public var text: String
    /// A user's own qualitative assessment, not a calibrated statistical probability.
    public var confidence: Double
    public var sourceNote: String
    public var experimentIDs: [UUID]
    public init(id: UUID = UUID(), kind: ScienceClaimKind, text: String, confidence: Double = 0.5, sourceNote: String = "", experimentIDs: [UUID] = []) {
        self.id = id; self.kind = kind; self.text = text; self.confidence = confidence; self.sourceNote = sourceNote; self.experimentIDs = experimentIDs
    }
}

public enum ScienceRelationKind: String, Codable, CaseIterable, Sendable {
    case supports, contradicts
    public var title: String { self == .supports ? "支持" : "反驳" }
    public func title(_ language: AppLanguage) -> String { language == .english ? (self == .supports ? "Supports" : "Contradicts") : title }
}

public struct ScienceRelation: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var fromClaimID: UUID
    public var toClaimID: UUID
    public var kind: ScienceRelationKind
    public var explanation: String
    public var limitations: String
    public init(id: UUID = UUID(), fromClaimID: UUID, toClaimID: UUID, kind: ScienceRelationKind, explanation: String = "", limitations: String = "") {
        self.id = id; self.fromClaimID = fromClaimID; self.toClaimID = toClaimID; self.kind = kind
        self.explanation = explanation; self.limitations = limitations
    }
    enum CodingKeys: String, CodingKey { case id, fromClaimID, toClaimID, kind, explanation, limitations }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); fromClaimID = try c.decode(UUID.self, forKey: .fromClaimID)
        toClaimID = try c.decode(UUID.self, forKey: .toClaimID); kind = try c.decode(ScienceRelationKind.self, forKey: .kind)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        limitations = try c.decodeIfPresent(String.self, forKey: .limitations) ?? ""
    }
}

public enum AtomicExperimentStatus: String, Codable, CaseIterable, Sendable {
    case planned, recorded
    public var title: String { self == .planned ? "待记录" : "已记录结果" }
    public func title(_ language: AppLanguage) -> String { language == .english ? (self == .planned ? "Planned" : "Recorded Result") : title }
}

/// One independently interpretable experimental test, not a Protocol operation or a scheduled event.
public struct AtomicExperiment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var method: String
    public var status: AtomicExperimentStatus
    public var observedResult: String
    public var sourceNote: String
    public var experimentID: UUID?
    public var recordedAt: Date
    public init(id: UUID = UUID(), title: String, method: String = "", status: AtomicExperimentStatus = .planned,
                observedResult: String = "", sourceNote: String = "", experimentID: UUID? = nil, recordedAt: Date = Date()) {
        self.id = id; self.title = title; self.method = method; self.status = status
        self.observedResult = observedResult; self.sourceNote = sourceNote; self.experimentID = experimentID; self.recordedAt = recordedAt
    }
}

public struct AtomicEvidenceLink: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var atomicExperimentID: UUID
    public var claimID: UUID
    public var kind: ScienceRelationKind
    /// The warrant belongs to this link: one experiment can inform two results differently.
    public var explanation: String
    public var limitations: String
    public init(id: UUID = UUID(), atomicExperimentID: UUID, claimID: UUID, kind: ScienceRelationKind, explanation: String = "", limitations: String = "") {
        self.id = id; self.atomicExperimentID = atomicExperimentID; self.claimID = claimID; self.kind = kind
        self.explanation = explanation; self.limitations = limitations
    }
    enum CodingKeys: String, CodingKey { case id, atomicExperimentID, claimID, kind, explanation, limitations }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); atomicExperimentID = try c.decode(UUID.self, forKey: .atomicExperimentID)
        claimID = try c.decode(UUID.self, forKey: .claimID); kind = try c.decode(ScienceRelationKind.self, forKey: .kind)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        limitations = try c.decodeIfPresent(String.self, forKey: .limitations) ?? ""
    }
}

public enum ScienceNarrativeOrigin: String, Codable, CaseIterable, Sendable { case reported, inferred }
public enum ScienceMainlineRole: String, Codable, CaseIterable, Sendable { case result, discussion }

/// Reading order and the reason for the next research question, never an evidence edge.
public struct ScienceMainlineStep: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { claimID }
    public var claimID: UUID
    public var question: String
    public var motivation: String
    public var origin: ScienceNarrativeOrigin
    public var role: ScienceMainlineRole
    public init(claimID: UUID, question: String = "", motivation: String = "", origin: ScienceNarrativeOrigin = .reported, role: ScienceMainlineRole = .result) {
        self.claimID = claimID; self.question = question; self.motivation = motivation; self.origin = origin
        self.role = role
    }
    enum CodingKeys: String, CodingKey { case claimID, question, motivation, origin, role }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claimID = try c.decode(UUID.self, forKey: .claimID); question = try c.decode(String.self, forKey: .question)
        motivation = try c.decode(String.self, forKey: .motivation); origin = try c.decode(ScienceNarrativeOrigin.self, forKey: .origin)
        role = try c.decodeIfPresent(ScienceMainlineRole.self, forKey: .role) ?? .result
    }
}

public struct ScienceGraphPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct ScientificQuestion: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var status: ScienceQuestionStatus
    public var claims: [ScienceClaim]
    public var relations: [ScienceRelation]
    public var atomicExperiments: [AtomicExperiment]
    public var evidenceLinks: [AtomicEvidenceLink]
    public var mainline: [ScienceMainlineStep]
    public var graphPositions: [String: ScienceGraphPoint]
    public var createdAt: Date
    public var updatedAt: Date
    public var revision: Int
    public init(id: UUID = UUID(), title: String, detail: String = "", status: ScienceQuestionStatus = .open,
                claims: [ScienceClaim] = [], relations: [ScienceRelation] = [], atomicExperiments: [AtomicExperiment] = [],
                evidenceLinks: [AtomicEvidenceLink] = [], graphPositions: [String: ScienceGraphPoint] = [:],
                createdAt: Date = Date(), updatedAt: Date = Date(), revision: Int = 0, mainline: [ScienceMainlineStep] = []) {
        self.id = id; self.title = title; self.detail = detail; self.status = status; self.claims = claims; self.relations = relations
        self.atomicExperiments = atomicExperiments; self.evidenceLinks = evidenceLinks; self.graphPositions = graphPositions
        self.mainline = mainline
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.revision = revision
    }
    enum CodingKeys: String, CodingKey {
        case id, title, detail, status, claims, relations, atomicExperiments, evidenceLinks, mainline, graphPositions, createdAt, updatedAt, revision
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        detail = try c.decode(String.self, forKey: .detail); status = try c.decode(ScienceQuestionStatus.self, forKey: .status)
        claims = try c.decode([ScienceClaim].self, forKey: .claims); relations = try c.decode([ScienceRelation].self, forKey: .relations)
        atomicExperiments = try c.decodeIfPresent([AtomicExperiment].self, forKey: .atomicExperiments) ?? []
        evidenceLinks = try c.decodeIfPresent([AtomicEvidenceLink].self, forKey: .evidenceLinks) ?? []
        mainline = try c.decodeIfPresent([ScienceMainlineStep].self, forKey: .mainline) ?? []
        graphPositions = try c.decodeIfPresent([String: ScienceGraphPoint].self, forKey: .graphPositions) ?? [:]
        createdAt = try c.decode(Date.self, forKey: .createdAt); updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        revision = try c.decode(Int.self, forKey: .revision)
    }
    public func validated(experimentIDs: Set<UUID>) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 300,
              detail.count <= 20_000, revision >= 0 else { throw WorkspaceError.invalid("科学问题的标题或描述无效。") }
        let claimIDs = claims.map(\.id)
        let atomIDs = atomicExperiments.map(\.id)
        guard claims.count <= 300, Set(claimIDs).count == claimIDs.count, relations.count <= 1000,
              Set(relations.map(\.id)).count == relations.count, atomicExperiments.count <= 500,
              Set(atomIDs).count == atomIDs.count, evidenceLinks.count <= 2000,
              Set(evidenceLinks.map(\.id)).count == evidenceLinks.count,
              Set(claimIDs).isDisjoint(with: Set(atomIDs)), !claimIDs.contains(id), !atomIDs.contains(id) else {
            throw WorkspaceError.invalid("科学问题含重复或过多的图谱节点与关系。")
        }
        for claim in claims {
            guard !claim.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, claim.text.count <= 10_000,
                  claim.sourceNote.count <= 10_000, claim.confidence.isFinite, (0...1).contains(claim.confidence),
                  Set(claim.experimentIDs).count == claim.experimentIDs.count,
                  Set(claim.experimentIDs).isSubset(of: experimentIDs) else { throw WorkspaceError.invalid("论断内容、自评确信度或实验引用无效。") }
        }
        let validIDs = Set(claimIDs)
        guard mainline.count <= 60, Set(mainline.map(\.claimID)).count == mainline.count,
              mainline.allSatisfy({ validIDs.contains($0.claimID) && $0.question.count <= 3000 && $0.motivation.count <= 5000 }),
              mainline.filter({ $0.role == .discussion }).count <= 1,
              mainline.filter({ $0.role == .discussion }).allSatisfy({ step in claims.contains { $0.id == step.claimID && $0.kind == .conclusion } }),
              !mainline.contains(where: { $0.role == .discussion }) || mainline.last?.role == .discussion else {
            throw WorkspaceError.invalid("研究主线的引用或长度无效；Discussion 必须使用结论节点，且唯一置于末尾。")
        }
        for relation in relations {
            guard relation.fromClaimID != relation.toClaimID,
                  validIDs.contains(relation.fromClaimID), validIDs.contains(relation.toClaimID),
                  relation.explanation.count <= 10_000, relation.limitations.count <= 10_000 else { throw WorkspaceError.invalid("论断关系引用或解释无效。") }
        }
        let relationKeys = relations.map { "\($0.fromClaimID)-\($0.toClaimID)" }
        guard Set(relationKeys).count == relationKeys.count else { throw WorkspaceError.invalid("存在重复的论断关系。") }
        var visitState: [UUID: Int] = [:]
        let outgoing = Dictionary(grouping: relations, by: \.fromClaimID)
        func visit(_ node: UUID) throws {
            if visitState[node] == 1 { throw WorkspaceError.invalid("论断关系形成循环；请保持从证据到结论的清晰方向。") }
            if visitState[node] == 2 { return }
            visitState[node] = 1
            for edge in outgoing[node] ?? [] { try visit(edge.toClaimID) }
            visitState[node] = 2
        }
        for node in claimIDs { try visit(node) }
        let validAtomIDs = Set(atomIDs)
        let mainlineIDs = Set(mainline.map(\.claimID))
        for atom in atomicExperiments {
            guard !atom.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, atom.title.count <= 300,
                  atom.method.count <= 10_000, atom.observedResult.count <= 20_000, atom.sourceNote.count <= 10_000,
                  atom.experimentID.map({ experimentIDs.contains($0) }) ?? true else {
                throw WorkspaceError.invalid("原子实验内容或实验引用无效。")
            }
            if atom.status == .recorded {
                guard !atom.observedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      atom.experimentID != nil || !atom.sourceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw WorkspaceError.invalid("已记录的原子实验必须有观察结果，并关联本机实验或写明可追溯出处。")
                }
            } else if !atom.observedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw WorkspaceError.invalid("待记录的原子实验不能包含已观察结果；请改为已记录状态。")
            }
        }
        for edge in evidenceLinks {
            guard validAtomIDs.contains(edge.atomicExperimentID), validIDs.contains(edge.claimID),
                  edge.explanation.count <= 10_000, edge.limitations.count <= 10_000,
                  atomicExperiments.first(where: { $0.id == edge.atomicExperimentID })?.status == .recorded else {
                throw WorkspaceError.invalid("证据连线只能从已记录结果的原子实验指向存在的论断。")
            }
            guard !mainlineIDs.contains(edge.claimID) else {
                throw WorkspaceError.invalid("原子实验不能直接连接主线结论；请先连接下层结论，再逐级支持主线。")
            }
        }
        let evidenceKeys = evidenceLinks.map { "\($0.atomicExperimentID)-\($0.claimID)" }
        guard Set(evidenceKeys).count == evidenceKeys.count else { throw WorkspaceError.invalid("存在重复的原子实验证据连线。") }
        let validNodeKeys = Set(([id] + claimIDs + atomIDs).map(\.uuidString))
        guard graphPositions.count <= validNodeKeys.count,
              graphPositions.allSatisfy({ validNodeKeys.contains($0.key) && $0.value.x.isFinite && $0.value.y.isFinite &&
                  (0...50_000).contains($0.value.x) && (0...50_000).contains($0.value.y) }) else {
            throw WorkspaceError.invalid("图谱节点位置无效。")
        }
    }

    public mutating func removeClaimFromMainline(_ id: UUID) {
        guard let index = mainline.firstIndex(where: { $0.claimID == id }) else { return }
        mainline.remove(at: index)
        // The old transition refers to a now-removed predecessor. Do not invent a replacement.
        if mainline.indices.contains(index) { mainline[index].motivation = "" }
    }
}
