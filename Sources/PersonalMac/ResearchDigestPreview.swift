import Foundation
import PersonalCore

/// Fictional, isolated preview with no file, network, credential or database access.
extension Workspace {
    static func dailyResearchPreview() throws -> Workspace {
        var workspace = Workspace.paperLogicPreview()
        workspace.language = .english
        workspace.laboratory.enabled = true; workspace.laboratory.automatic = false
        workspace.laboratory.baseURL = "https://research.example.org/api"
        let original = workspace.literatureReadings[0].graph
        let claims = Dictionary(uniqueKeysWithValues: original.claims.enumerated().map { ($0.element.id, "c\($0.offset)") })
        let atoms = Dictionary(uniqueKeysWithValues: original.atomicExperiments.enumerated().map { ($0.element.id, "a\($0.offset)") })
        let graph: JSONValue = .object([
            "title": .string(original.title), "detail": .string("Fictional UI preview only, not scientific evidence."),
            "claims": .array(original.claims.map { .object(["key": .string(claims[$0.id]!), "kind": .string($0.kind.rawValue), "text": .string($0.text), "source_page": .number(1)]) }),
            "atomic_experiments": .array(original.atomicExperiments.map { .object(["key": .string(atoms[$0.id]!), "title": .string($0.title), "method": .string($0.method), "status": .string($0.status.rawValue), "observed_result": .string($0.observedResult), "source_page": .number(1)]) }),
            "evidence_links": .array(original.evidenceLinks.map { .object(["atom_key": .string(atoms[$0.atomicExperimentID]!), "claim_key": .string(claims[$0.claimID]!), "kind": .string($0.kind.rawValue), "explanation": .string($0.explanation), "limitations": .string($0.limitations)]) }),
            "claim_links": .array(original.relations.map { .object(["from_key": .string(claims[$0.fromClaimID]!), "to_key": .string(claims[$0.toClaimID]!), "kind": .string($0.kind.rawValue), "explanation": .string($0.explanation), "limitations": .string($0.limitations)]) }),
            "mainline": .array(original.mainline.map { .object(["claim_key": .string(claims[$0.claimID]!), "question": .string($0.question), "motivation": .string($0.motivation), "origin": .string($0.origin.rawValue), "role": .string($0.role.rawValue)]) })
        ])
        let day = workspace.laboratory.day(Date())
        let data: JSONValue = .object([
            "schema_version": .number(1), "id": .string("fictional-daily-preview"), "date": .string(day), "timezone": .string(workspace.laboratory.timezone), "language": .string("en"), "feed": .string("default"), "revision": .number(1),
            "title": .string("Fictional daily research · signal and interpretation"), "summary": .string("A fictional demonstration of a daily research mainline and two connected evidence trees. No scientific result or server connection is implied."),
            "published_at": .string(ISO8601DateFormatter().string(from: Date())),
            "sources": .array([.object(["id": .string("preview"), "title": .string("Fictional source, not a publication"), "url": .string("https://example.org/fictional-paper"), "page_count": .number(2)])]),
            "citations": .array((Array(claims.values) + Array(atoms.values)).map { .object(["node_key": .string($0), "source_id": .string("preview"), "page": .number(1)]) }),
            "graph": graph
        ])
        let digest = try DailyResearchDigest.decode(JSONEncoder().encode(data))
        workspace.researchDigests = [CachedResearchDigest(key: try ResearchDigestClient.key(configuration: workspace.laboratory, date: day, language: .english), digest: digest, graph: try digest.materialize(language: .english), etag: nil, checkedAt: Date())]
        return workspace
    }
}
