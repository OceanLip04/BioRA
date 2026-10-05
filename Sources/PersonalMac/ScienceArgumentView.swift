import PersonalCore
import SwiftUI

/// A readable spine with expandable conclusion trees. Cross-tree evidence remains in the canvas.
struct ScienceArgumentView: View {
    let question: ScientificQuestion
    let language: AppLanguage
    @State private var expanded: Set<UUID> = []
    private func text(_ zh: String, _ en: String) -> String { language == .english ? en : zh }
    private var index: ScienceArgumentIndex { ScienceArgumentIndex(question: question) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(Palette.accent)
                Text(text("研究主线", "Research mainline")).font(EditorialType.title(24))
                Spacer()
                Text(text("先读结果，再展开论证树", "Read the results, then unfold their evidence trees"))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            if question.mainline.isEmpty {
                Text(text("尚未整理主线。原有结论与实验证据仍保留；请选择一级结果并说明研究承接理由。不会按创建顺序猜测科学逻辑。",
                          "No mainline has been organized. Existing conclusions and evidence are preserved. Choose top-level results and explain the research rationale; creation order is not scientific logic."))
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            ForEach(Array(question.mainline.enumerated()), id: \.element.id) { number, step in
                if let claim = question.claims.first(where: { $0.id == step.claimID }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", number + 1)).font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Palette.accent).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 9) {
                                if step.role == .discussion {
                                    Text(text("DISCUSSION · 综合讨论", "DISCUSSION · synthesis"))
                                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                                }
                                Text(step.role == .discussion ? text("这些发现如何综合，边界在哪里？", "How do these findings fit together, and where are their limits?") : text(number == 0 ? "为什么先研究这一步" : "为什么进入下一步",
                                          number == 0 ? "Why start here" : "Why take the next step"))
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                                Text(step.motivation.isEmpty ? text("承接理由待补充", "Research rationale not recorded") : step.motivation)
                                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                                if step.origin == .inferred {
                                    Label(text("归纳的研究思路，非原文明示", "Reconstructed rationale, not explicitly stated"), systemImage: "info.circle")
                                        .font(.system(size: 10)).foregroundStyle(Palette.warning)
                                }
                                Text(step.question.isEmpty ? text("本轮研究问题待补充", "Specific research question not recorded") : step.question)
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.accent)
                                Text(claim.text).font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        conclusionTree(claim, root: true, path: [])
                    }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 0.7))
                }
            }
            if !question.mainline.isEmpty {
                let count = index.unassignedClaimIDs.count + index.unassignedAtomIDs.count
                if count > 0 {
                    Text(text("\(count) 个节点尚未关联主线：仍保留在画布中，不会自动补造连线。",
                              "\(count) nodes are not connected to the mainline. They remain on the canvas; no links are fabricated."))
                        .font(.system(size: 11)).foregroundStyle(Palette.warning)
                }
                Text(text("主线箭头只表示研究推进。论证树的证据从实验、下层结论逐级指向上层；跨树连线可在画布查看。",
                          "Mainline arrows indicate research progression only. Evidence flows from tests and lower conclusions toward upper conclusions; cross-tree links are visible on the canvas."))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }.textSelection(.enabled)
    }

    private func conclusionTree(_ claim: ScienceClaim, root: Bool, path: Set<UUID>) -> AnyView {
        let incoming = question.relations.filter { $0.toClaimID == claim.id }
        let tests = question.evidenceLinks.filter { $0.claimID == claim.id }
        let nextPath = path.union([claim.id])
        return AnyView(DisclosureGroup(isExpanded: Binding(get: { expanded.contains(claim.id) }, set: { value in
            if value { expanded.insert(claim.id) } else { expanded.remove(claim.id) }
        })) {
            if expanded.contains(claim.id) {
                VStack(alignment: .leading, spacing: 13) {
                    if !claim.sourceNote.isEmpty { Text(claim.sourceNote).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    if incoming.isEmpty && tests.isEmpty {
                        Text(text("尚未记录支撑证据", "No evidence recorded")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    ForEach(incoming) { edge in
                        if let child = question.claims.first(where: { $0.id == edge.fromClaimID }) {
                            VStack(alignment: .leading, spacing: 7) {
                                warrant(edge.kind, explanation: edge.explanation, limitations: edge.limitations)
                                if nextPath.contains(child.id) {
                                    Text(text("循环引用，需修正", "Cyclic reference; review required")).font(.system(size: 11)).foregroundStyle(Palette.warning)
                                } else {
                                    conclusionTree(child, root: false, path: nextPath)
                                }
                            }.padding(.leading, 14).overlay(alignment: .leading) { Rectangle().fill(Palette.line).frame(width: 2) }
                        }
                    }
                    ForEach(tests) { edge in
                        if let atom = question.atomicExperiments.first(where: { $0.id == edge.atomicExperimentID }) {
                            VStack(alignment: .leading, spacing: 7) {
                                Label(atom.title, systemImage: "flask").font(.system(size: 12, weight: .medium))
                                Text(text("方法：", "Method: ") + atom.method).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                Text(text("观察：", "Observation: ") + atom.observedResult).font(.system(size: 11))
                                warrant(edge.kind, explanation: edge.explanation, limitations: edge.limitations)
                                if !atom.sourceNote.isEmpty { Text(atom.sourceNote).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                            }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.padding(.top, 10)
            }
        } label: {
            if root {
                if question.mainline.first(where: { $0.claimID == claim.id })?.role == .discussion {
                    Text(text("讨论综合依据 · \(incoming.count) 条结论关系", "Discussion basis · \(incoming.count) finding links"))
                        .font(.system(size: 12, weight: .medium))
                } else {
                    let count = Set(index.evidence(for: claim.id).map(\.atomicExperimentID)).count
                    Text(text("展开论证树 · \(count) 项实验", "Evidence tree · \(count) tests")).font(.system(size: 12, weight: .medium))
                }
            } else {
                Text(claim.text).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
        }.tint(Palette.accent))
    }

    private func warrant(_ kind: ScienceRelationKind, explanation: String, limitations: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(kind.title(language) + " · " + (explanation.isEmpty ? text("论证依据待补充", "Warrant not recorded") : explanation))
                .font(.system(size: 11)).foregroundStyle(kind == .supports ? Palette.success : Palette.warning)
            if !limitations.isEmpty {
                Text(text("解释边界：", "Inferential boundary: ") + limitations).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }
}
