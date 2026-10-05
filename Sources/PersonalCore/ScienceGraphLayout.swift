import Foundation

public enum ScienceGraphNodeKind: Sendable, Equatable {
    case question, claim(ScienceClaimKind), atomicExperiment(AtomicExperimentStatus)
}

public struct ScienceGraphNode: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var kind: ScienceGraphNodeKind
    public var title: String
    public var subtitle: String
    public var position: ScienceGraphPoint
    public var mainlineNumber: Int? = nil
}

public enum ScienceGraphEdgeKind: Sendable, Equatable {
    case addresses, supports, contradicts, progression
}

public struct ScienceGraphEdge: Sendable, Equatable {
    public var fromID: UUID
    public var toID: UUID
    public var kind: ScienceGraphEdgeKind
    public var label: String = ""
    public var isCrossTree: Bool = false
    public var caption: String = ""
}

/// Deterministic, bounded-size left-to-right argument map. Arrows point from evidence toward claims.
public struct ScienceGraphLayout: Sendable {
    public let nodes: [ScienceGraphNode]
    public let edges: [ScienceGraphEdge]
    public let width: Double
    public let height: Double

    public init(question: ScientificQuestion, language: AppLanguage = .chinese) {
        if !question.mainline.isEmpty {
            self = Self.mainlineLayout(question, language: language)
            return
        }
        let outgoing = Dictionary(grouping: question.relations, by: \.fromClaimID)
        var levelCache: [UUID: Int] = [:]
        func claimLevel(_ id: UUID) -> Int {
            if let value = levelCache[id] { return value }
            let targets = outgoing[id] ?? []
            let value = min(8, 1 + (targets.map { claimLevel($0.toClaimID) }.max() ?? 0))
            levelCache[id] = value
            return value
        }
        for claim in question.claims { _ = claimLevel(claim.id) }
        let evidenceTargets = Dictionary(grouping: question.evidenceLinks, by: \.atomicExperimentID)
        var levels: [UUID: Int] = [question.id: 0]
        for claim in question.claims { levels[claim.id] = claimLevel(claim.id) }
        for atom in question.atomicExperiments {
            levels[atom.id] = min(9, max(1, (evidenceTargets[atom.id] ?? []).compactMap { levels[$0.claimID] }.max() ?? 0) + 1)
        }
        var builtEdges = question.relations.map { ScienceGraphEdge(fromID: $0.fromClaimID, toID: $0.toClaimID, kind: $0.kind == .supports ? .supports : .contradicts) }
        builtEdges += question.evidenceLinks.map { ScienceGraphEdge(fromID: $0.atomicExperimentID, toID: $0.claimID, kind: $0.kind == .supports ? .supports : .contradicts) }
        let linkedAsPremise = Set(question.relations.map(\.fromClaimID))
        builtEdges += question.claims.filter { !linkedAsPremise.contains($0.id) }.map { ScienceGraphEdge(fromID: $0.id, toID: question.id, kind: .addresses) }
        edges = builtEdges

        var all: [UUID: ScienceGraphNode] = [:]
        all[question.id] = ScienceGraphNode(id: question.id, kind: .question, title: question.title, subtitle: language == .english ? "Scientific Question" : "科学问题", position: ScienceGraphPoint(x: 0, y: 0))
        for claim in question.claims {
            all[claim.id] = ScienceGraphNode(id: claim.id, kind: .claim(claim.kind), title: claim.text,
                subtitle: language == .english ? "\(claim.kind.title(language)) · self-rated \(Int((claim.confidence * 100).rounded()))%" : "\(claim.kind.title) · 自评 \(Int((claim.confidence * 100).rounded()))%", position: ScienceGraphPoint(x: 0, y: 0))
        }
        for atom in question.atomicExperiments {
            all[atom.id] = ScienceGraphNode(id: atom.id, kind: .atomicExperiment(atom.status), title: atom.title,
                subtitle: atom.status.title(language), position: ScienceGraphPoint(x: 0, y: 0))
        }
        let rowSpacing = 142.0, columnSpacing = 270.0, maxRows = 18
        let largestLayer = Dictionary(grouping: levels.values, by: { $0 }).values.map(\.count).max() ?? 1
        let canvasHeight = max(660, Double(min(maxRows, largestLayer)) * rowSpacing + 140)
        var x = 158.0
        let highestLevel = levels.values.max() ?? 0
        for level in 0...highestLevel {
            var ids = levels.filter { $0.value == level }.map(\.key)
            ids.sort { lhs, rhs in
                func targetY(_ id: UUID) -> Double {
                    let targets = builtEdges.filter { $0.fromID == id }.compactMap { all[$0.toID]?.position.y }.filter { $0 > 0 }
                    return targets.isEmpty ? 112 : targets.reduce(0, +) / Double(targets.count)
                }
                let a = targetY(lhs), b = targetY(rhs)
                if abs(a - b) > 0.01 { return a < b }
                return (all[lhs]?.title ?? "") < (all[rhs]?.title ?? "") || ((all[lhs]?.title ?? "") == (all[rhs]?.title ?? "") && lhs.uuidString < rhs.uuidString)
            }
            for (index, id) in ids.enumerated() {
                let column = index / maxRows
                let row = index % maxRows
                let y = 112 + Double(row) * rowSpacing
                all[id]?.position = ScienceGraphPoint(x: x + Double(column) * columnSpacing, y: y)
            }
            x += Double(max(1, (ids.count + maxRows - 1) / maxRows)) * columnSpacing
        }
        for (key, saved) in question.graphPositions {
            if let id = UUID(uuidString: key), all[id] != nil { all[id]?.position = saved }
        }
        nodes = all.values.sorted { ($0.position.x, $0.position.y, $0.id.uuidString) < ($1.position.x, $1.position.y, $1.id.uuidString) }
        width = max(x + 30, (nodes.map { $0.position.x }.max() ?? 0) + 170)
        height = max(canvasHeight, (nodes.map { $0.position.y }.max() ?? 0) + 90)
    }

