import PersonalCore
import SwiftUI

struct FigurePanelLogicView: View {
    let analysis: PaperAnalysis?
    let readingID: UUID
    let language: AppLanguage
    var canvasHeight: CGFloat = 500
    var supplement: (() -> Void)? = nil
    private func t(_ zh: String, _ en: String) -> String { language == .english ? en : zh }

    var body: some View {
        if let analysis, let panels = analysis.figure_panels, !panels.isEmpty {
            let map = PaperPanelGraph(analysis: analysis, readingID: readingID, language: language)
            VStack(alignment: .leading, spacing: 16) {
                Text(t("从图面板理解论证：箭头标明为何继续检验、如何排除替代解释、或怎样支持与挑战发现。面板顺序本身不是证明；点按节点核对观察、解释、页码与连边依据。", "Read the argument through its figure panels: arrows explain the next test, alternative controls, or support and challenges to a finding. Panel order is not proof. Select a node to inspect observations, interpretation, pages, and link warrants."))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ScienceMindMapView(question: map.question, language: language, canEdit: false, canMoveNodes: false,
                    experimentName: { _ in "" }, moveNode: { _, _ in false }, resetLayout: {}, addClaim: {}, addAtom: {},
                    editQuestion: {}, editClaim: { _ in }, editAtom: { _ in }, linkClaim: { _ in }, linkAtom: { _ in },
                    canvasHeight: canvasHeight, layoutOverride: map.layout,
                    titleOverride: t("图面板之间的逻辑", "Logic between figure panels"),
                    summaryOverride: t("\(panels.count) 个面板 · \(map.layout.edges.count) 条逻辑关系", "\(panels.count) panels · \(map.layout.edges.count) logical links"))
                DisclosureGroup(t("逐条核对逻辑连边", "Review each logical link")) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array((analysis.panel_links ?? []).enumerated()), id: \.offset) { _, link in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(label(link.from_panel, panels) + " → " + label(link.to_panel, panels)).font(.system(size: 13, weight: .semibold))
                                Text(link.kind.title(language) + " · " + link.explanation).font(.system(size: 12))
                                if !link.limitations.isEmpty { Text(t("解释边界：", "Boundary: ") + link.limitations).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                                Text((link.origin == .reported ? t("原文报告", "Reported") : t("归纳关系，需核对", "Inferred relation; verify"))
                                    + (link.source_pages.isEmpty ? "" : " · " + t("PDF 页 ", "PDF pp. ") + link.source_pages.map(String.init).joined(separator: ", ")))
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if map.layout.edges.isEmpty { Text(t("原文未提供足以建立面板连边的依据；未强行连线。", "No grounded panel relations were extracted; no links were invented.")).foregroundStyle(Palette.muted) }
                    }.padding(.top, 12).textSelection(.enabled)
                }.font(.system(size: 13, weight: .medium))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "rectangle.connected.to.line.below").font(.system(size: 28)).foregroundStyle(Palette.muted)
                Text(t("尚无图面板逻辑", "No figure-panel logic yet")).font(EditorialType.title(24))
                Text(analysis?.figure_panels == nil
                    ? t("这份阅读记录没有图面板数据。可以用专用提示词补充，也可重新解析 PDF；不会凭空补造面板或关系。", "This reading has no panel data. Supplement it with the dedicated prompt or reanalyze the PDF; panels and links are not invented without source evidence.")
                    : t("未识别出有依据的图面板。可补充含图注的原文，再复制专用提示词并粘贴结果。", "No grounded figure panels were identified. Supply original captions, copy the dedicated prompt, and paste the result."))
                    .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if let supplement {
                    Button(t("用自己的 LLM 补充…", "Supplement with your own LLM…"), systemImage: "doc.on.clipboard", action: supplement)
                        .buttonStyle(QuietButtonStyle(prominent: true))
                    Text(t("复制专用提示词 → 粘贴 JSON → 审阅补充，无需重新生成主线。", "Copy a dedicated prompt → paste JSON → review the supplement, without regenerating the mainline."))
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func label(_ key: String, _ panels: [PaperAnalysis.FigurePanel]) -> String {
        guard let panel = panels.first(where: { $0.key == key }) else { return key }
        return panel.figure_ref + (panel.panel_label.isEmpty ? "" : " · " + panel.panel_label)
    }
}
