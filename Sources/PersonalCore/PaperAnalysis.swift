import Foundation

public enum PaperStudyType: String, Codable, CaseIterable, Sendable {
    case experimental, observational, review, methods, simulation, mixed, unclear
}

public struct PaperAnalysis: Codable, Equatable, Sendable {
    public struct Statement: Codable, Equatable, Sendable {
        public enum Origin: String, Codable, Sendable { case reported, inferred }
        public var text: String; public var origin: Origin; public var source_pages: [Int]
    }
    public struct Method: Codable, Equatable, Sendable {
        public var key: String; public var title: String; public var system: String; public var design: String
        public var intervention: String; public var controls: String; public var measurements: String
        public var sample_size: String; public var statistics: String; public var source_pages: [Int]; public var figure_refs: [String]
    }
    public struct Finding: Codable, Equatable, Sendable {
        public var key: String; public var statement: String; public var quantitative_result: String
        public var uncertainty: String; public var interpretation: String
        public var method_keys: [String]; public var source_pages: [Int]; public var figure_refs: [String]
    }
    public var paper_title: String; public var authors: [String]; public var year: String; public var doi: String
    public var study_type: PaperStudyType; public var central_question: String; public var background_and_gap: String; public var summary: String
    public var methods: [Method]; public var findings: [Finding]
    public var conclusions: [Statement]; public var limitations: [Statement]; public var open_questions: [Statement]
    public var discussion: Discussion? = nil
    public var figure_panels: [FigurePanel]? = nil
    public var panel_links: [PanelLink]? = nil

    public static func validateShape(_ json: JSONValue, requirePanelLogic: Bool = false) throws {
        func object(_ value: JSONValue, keys: Set<String>) throws {
            guard let fields = value.object, Set(fields.keys) == keys else { throw WorkspaceError.invalid("Paper JSON must use exactly the specified fields.") }
        }
        let base: Set<String> = ["paper_title", "authors", "year", "doi", "study_type", "central_question", "background_and_gap", "summary", "methods", "findings", "conclusions", "limitations", "open_questions"]
        let extra: Set<String> = ["discussion", "figure_panels", "panel_links"]
        guard let fields = json.object, base.isSubset(of: Set(fields.keys)),
              Set(fields.keys).isSubset(of: base.union(extra)),
              !requirePanelLogic || extra.isSubset(of: Set(fields.keys)) else {
            throw WorkspaceError.invalid("Paper JSON must use the specified reading and figure-panel fields.")
        }
        let groups: [(String, Set<String>)] = [
            ("methods", ["key", "title", "system", "design", "intervention", "controls", "measurements", "sample_size", "statistics", "source_pages", "figure_refs"]),
            ("findings", ["key", "statement", "quantitative_result", "uncertainty", "interpretation", "method_keys", "source_pages", "figure_refs"]),
            ("conclusions", ["text", "origin", "source_pages"]), ("limitations", ["text", "origin", "source_pages"]), ("open_questions", ["text", "origin", "source_pages"])
        ]
        for (name, keys) in groups {
            guard case .array(let values) = json.object?[name] else { throw WorkspaceError.invalid("Paper JSON arrays are missing.") }
            for value in values { try object(value, keys: keys) }
        }
        if fields["discussion"] != nil {
            try object(json["discussion"], keys: ["summary", "origin", "source_pages"])
        }
        for (name, keys) in [("figure_panels", Set(["key", "figure_ref", "panel_label", "title", "question", "observed_result", "interpretation", "limitations", "method_keys", "finding_keys", "source_pages"])),
                             ("panel_links", Set(["from_panel", "to_panel", "kind", "explanation", "limitations", "origin", "source_pages"]))] where fields[name] != nil {
            guard let values = json[name].array else { throw WorkspaceError.invalid("Figure panel arrays are invalid.") }
            for value in values { try object(value, keys: keys) }
        }
    }

    public func validated(pageCount: Int, language: AppLanguage) throws {
        guard !paper_title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !central_question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !summary.isEmpty,
              paper_title.count <= 500, summary.count <= 20_000, methods.count <= 60, findings.count <= 100,
              conclusions.count <= 40, limitations.count <= 40, open_questions.count <= 40, authors.count <= 100,
              authors.allSatisfy({ $0.count <= 300 }), year.count <= 20, doi.count <= 300, pageCount > 0 else {
            throw WorkspaceError.invalid("The paper reading is incomplete or exceeds its limits.")
        }
        func prose(_ values: [String]) throws {
            for value in values { guard value.count <= 20_000 else { throw WorkspaceError.invalid("A paper analysis field is too long.") }; try language.requiresEnglish(value) }
        }
        func pages(_ values: [Int], required: Bool) throws {
            guard (!required || !values.isEmpty), Set(values).count == values.count,
                  values.allSatisfy({ (1...pageCount).contains($0) }) else { throw WorkspaceError.invalid("Use real, unique PDF page citations for every reported method, finding, and statement.") }
        }
        let methodKeys = methods.map(\.key), findingKeys = findings.map(\.key)
        guard Set(methodKeys + findingKeys).count == methodKeys.count + findingKeys.count,
              (methodKeys + findingKeys).allSatisfy({ !$0.isEmpty && $0.count <= 40 }) else { throw WorkspaceError.invalid("Paper method and finding keys must be unique.") }
        try prose([paper_title, central_question, background_and_gap, summary])
        for item in methods {
            guard item.figure_refs.count <= 100, item.figure_refs.allSatisfy({ $0.count <= 200 }) else { throw WorkspaceError.invalid("Too many figure references.") }
            try pages(item.source_pages, required: true)
            guard !item.title.isEmpty, !item.design.isEmpty else { throw WorkspaceError.invalid("Each extracted method needs a title and study design.") }
            try prose([item.title, item.system, item.design, item.intervention, item.controls, item.measurements, item.sample_size, item.statistics])
        }
        for item in findings {
            guard item.figure_refs.count <= 100, item.figure_refs.allSatisfy({ $0.count <= 200 }) else { throw WorkspaceError.invalid("Too many figure references.") }
            try pages(item.source_pages, required: true)
            guard !item.statement.isEmpty, Set(item.method_keys).count == item.method_keys.count,
                  item.method_keys.allSatisfy({ methodKeys.contains($0) }) else { throw WorkspaceError.invalid("A paper finding references an unknown method or lacks a statement.") }
            try prose([item.statement, item.quantitative_result, item.uncertainty, item.interpretation])
        }
        for item in conclusions + limitations + open_questions {
            guard !item.text.isEmpty else { throw WorkspaceError.invalid("A paper reading statement is empty.") }
            try pages(item.source_pages, required: item.origin == .reported); try prose([item.text])
        }
        if let discussion {
            guard !discussion.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceError.invalid("The Discussion synthesis is empty.") }
            try prose([discussion.summary]); try pages(discussion.source_pages, required: discussion.origin == .reported)
        }
        try validatePanels(pageCount: pageCount, language: language)
    }
}