    public init(nodes: [ScienceGraphNode], edges: [ScienceGraphEdge], width: Double, height: Double) {
        self.nodes = nodes; self.edges = edges; self.width = width; self.height = height
    }

    public func mainlineOnly() -> ScienceGraphLayout {
        var visible = nodes.filter { $0.kind == .question || $0.mainlineNumber != nil }
        let shift = (visible.map { $0.position.y }.min() ?? 130) - 130
        for i in visible.indices { visible[i].position.y -= shift }
        let ids = Set(visible.map(\.id))
        return ScienceGraphLayout(nodes: visible, edges: edges.filter { $0.kind == .progression && ids.contains($0.fromID) && ids.contains($0.toID) },
            width: max(600, (visible.map { $0.position.x }.max() ?? 0) + 170),
            height: max(300, (visible.map { $0.position.y }.max() ?? 0) + 90))
    }

    private static func mainlineLayout(_ question: ScientificQuestion, language: AppLanguage) -> ScienceGraphLayout {
        let claims = Dictionary(uniqueKeysWithValues: question.claims.map { ($0.id, $0) })
        let atoms = Dictionary(uniqueKeysWithValues: question.atomicExperiments.map { ($0.id, $0) })
        let mainIDs = Set(question.mainline.map(\.claimID))
        let stableOrder = Dictionary(uniqueKeysWithValues: (question.claims.map(\.id) + question.atomicExperiments.map(\.id)).enumerated().map { ($0.element, $0.offset) })
        let outgoing = Dictionary(grouping: question.relations, by: \.fromClaimID)
        typealias Ownership = (root: UUID, contradictions: Int, distance: Int, order: Int)
        var choices: [UUID: Ownership] = [:], evaluated: Set<UUID> = [], visiting: Set<UUID> = []
        for (i, step) in question.mainline.enumerated() { choices[step.claimID] = (step.claimID, 0, 0, i) }
        func better(_ a: Ownership, _ b: Ownership) -> Bool {
            (a.contradictions, a.distance, a.order) < (b.contradictions, b.distance, b.order)
        }
        func ownership(_ id: UUID) -> Ownership? {
            if let known = choices[id] { return known }
            guard !evaluated.contains(id), visiting.insert(id).inserted else { return nil }
            var best: Ownership?
            for edge in outgoing[id] ?? [] {
                if let target = ownership(edge.toClaimID) {
                    let candidate: Ownership = (target.root, target.contradictions + (edge.kind == .contradicts ? 1 : 0), target.distance + 1, target.order)
                    if best == nil || better(candidate, best!) { best = candidate }
                }
            }
            visiting.remove(id); evaluated.insert(id)
            choices[id] = best
            return best
        }
        for claim in question.claims { _ = ownership(claim.id) }
        var owner = choices.mapValues(\.root)
        var parents: [UUID: UUID] = [:]
        for claim in question.claims where !mainIDs.contains(claim.id) {
            let candidates = (outgoing[claim.id] ?? []).filter { owner[$0.toClaimID] != nil && owner[$0.toClaimID] == owner[claim.id] }
            parents[claim.id] = candidates.min { a, b in
                let x = choices[a.toClaimID]!, y = choices[b.toClaimID]!
                return (x.contradictions + (a.kind == .contradicts ? 1 : 0), x.distance, stableOrder[a.toClaimID] ?? 0)
                    < (y.contradictions + (b.kind == .contradicts ? 1 : 0), y.distance, stableOrder[b.toClaimID] ?? 0)
            }?.toClaimID
        }
        for atom in question.atomicExperiments {
            let candidates = question.evidenceLinks.filter { $0.atomicExperimentID == atom.id && choices[$0.claimID] != nil }
            if let target = candidates.min(by: { a, b in
                let x = choices[a.claimID]!, y = choices[b.claimID]!
                return (x.contradictions + (a.kind == .contradicts ? 1 : 0), x.distance, x.order)
                    < (y.contradictions + (b.kind == .contradicts ? 1 : 0), y.distance, y.order)
            }) {
                parents[atom.id] = target.claimID; owner[atom.id] = owner[target.claimID]
            }
        }
        let children = Dictionary(grouping: parents.keys, by: { parents[$0]! })
        typealias Tree = (number: Int, step: ScienceMainlineStep, result: ScienceClaim, positions: [UUID: ScienceGraphPoint], depths: [UUID: Int], width: Double)
        var trees: [Tree] = []
        for (number, step) in question.mainline.enumerated() {
            guard let result = claims[step.claimID] else { continue }
            var positions: [UUID: ScienceGraphPoint] = [:], depths: [UUID: Int] = [:], leaf = 0
            func place(_ id: UUID, depth: Int) -> (Int, Int) {
                depths[id] = depth
                let ids = (children[id] ?? []).filter { owner[$0] == result.id }
                    .sorted { (stableOrder[$0] ?? 0) < (stableOrder[$1] ?? 0) }
                let span: (Int, Int)
                if ids.isEmpty { span = (leaf, leaf); leaf += 1 }
                else {
                    let spans = ids.map { place($0, depth: depth + 1) }
                    span = (spans.first!.0, spans.last!.1)
                }
                positions[id] = ScienceGraphPoint(x: 132 + Double(span.0 + span.1) * 132,
                    y: depth == 0 ? 0 : 164 + Double(depth - 1) * 136)
                return span
            }
            _ = place(result.id, depth: 0)
            trees.append((number, step, result, positions, depths, max(264, Double(leaf) * 264)))
        }
        let upperExtent = trees.filter { $0.number % 2 == 0 }.flatMap { $0.positions.values.map(\.y) }.max() ?? 0
        let mainY = upperExtent + 90
        var nodes = [ScienceGraphNode(id: question.id, kind: .question, title: question.title,
            subtitle: language == .english ? "Scientific Question" : "科学问题", position: ScienceGraphPoint(x: 158, y: mainY))]
        var edges = question.relations.map { ScienceGraphEdge(fromID: $0.fromClaimID, toID: $0.toClaimID,
            kind: $0.kind == .supports ? .supports : .contradicts, label: $0.explanation) }
        edges += question.evidenceLinks.map { ScienceGraphEdge(fromID: $0.atomicExperimentID, toID: $0.claimID,
            kind: $0.kind == .supports ? .supports : .contradicts, label: $0.explanation) }
        var placed: Set<UUID> = [question.id], previousCenter = 158.0
        var rightEdges: [Int: Double] = [:]
        for tree in trees {
            let (number, step, result, localPositions, depths, laneWidth) = tree
            // Choose one real display-parent per node, retaining ALL other links as graph edges.
            // This is layout ownership only, never a computed evidentiary strength or probability.
            let side = number % 2
            let center = max(previousCenter + 284, laneWidth / 2 + 36,
                (rightEdges[side] ?? -40) + 40 + laneWidth / 2)
            let sign = side == 0 ? -1.0 : 1.0
            let subtitle = step.role == .discussion ? (language == .english ? "DISCUSSION · synthesis" : "DISCUSSION · 综合讨论")
                : (language == .english ? "Mainline result \(number + 1) · Level 1" : "主线结果 \(number + 1) · 一级结论")
            nodes.append(ScienceGraphNode(id: result.id, kind: .claim(result.kind), title: result.text,
                subtitle: subtitle, position: ScienceGraphPoint(x: center, y: mainY), mainlineNumber: number + 1))
            edges.append(ScienceGraphEdge(fromID: number == 0 ? question.id : question.mainline[number - 1].claimID,
                toID: result.id, kind: .progression, label: step.motivation))
            placed.insert(result.id)
            let xShift = center - (localPositions[result.id]?.x ?? 0)
            for id in localPositions.keys.sorted(by: { (stableOrder[$0] ?? 0) < (stableOrder[$1] ?? 0) }) where id != result.id {
                let local = localPositions[id]!
                let point = ScienceGraphPoint(x: local.x + xShift, y: mainY + sign * local.y)
                if let claim = claims[id] {
                    nodes.append(ScienceGraphNode(id: id, kind: .claim(claim.kind), title: claim.text,
                        subtitle: language == .english ? "Level \((depths[id] ?? 1) + 1) conclusion" : "\((depths[id] ?? 1) + 1) 级结论", position: point))
                } else if let atom = atoms[id] {
                    nodes.append(ScienceGraphNode(id: id, kind: .atomicExperiment(atom.status), title: atom.title,
                        subtitle: atom.status.title(language), position: point))
                }
                placed.insert(id)
            }
            rightEdges[side] = center + laneWidth / 2
            previousCenter = center
        }
        let startX = max(previousCenter + 170, rightEdges.values.max() ?? 0) + 50
        // Preserve disconnected records visibly; never fabricate evidence to force everything onto the line.
        let orphanClaims = question.claims.filter { !placed.contains($0.id) }
        let orphanAtoms = question.atomicExperiments.filter { !placed.contains($0.id) }
        let pendingLabel = language == .english ? "Not linked to mainline" : "尚未关联主线"
        for (i, claim) in orphanClaims.enumerated() {
            nodes.append(ScienceGraphNode(id: claim.id, kind: .claim(claim.kind), title: claim.text, subtitle: pendingLabel,
                position: ScienceGraphPoint(x: startX + 132 + Double(i / 12) * 264, y: mainY + 164 + Double(i % 12) * 136)))
        }
        let orphanX = startX + Double(max(1, (orphanClaims.count + 11) / 12)) * 264
        for (i, atom) in orphanAtoms.enumerated() {
            nodes.append(ScienceGraphNode(id: atom.id, kind: .atomicExperiment(atom.status), title: atom.title, subtitle: pendingLabel,
                position: ScienceGraphPoint(x: orphanX + 132 + Double(i / 12) * 264, y: mainY + 164 + Double(i % 12) * 136)))
        }
        for i in nodes.indices {
            if let saved = question.graphPositions[nodes[i].id.uuidString] { nodes[i].position = saved }
        }
        for i in edges.indices where edges[i].kind != .progression {
            if let source = owner[edges[i].fromID], let target = owner[edges[i].toID] {
                edges[i].isCrossTree = source != target
            }
        }
        return ScienceGraphLayout(nodes: nodes, edges: edges,
            width: max(850, (nodes.map { $0.position.x }.max() ?? 0) + 170),
            height: max(600, (nodes.map { $0.position.y }.max() ?? 0) + 100))
    }
}
