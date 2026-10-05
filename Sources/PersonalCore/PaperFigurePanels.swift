import Foundation

extension PaperAnalysis {
    public struct Discussion: Codable, Equatable, Sendable {
        public var summary: String
        public var origin: ScienceNarrativeOrigin
        public var source_pages: [Int]
    }
    public struct FigurePanel: Codable, Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String
        public var figure_ref: String
        public var panel_label: String
        public var title: String
        public var question: String
        public var observed_result: String
        public var interpretation: String
        public var limitations: String
        public var method_keys: [String]
        public var finding_keys: [String]
        public var source_pages: [Int]
    }
    public enum PanelLinkKind: String, Codable, CaseIterable, Sendable {
        case supports, contradicts, motivates, controlsFor = "controls_for", extends
        public func title(_ language: AppLanguage) -> String {
            switch self {
            case .supports: language == .english ? "Supports" : "支持"
            case .contradicts: language == .english ? "Challenges" : "挑战"
            case .motivates: language == .english ? "Motivates next test" : "引出下一检验"
            case .controlsFor: language == .english ? "Controls for alternative" : "检验替代解释"
            case .extends: language == .english ? "Extends scope" : "扩展适用范围"
            }
        }
    }
    public struct PanelLink: Codable, Equatable, Sendable {
        public var from_panel: String
        public var to_panel: String
        public var kind: PanelLinkKind
        public var explanation: String
        public var limitations: String
        public var origin: ScienceNarrativeOrigin
        public var source_pages: [Int]
    }

    func validatePanels(pageCount: Int, language: AppLanguage) throws {
        let panels = figure_panels ?? [], links = panel_links ?? []
        let keys = panels.map(\.key), ids = Set(keys)
        guard panels.count <= 120, links.count <= 400, ids.count == keys.count,
              keys.allSatisfy({ !$0.isEmpty && $0.count <= 40 && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 } }) else {
            throw WorkspaceError.invalid("Figure-panel keys must be unique ASCII identifiers; panel/link limits exceeded.")
        }
        func citations(_ pages: [Int], required: Bool) throws {
            guard (!required || !pages.isEmpty), Set(pages).count == pages.count, pages.allSatisfy({ (1...pageCount).contains($0) }) else {
                throw WorkspaceError.invalid("Figure panels and reported links need real, unique PDF page citations.")
            }
        }
        for panel in panels {
            guard !panel.figure_ref.isEmpty, panel.figure_ref.count <= 100, panel.panel_label.count <= 100,
                  !panel.title.isEmpty, !panel.question.isEmpty,
                  !panel.observed_result.isEmpty || !panel.interpretation.isEmpty,
                  Set(panel.method_keys).count == panel.method_keys.count, Set(panel.finding_keys).count == panel.finding_keys.count,
                  panel.method_keys.allSatisfy({ key in methods.contains { $0.key == key } }),
                  panel.finding_keys.allSatisfy({ key in findings.contains { $0.key == key } }),
                  panel.observed_result.isEmpty || !panel.finding_keys.isEmpty else {
                throw WorkspaceError.invalid("A figure panel needs its identity, question and real method/finding references.")
            }
            for value in [panel.title, panel.question, panel.observed_result, panel.interpretation, panel.limitations] {
                guard value.count <= 10_000 else { throw WorkspaceError.invalid("A figure panel field is too long.") }
                try language.requiresEnglish(value)
            }
            try citations(panel.source_pages, required: true)
        }
        let identities = panels.map { $0.figure_ref.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "|" + $0.panel_label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        guard Set(identities).count == identities.count else { throw WorkspaceError.invalid("Duplicate figure-panel identities.") }
        let linkKeys = links.map { "\($0.from_panel)|\($0.to_panel)|\($0.kind.rawValue)" }
        guard Set(linkKeys).count == linkKeys.count else { throw WorkspaceError.invalid("Duplicate figure-panel links.") }
        for link in links {
            guard link.from_panel != link.to_panel, ids.contains(link.from_panel), ids.contains(link.to_panel),
                  !link.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  link.explanation.count <= 10_000, link.limitations.count <= 10_000 else {
                throw WorkspaceError.invalid("Panel links need real distinct endpoints and a specific logical explanation.")
            }
            try language.requiresEnglish(link.explanation); try language.requiresEnglish(link.limitations)
            try citations(link.source_pages, required: link.origin == .reported)
        }
        // Later panels may challenge earlier ones while earlier ones motivated later tests.
        // These mixed reading/evidence relations are not an acyclic proof tree; do not erase valid feedback.
    }
}
