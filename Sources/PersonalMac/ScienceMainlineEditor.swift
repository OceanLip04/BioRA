import PersonalCore
import SwiftUI

struct ScienceMainlineEditor: View {
    @Environment(\.dismiss) private var dismiss
    let question: ScientificQuestion
    let language: AppLanguage
    let save: ([ScienceMainlineStep]) -> String?
    @State private var steps: [ScienceMainlineStep]
    @State private var error: String?
    init(question: ScientificQuestion, language: AppLanguage, save: @escaping ([ScienceMainlineStep]) -> String?) {
        self.question = question; self.language = language; self.save = save
        _steps = State(initialValue: question.mainline)
    }
    private func text(_ zh: String, _ en: String) -> String { language == .english ? en : zh }
    private var eligible: [ScienceClaim] {
        let directTargets = Set(question.evidenceLinks.map(\.claimID))
        return question.claims.filter { !directTargets.contains($0.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("整理研究主线", "Organize research mainline")).font(EditorialType.title(26))
            Text(text("选择一级结果作为树根。原子实验先支持下层结论，再逐级汇聚到主线；树之间可有交叉证据。调整顺序不是增加证明关系。",
                      "Choose top-level results as tree roots. Atomic tests inform lower conclusions, which feed the mainline through further levels. Trees may share evidence. Changing the order does not add proof."))
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(steps[i].role == .discussion ? "DISCUSSION" : text("结果 \(i + 1)", "Result \(i + 1)")).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Button { move(i, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(i == 0).accessibilityLabel(text("上移", "Move up"))
                                Button { move(i, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(i == steps.count - 1).accessibilityLabel(text("下移", "Move down"))
                                Button(role: .destructive) {
                                    steps.remove(at: i)
                                    if steps.indices.contains(i) { steps[i].motivation = "" }
                                } label: { Image(systemName: "minus.circle") }.accessibilityLabel(text("移出主线（保留结论）", "Remove from mainline (keep conclusion)"))
                            }
                            Picker(text("一级结论", "Top-level conclusion"), selection: $steps[i].claimID) {
                                ForEach(eligible) { Text($0.text).lineLimit(2).tag($0.id) }
                            }
                            Picker(text("主线角色", "Mainline role"), selection: $steps[i].role) {
                                Text(text("主要结果", "Principal result")).tag(ScienceMainlineRole.result)
                                Text("Discussion").tag(ScienceMainlineRole.discussion)
                            }
                            if steps[i].role == .discussion {
                                Text(text("综合讨论应选用结论节点，且只能有一个，置于主线末尾。", "Discussion must use a conclusion node and be the unique final step."))
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                            TextField(text("本轮要回答什么问题？", "What question does this result answer?"), text: $steps[i].question, axis: .vertical)
                            TextField(text(i == 0 ? "为什么先做这一步？" : "上一结果留下什么缺口，为什么继续这一步？",
                                           i == 0 ? "Why start with this check?" : "What gap remains after the previous result, and why this next check?"), text: $steps[i].motivation, axis: .vertical)
                                .lineLimit(2...4)
                            Picker(text("承接理由来源", "Rationale source"), selection: $steps[i].origin) {
                                Text(text("原文或记录明确说明", "Explicit in source or record")).tag(ScienceNarrativeOrigin.reported)
                                Text(text("归纳思路（待核实）", "Reconstructed (verify)")).tag(ScienceNarrativeOrigin.inferred)
                            }
                        }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if eligible.isEmpty {
                Text(text("先添加一级结论，并用下层结论支撑它。已有原子实验直连的结论不能直接选为主线树根。",
                          "Add a top-level conclusion supported by lower conclusions first. Conclusions directly linked from atomic tests cannot be mainline roots."))
                    .font(.system(size: 11)).foregroundStyle(Palette.warning)
            }
            Button(text("添加主线结果", "Add mainline result"), systemImage: "plus") {
                if let claim = eligible.first(where: { candidate in !steps.contains { $0.claimID == candidate.id } }) {
                    let index = steps.firstIndex { $0.role == .discussion } ?? steps.count
                    steps.insert(ScienceMainlineStep(claimID: claim.id), at: index)
                }
            }.disabled(!eligible.contains { candidate in !steps.contains { $0.claimID == candidate.id } })
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.warning) }
            HStack {
                Spacer(); Button(text("取消", "Cancel")) { dismiss() }
                Button(text("保存主线", "Save mainline")) { error = save(steps); if error == nil { dismiss() } }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 660, height: 680).background(Palette.canvas)
    }
    private func move(_ i: Int, by delta: Int) {
        let target = i + delta
        guard steps.indices.contains(target) else { return }
        steps.swapAt(i, target)
        for affected in Set([i, target, max(i, target) + 1]) where steps.indices.contains(affected) {
            steps[affected].motivation = ""
        }
    }
}
