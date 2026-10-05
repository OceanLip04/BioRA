import Foundation

/// A reading map, not a proof DAG. Panel relations may include feedback and are never
/// converted into scientific evidence links merely to render them.
public struct PaperPanelGraph: Sendable {
    public let question: ScientificQuestion
    public let layout: ScienceGraphLayout

    public init(analysis: PaperAnalysis, readingID: UUID, language: AppLanguage) {
        let panels = analysis.figure_panels ?? []
        let links = analysis.panel_links ?? []
        func t(_ zh: String, _ en: String) -> String { language == .english ? en : zh }
        var ids: [String: UUID] = [:]
        for (index, key) in panels.map(\.key).sorted().enumerated() {
            var number = index + 1
            var id = UUID(uuidString: String(format: "F16E0000-0000-4000-8000-%012llX", UInt64(number)))!
            if id == readingID { number += 1_000; id = UUID(uuidString: String(format: "F16E0000-0000-4000-8000-%012llX", UInt64(number)))! }
            ids[key] = id
        }
        var groups: [String] = [], grouped: [String: [PaperAnalysis.FigurePanel]] = [:]
        for panel in panels {
            if grouped[panel.figure_ref] == nil { groups.append(panel.figure_ref) }
            grouped[panel.figure_ref, default: []].append(panel)
        }
        var nodes: [ScienceGraphNode] = [], claims: [ScienceClaim] = []
        var column = 0
        for figure in groups {
            let values = grouped[figure] ?? []
            for (index, panel) in values.enumerated() {
                guard let id = ids[panel.key] else { continue }
                let fields: [(String, String)] = [(t("问题", "Question"), panel.question),
                               (t("观察结果", "Observation"), panel.observed_result),
                               (t("解释", "Interpretation"), panel.interpretation),
                               (t("边界", "Boundary"), panel.limitations),
                               (t("方法引用", "Method keys"), panel.method_keys.joined(separator: ", ")),
                               (t("发现引用", "Finding keys"), panel.finding_keys.joined(separator: ", ")),
                               (t("PDF 页", "PDF pages"), panel.source_pages.map(String.init).joined(separator: ", "))]
                let details = fields.filter { !$0.1.isEmpty }.map { $0.0 + "\n" + $0.1 }.joined(separator: "\n\n")
                let title = panel.figure_ref + (panel.panel_label.isEmpty ? "" : " · " + panel.panel_label) + " — " + panel.title
                claims.append(ScienceClaim(id: id, kind: .observation, text: title, sourceNote: details))
                nodes.append(ScienceGraphNode(id: id, kind: .claim(.observation), title: panel.title,
                    subtitle: panel.figure_ref + " · " + panel.panel_label,
                    position: ScienceGraphPoint(x: 150 + Double(column + index / 8) * 304, y: 100 + Double(index % 8) * 152)))
            }
            column += max(1, (values.count + 7) / 8)
        }
        let edges = links.compactMap { link -> ScienceGraphEdge? in
            guard let from = ids[link.from_panel], let to = ids[link.to_panel] else { return nil }
            let kind: ScienceGraphEdgeKind = link.kind == .supports ? .supports : link.kind == .contradicts ? .contradicts : .progression
            let pages = link.source_pages.map(String.init).joined(separator: ", ")
            let label = link.kind.title(language) + "\n" + link.explanation
                + (link.limitations.isEmpty ? "" : "\n" + t("边界：", "Boundary: ") + link.limitations)
                + "\n" + (link.origin == .reported ? t("原文报告", "Reported") : t("归纳关系，需核对", "Inferred relation; verify"))
                + (pages.isEmpty ? "" : " · " + t("PDF 页 ", "PDF pp. ") + pages)
            return ScienceGraphEdge(fromID: from, toID: to, kind: kind, label: label, caption: link.kind.title(language))
        }
        question = ScientificQuestion(id: readingID, title: analysis.paper_title, detail: analysis.central_question, claims: claims)
        layout = ScienceGraphLayout(nodes: nodes, edges: edges,
            width: max(400, (nodes.map { $0.position.x }.max() ?? 150) + 150),
            height: max(300, (nodes.map { $0.position.y }.max() ?? 100) + 100))
    }
}
