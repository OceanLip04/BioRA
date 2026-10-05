import Foundation

/// Evidence membership follows real directed links, not similarity, creation order, or narrative order.
public struct ScienceArgumentIndex: Sendable {
    public let question: ScientificQuestion
    public init(question: ScientificQuestion) { self.question = question }

    public func premiseIDs(for resultID: UUID) -> Set<UUID> {
        let mainIDs = Set(question.mainline.map(\.claimID))
        let incoming = Dictionary(grouping: question.relations, by: \.toClaimID)
        var found: Set<UUID> = [resultID], queue = [resultID], cursor = 0
        while cursor < queue.count {
            let target = queue[cursor]; cursor += 1
            for edge in incoming[target] ?? [] where !mainIDs.contains(edge.fromClaimID) {
                if found.insert(edge.fromClaimID).inserted { queue.append(edge.fromClaimID) }
            }
        }
        return found
    }

    public func evidence(for resultID: UUID) -> [AtomicEvidenceLink] {
        let premises = premiseIDs(for: resultID)
        return question.evidenceLinks.filter { premises.contains($0.claimID) }
    }

    public var unassignedClaimIDs: Set<UUID> {
        let connected = question.mainline.reduce(into: Set<UUID>()) { $0.formUnion(premiseIDs(for: $1.claimID)) }
        return Set(question.claims.map(\.id)).subtracting(connected)
    }
    public var unassignedAtomIDs: Set<UUID> {
        let connected = question.mainline.flatMap { evidence(for: $0.claimID).map(\.atomicExperimentID) }
        return Set(question.atomicExperiments.map(\.id)).subtracting(connected)
    }
}
