import AppKit
import PersonalCore
import SwiftUI

private enum ScienceSheet: Identifiable {
    case question(UUID?), claim(UUID?), atom(UUID?), relation(UUID?), evidenceLink(UUID?), mainline, evidenceReason(UUID)
    var id: String {
        switch self {
        case .question(let id): "question-\(id?.uuidString ?? "new")"
        case .claim(let id): "claim-\(id?.uuidString ?? "new")"
        case .atom(let id): "atom-\(id?.uuidString ?? "new")"
        case .relation(let id): "relation-\(id?.uuidString ?? "new")"
        case .evidenceLink(let id): "evidence-link-\(id?.uuidString ?? "new")"
        case .mainline: "mainline"
        case .evidenceReason(let id): "evidence-reason-\(id)"
        }
    }
}

struct ScienceQuestionsView: View {
    let store: PersonalStore
    let discuss: (ScientificQuestion) -> Void
    @State private var selectedID: UUID?
    @State private var sheet: ScienceSheet?
    @State private var search = ""
    @State private var listVisible = true
    @State private var showFocusedMap = false
    @State private var deleteQuestionID: UUID?
    @State private var deleteClaimID: UUID?
    @State private var deleteAtomID: UUID?
    @State private var deleteRelationID: UUID?
    @State private var deleteEvidenceLinkID: UUID?
    @State private var showDeleteConfirmation = false

    private var selected: ScientificQuestion? { store.workspace.scientificQuestions.first { $0.id == selectedID } }
    private func wording(_ chinese: String, _ english: String) -> String { store.assistantText(chinese, english) }
    private var focusWidth: CGFloat { min(1500, max(980, (NSScreen.main?.visibleFrame.width ?? 1360) - 60)) }
    private var focusHeight: CGFloat { min(920, max(630, (NSScreen.main?.visibleFrame.height ?? 800) - 80)) }
    private var questions: [ScientificQuestion] {
        store.workspace.scientificQuestions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        HStack(spacing: 0) {
            if listVisible {
                listPane.frame(width: 268).frame(maxHeight: .infinity)
                Rectangle().fill(Palette.line).frame(width: 0.5)
            }
            if let question = selected {
                ScrollView { detailPane(question).frame(maxWidth: listVisible ? 1100 : 1400, alignment: .leading).padding(.horizontal, 34).padding(.vertical, 30).frame(maxWidth: .infinity) }
                    .scrollIndicators(.hidden).id(question.id)
            } else {
                emptyDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas)
        .onAppear { if selectedID == nil { selectedID = questions.first?.id } }
        .sheet(item: $sheet) { item in
            switch item {
            case .question(let id):
                ScienceQuestionEditor(initial: id.flatMap { target in store.workspace.scientificQuestions.first { $0.id == target } }) { draft in
                    do { try store.saveScientificQuestion(draft); selectedID = draft.id; store.errorMessage = nil; return nil }
                    catch { store.errorMessage = error.localizedDescription; return error.localizedDescription }
                }
            case .claim(let id):
                if let question = selected {
                    ScienceClaimEditor(initial: id.flatMap { target in question.claims.first { $0.id == target } }, experiments: store.workspace.experiments) { claim in
                        updateSelected { question in
                            if let index = question.claims.firstIndex(where: { $0.id == claim.id }) { question.claims[index] = claim }
                            else { question.claims.append(claim) }
                        }
                    }
                }
            case .atom(let id):
                if let question = selected {
                    AtomicExperimentEditor(initial: id.flatMap { target in question.atomicExperiments.first { $0.id == target } },
                        experiments: store.workspace.experiments) { atom in
                        updateSelected { question in
                            if let index = question.atomicExperiments.firstIndex(where: { $0.id == atom.id }) { question.atomicExperiments[index] = atom }
                            else { question.atomicExperiments.append(atom) }
                        }
                    }
                }
            case .relation(let defaultFrom):
                if let question = selected {
                    ScienceRelationEditor(claims: question.claims, defaultFrom: defaultFrom) { relation in
                        updateSelected { $0.relations.append(relation) }
                    }
                }
            case .evidenceLink(let defaultAtom):
                if let question = selected {
                    AtomicEvidenceLinkEditor(atoms: question.atomicExperiments.filter { $0.status == .recorded },
                        claims: question.claims.filter { claim in !question.mainline.contains { $0.claimID == claim.id } }, defaultAtom: defaultAtom) { link in
                        updateSelected { $0.evidenceLinks.append(link) }
                    }
                }
            case .mainline:
                if let question = selected {
                    ScienceMainlineEditor(question: question, language: store.workspace.language) { steps in
                        updateSelected { $0.mainline = steps; $0.graphPositions = [:] }
                    }
                }
            case .evidenceReason(let id):
                if let question = selected {
                    let atomLink = question.evidenceLinks.first { $0.id == id }
                    let claimLink = question.relations.first { $0.id == id }
                    ScienceEvidenceReasonEditor(language: store.workspace.language,
                        explanation: atomLink?.explanation ?? claimLink?.explanation ?? "",
                        limitations: atomLink?.limitations ?? claimLink?.limitations ?? "") { explanation, limitations in
                        updateSelected { q in
                            if let i = q.evidenceLinks.firstIndex(where: { $0.id == id }) {
                                q.evidenceLinks[i].explanation = explanation; q.evidenceLinks[i].limitations = limitations
                            } else if let i = q.relations.firstIndex(where: { $0.id == id }) {
                                q.relations[i].explanation = explanation; q.relations[i].limitations = limitations
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFocusedMap) {
            if let question = selected {
                VStack(spacing: 0) {
                    HStack {
                        Text(store.assistantText("专注图谱", "Focus Map")).font(EditorialType.title(24))
                        Spacer()
                        Button(store.assistantText("完成", "Done")) { showFocusedMap = false }
                            .buttonStyle(QuietButtonStyle())
                    }.padding(20)
                    mindMap(question, canvasHeight: focusHeight - 220).padding(.horizontal, 20).padding(.bottom, 20)
                }.frame(width: focusWidth, height: focusHeight).background(Palette.canvas)
            }
        }
        .confirmationDialog("确认删除？", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) { deleteRequested() }
            Button("取消", role: .cancel) { clearDeleteRequest() }
        } message: { Text("删除后，相关节点与连线会从本机工作区移除。") }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "RESEARCH QUESTIONS")
                    Text("科学问题").font(EditorialType.title(27))
                }
                Spacer()
                Button { sheet = .question(nil) } label: { Image(systemName: "plus").font(.system(size: 15, weight: .medium)) }
                    .buttonStyle(.plain).help("新建科学问题").disabled(store.readOnly)
            }.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 20)
            TextField("搜索问题", text: $search).textFieldStyle(.roundedBorder).padding(.horizontal, 17).padding(.bottom, 13)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(questions) { question in
                        Button { selectedID = question.id } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(question.title).font(.system(size: 13, weight: selectedID == question.id ? .semibold : .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                HStack(spacing: 6) {
                                    Circle().fill(question.status == .resolved ? Palette.success : Palette.accent).frame(width: 5, height: 5)
                                    Text(question.status.title(store.workspace.language))
                                    Text(store.assistantText("· \(question.claims.count) 条论断 · \(question.atomicExperiments.count) 个原子实验", "· \(question.claims.count) claims · \(question.atomicExperiments.count) atomic experiments"))
                                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                                .background(selectedID == question.id ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).foregroundStyle(Palette.ink)
                    }
                    if questions.isEmpty { Text(search.isEmpty ? "还没有科学问题" : "没有匹配的问题").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.top, 28) }
                }.padding(.horizontal, 10).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }.background(Palette.sidebar.opacity(0.55))
    }

    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "questionmark.circle").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(Palette.accent)
            Text("从一个值得追问的问题开始。").font(EditorialType.title(34))
            Text("记录假设与观察，连接支持或反驳它们的证据，保留研究思路的来龙去脉。所有内容只保存在你的本机工作区。")
                .font(.system(size: 13)).lineSpacing(5).foregroundStyle(Palette.muted).frame(maxWidth: 440, alignment: .leading)
            Button("新建科学问题", systemImage: "plus") { sheet = .question(nil) }.buttonStyle(QuietButtonStyle(prominent: true)).disabled(store.readOnly)
        }.frame(maxWidth: 520, alignment: .leading)
    }

    private func detailPane(_ question: ScientificQuestion) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 17) {
                Eyebrow(text: "SCIENTIFIC INQUIRY")
                HStack(alignment: .top, spacing: 20) {
                    Text(question.title).font(EditorialType.title(37)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        ForEach(ScienceQuestionStatus.allCases, id: \.self) { status in Button(status.title(store.workspace.language)) { updateSelected { $0.status = status } } }
                    } label: { StatusPill(title: question.status.title(store.workspace.language), color: question.status == .resolved ? Palette.success : Palette.accent) }
                        .menuStyle(.borderlessButton).fixedSize().disabled(store.readOnly)
                }
                if !question.detail.isEmpty { Text(question.detail).font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(5).textSelection(.enabled) }
                HStack(spacing: 8) {
                    Button("与助手讨论", systemImage: "sparkles") { discuss(question) }.buttonStyle(QuietButtonStyle(prominent: true))
                    Button("编辑问题", systemImage: "square.and.pencil") { sheet = .question(question.id) }.buttonStyle(QuietButtonStyle()).disabled(store.readOnly)
                    Button(wording("整理主线", "Organize mainline"), systemImage: "list.number") { sheet = .mainline }
                        .buttonStyle(QuietButtonStyle()).disabled(store.readOnly)
                    Button(listVisible ? "隐藏问题列表" : "显示问题列表", systemImage: "sidebar.left") {
                        withAnimation(.easeInOut(duration: 0.18)) { listVisible.toggle() }
                    }.buttonStyle(QuietButtonStyle())
                    Button("专注图谱", systemImage: "arrow.up.left.and.arrow.down.right") { showFocusedMap = true }
                        .buttonStyle(QuietButtonStyle())
                    Spacer()
                    Text(wording("更新于 \(LocalDate.string(question.updatedAt, "M月d日"))", "Updated \(LocalDate.string(question.updatedAt, "MMM d"))")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Menu { Button("删除问题", systemImage: "trash", role: .destructive) { deleteQuestionID = question.id; showDeleteConfirmation = true } }
                    label: { Image(systemName: "ellipsis").frame(width: 22) }.menuStyle(.borderlessButton).disabled(store.readOnly)
                }
            }
            ScienceArgumentView(question: question, language: store.workspace.language)
            mindMap(question)
            DisclosureGroup(wording("所有节点与证据（编辑）", "All nodes and evidence (edit)")) {
            VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading("原子实验", count: question.atomicExperiments.count, action: "添加原子实验") { sheet = .atom(nil) }
                if question.atomicExperiments.isEmpty { sectionEmpty("一个实验可以拆成多项可独立解释的检验。先记录方法；得到结果后再连接到论断。") }
                ForEach(question.atomicExperiments) { atom in atomRow(atom, in: question) }
            }
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading("假设、观察与结论", count: question.claims.count, action: "添加论断") { sheet = .claim(nil) }
                if question.claims.isEmpty { sectionEmpty("先记录一个假设、观察或结论。") }
                ForEach(question.claims) { claim in claimRow(claim) }
            }
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading("证据链", count: question.relations.count + question.evidenceLinks.count, action: "连接论断", disabled: question.claims.count < 2) { sheet = .relation(nil) }
                if question.relations.isEmpty && question.evidenceLinks.isEmpty {
                    sectionEmpty("将已记录的原子实验连到论断，再把论断连向更高层结论；连线由你审阅，不自动推断为证明。")
                }
                ForEach(question.evidenceLinks) { link in evidenceLinkRow(link, in: question) }
                ForEach(question.relations) { relation in relationRow(relation, in: question) }
                if question.atomicExperiments.contains(where: { $0.status == .recorded }) && !question.claims.isEmpty {
                    Button("连接原子实验与论断", systemImage: "arrow.triangle.branch") { sheet = .evidenceLink(nil) }
                        .buttonStyle(QuietButtonStyle()).disabled(store.readOnly)
                }
            }
            Text("连线表示人工判断的支持或反驳，不会自动宣称因果或证明。计划实验没有结果，不能作为证据；确信度也不是统计概率。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.bottom, 20)
            }.padding(.top, 16)
            }.tint(Palette.accent)
        }
    }

    private func mindMap(_ question: ScientificQuestion, canvasHeight: CGFloat = 550) -> some View {
        ScienceMindMapView(question: question, language: store.workspace.language, canEdit: !store.readOnly,
            canMoveNodes: !store.readOnly, experimentName: store.experimentName,
            moveNode: { id, point in updateSelected { $0.graphPositions[id.uuidString] = point } == nil },
            resetLayout: { updateSelected { $0.graphPositions = [:] } },
            addClaim: { sheet = .claim(nil) }, addAtom: { sheet = .atom(nil) },
            editQuestion: { sheet = .question(question.id) },
            editClaim: { sheet = .claim($0) }, editAtom: { sheet = .atom($0) },
            linkClaim: { sheet = .relation($0) }, linkAtom: { sheet = .evidenceLink($0) }, canvasHeight: canvasHeight)
    }

    private func claimRow(_ claim: ScienceClaim) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                StatusPill(title: claim.kind.title(store.workspace.language), color: claim.kind == .observation ? Palette.success : Palette.accent)
                Text(store.assistantText("自评确信度 \(Int((claim.confidence * 100).rounded()))%", "Self-rated confidence \(Int((claim.confidence * 100).rounded()))%")) .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("编辑", systemImage: "square.and.pencil") { sheet = .claim(claim.id) }.buttonStyle(.plain).font(.system(size: 11)).disabled(store.readOnly)
                Menu { Button("删除论断", systemImage: "trash", role: .destructive) { deleteClaimID = claim.id; showDeleteConfirmation = true } }
                label: { Image(systemName: "ellipsis").frame(width: 19) }.menuStyle(.borderlessButton).disabled(store.readOnly)
            }
            Text(claim.text).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
            if !claim.sourceNote.isEmpty { Label(claim.sourceNote, systemImage: "text.book.closed").font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled) }
            if !claim.experimentIDs.isEmpty {
                HStack(spacing: 6) { Image(systemName: "flask"); Text(wording("相关实验（不等于证据）：" + claim.experimentIDs.map(store.experimentName).joined(separator: "、"), "Related experiments (not evidence): " + claim.experimentIDs.map(store.experimentName).joined(separator: ", "))) }
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line.opacity(0.7), lineWidth: 0.7))
    }

    private func atomRow(_ atom: AtomicExperiment, in question: ScientificQuestion) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                StatusPill(title: atom.status.title(store.workspace.language), color: atom.status == .recorded ? Palette.success : Palette.muted)
                if let id = atom.experimentID { Text(store.experimentName(id)).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1) }
                Spacer()
                Button("编辑", systemImage: "square.and.pencil") { sheet = .atom(atom.id) }.buttonStyle(.plain).font(.system(size: 11)).disabled(store.readOnly)
                Menu { Button("删除原子实验", systemImage: "trash", role: .destructive) { deleteAtomID = atom.id; showDeleteConfirmation = true } }
                label: { Image(systemName: "ellipsis").frame(width: 19) }.menuStyle(.borderlessButton).disabled(store.readOnly)
            }
            Text(atom.title).font(.system(size: 14, weight: .medium)).textSelection(.enabled)
            if !atom.method.isEmpty { Text(wording("方法：\(atom.method)", "Method: \(atom.method)")).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled) }
            if atom.status == .recorded { Text(wording("观察：\(atom.observedResult)", "Observation: \(atom.observedResult)")).font(.system(size: 12)).textSelection(.enabled) }
            if !atom.sourceNote.isEmpty { Text(wording("出处：\(atom.sourceNote)", "Source: \(atom.sourceNote)")).font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled) }
            if atom.status == .recorded && !question.claims.isEmpty {
                Button("连接到论断", systemImage: "arrow.triangle.branch") { sheet = .evidenceLink(atom.id) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent).disabled(store.readOnly)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line.opacity(0.7), lineWidth: 0.7))
    }

    private func evidenceLinkRow(_ link: AtomicEvidenceLink, in question: ScientificQuestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flask").foregroundStyle(link.kind == .supports ? Palette.success : Palette.warning)
            VStack(alignment: .leading, spacing: 5) {
                Text(question.atomicExperiments.first { $0.id == link.atomicExperimentID }?.title ?? wording("未知原子实验", "Unknown atomic experiment")).lineLimit(2)
                Text((link.kind == .supports ? wording("支持", "Supports") : wording("反驳", "Contradicts")) + " ↓").font(.system(size: 11, weight: .medium)).foregroundStyle(link.kind == .supports ? Palette.success : Palette.warning)
                Text(question.claims.first { $0.id == link.claimID }?.text ?? wording("未知论断", "Unknown claim")).lineLimit(2)
                Text(link.explanation.isEmpty ? wording("论证依据待补充", "Warrant not recorded") : link.explanation).font(.system(size: 11)).foregroundStyle(Palette.muted)
                if !link.limitations.isEmpty { Text(wording("解释边界：", "Inferential boundary: ") + link.limitations).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Button { sheet = .evidenceReason(link.id) } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).disabled(store.readOnly)
                .help(wording("编辑论证依据", "Edit evidence warrant"))
            Menu { Button("删除证据连线", systemImage: "trash", role: .destructive) { deleteEvidenceLinkID = link.id; showDeleteConfirmation = true } }
            label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).disabled(store.readOnly)
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func relationRow(_ relation: ScienceRelation, in question: ScientificQuestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: relation.kind == .supports ? "arrow.up.right" : "arrow.down.right").foregroundStyle(relation.kind == .supports ? Palette.success : Palette.warning)
            VStack(alignment: .leading, spacing: 5) {
                Text(question.claims.first { $0.id == relation.fromClaimID }?.text ?? wording("未知论断", "Unknown claim")).lineLimit(2)
                Text((relation.kind == .supports ? wording("支持", "Supports") : wording("反驳", "Contradicts")) + " ↓").font(.system(size: 11, weight: .medium)).foregroundStyle(relation.kind == .supports ? Palette.success : Palette.warning)
                Text(question.claims.first { $0.id == relation.toClaimID }?.text ?? wording("未知论断", "Unknown claim")).lineLimit(2)
                Text(relation.explanation.isEmpty ? wording("论证依据待补充", "Warrant not recorded") : relation.explanation).font(.system(size: 11)).foregroundStyle(Palette.muted)
                if !relation.limitations.isEmpty { Text(wording("解释边界：", "Inferential boundary: ") + relation.limitations).font(.system(size: 11)).foregroundStyle(Palette.muted) }
            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Button { sheet = .evidenceReason(relation.id) } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).disabled(store.readOnly)
                .help(wording("编辑论证依据", "Edit evidence warrant"))
            Menu { Button("删除关系", systemImage: "trash", role: .destructive) { deleteRelationID = relation.id; showDeleteConfirmation = true } }
            label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).disabled(store.readOnly)
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionHeading(_ title: String, count: Int, action: String, disabled: Bool = false, perform: @escaping () -> Void) -> some View {
        HStack { Text(LocalizedStringKey(title)).font(EditorialType.title(24)); Text("\(count)").font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer(); Button(LocalizedStringKey(action), systemImage: "plus", action: perform).buttonStyle(QuietButtonStyle()).disabled(store.readOnly || disabled) }
    }
    private func sectionEmpty(_ text: String) -> some View { Text(LocalizedStringKey(text)).font(.system(size: 12)).foregroundStyle(Palette.muted).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10)) }
    @discardableResult private func updateSelected(_ change: (inout ScientificQuestion) -> Void) -> String? {
        guard var question = selected else { return "科学问题不存在，请重新选择。" }
        change(&question)
        do { try store.saveScientificQuestion(question); store.errorMessage = nil; return nil }
        catch { store.errorMessage = error.localizedDescription; return error.localizedDescription }
    }
    private func clearDeleteRequest() { deleteQuestionID = nil; deleteClaimID = nil; deleteAtomID = nil; deleteRelationID = nil; deleteEvidenceLinkID = nil }
    private func deleteRequested() {
        if let id = deleteQuestionID {
            do { try store.deleteScientificQuestion(id); selectedID = questions.first?.id; store.errorMessage = nil }
            catch { store.errorMessage = error.localizedDescription }
        } else if let id = deleteClaimID {
            updateSelected { question in
                question.claims.removeAll { $0.id == id }
                question.relations.removeAll { $0.fromClaimID == id || $0.toClaimID == id }
                question.evidenceLinks.removeAll { $0.claimID == id }
                question.graphPositions.removeValue(forKey: id.uuidString)
                question.removeClaimFromMainline(id)
            }
        } else if let id = deleteAtomID {
            updateSelected { question in
                question.atomicExperiments.removeAll { $0.id == id }
                question.evidenceLinks.removeAll { $0.atomicExperimentID == id }
                question.graphPositions.removeValue(forKey: id.uuidString)
            }
        } else if let id = deleteRelationID { updateSelected { $0.relations.removeAll { $0.id == id } } }
        else if let id = deleteEvidenceLinkID { updateSelected { $0.evidenceLinks.removeAll { $0.id == id } } }
        clearDeleteRequest()
    }
}

private struct ScienceQuestionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScientificQuestion
    @State private var errorMessage: String?
    let isNew: Bool
    let save: (ScientificQuestion) -> String?
    init(initial: ScientificQuestion?, save: @escaping (ScientificQuestion) -> String?) {
        _draft = State(initialValue: initial ?? ScientificQuestion(title: "")); isNew = initial == nil; self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isNew ? "新建科学问题" : "编辑科学问题").font(EditorialType.title(28))
            Form {
                TextField("问题标题", text: $draft.title, axis: .vertical).lineLimit(2...3)
                TextField("背景、范围与思路（可选）", text: $draft.detail, axis: .vertical).lineLimit(4...8)
                Picker("状态", selection: $draft.status) { ForEach(ScienceQuestionStatus.allCases, id: \.self) { Text($0.title).tag($0) } }
            }.formStyle(.grouped)
            if let errorMessage { Text(errorMessage).font(.system(size: 11)).foregroundStyle(Palette.warning) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存") { errorMessage = save(draft); if errorMessage == nil { dismiss() } }.keyboardShortcut(.defaultAction).disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(22).frame(width: 540).background(Palette.canvas)
    }
}

private struct ScienceClaimEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScienceClaim
    @State private var errorMessage: String?
    let experiments: [Experiment]
    let save: (ScienceClaim) -> String?
    init(initial: ScienceClaim?, experiments: [Experiment], save: @escaping (ScienceClaim) -> String?) {
        _draft = State(initialValue: initial ?? ScienceClaim(kind: .hypothesis, text: "")); self.experiments = experiments; self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("论断与证据").font(EditorialType.title(28))
            Form {
                Picker("类型", selection: $draft.kind) { ForEach(ScienceClaimKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                TextField("写下假设、观察或结论", text: $draft.text, axis: .vertical).lineLimit(3...6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("自评确信度"); Spacer(); Text("\(Int((draft.confidence * 100).rounded()))%").foregroundStyle(Palette.muted) }
                    Slider(value: $draft.confidence, in: 0...1, step: 0.05)
                    Text("仅表达你的主观判断，不是统计概率。 ").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                TextField("资料出处或备注（可选）", text: $draft.sourceNote, axis: .vertical).lineLimit(2...4)
                if !experiments.isEmpty {
                    Section("相关实验（不等于证据）") {
                        ForEach(experiments) { experiment in
                            Toggle(experiment.name, isOn: Binding(
                                get: { draft.experimentIDs.contains(experiment.id) },
                                set: { selected in
                                    if selected { if !draft.experimentIDs.contains(experiment.id) { draft.experimentIDs.append(experiment.id) } }
                                    else { draft.experimentIDs.removeAll { $0 == experiment.id } }
                                }
                            ))
                        }
                    }
                }
            }.formStyle(.grouped)
            if let errorMessage { Text(errorMessage).font(.system(size: 11)).foregroundStyle(Palette.warning) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存论断") { errorMessage = save(draft); if errorMessage == nil { dismiss() } }.keyboardShortcut(.defaultAction).disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(22).frame(width: 580, height: 590).background(Palette.canvas)
    }
}

private struct ScienceRelationEditor: View {
    @Environment(\.dismiss) private var dismiss
    let claims: [ScienceClaim]
    let save: (ScienceRelation) -> String?
    @State private var errorMessage: String?
    @State private var fromID: UUID
    @State private var toID: UUID
    @State private var kind: ScienceRelationKind = .supports
    @State private var explanation = ""
    @State private var limitations = ""
    init(claims: [ScienceClaim], defaultFrom: UUID?, save: @escaping (ScienceRelation) -> String?) {
        self.claims = claims; self.save = save
        let source = defaultFrom ?? claims.first?.id ?? UUID()
        _fromID = State(initialValue: source); _toID = State(initialValue: claims.first { $0.id != source }?.id ?? UUID())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("连接论断").font(EditorialType.title(28))
            Form {
                Picker("起点", selection: $fromID) { ForEach(claims) { claim in Text(claim.text).lineLimit(1).tag(claim.id) } }
                Picker("关系", selection: $kind) { ForEach(ScienceRelationKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                Picker("终点", selection: $toID) { ForEach(claims) { claim in Text(claim.text).lineLimit(1).tag(claim.id) } }
                TextField("为什么支持或反驳目标结论？", text: $explanation, axis: .vertical).lineLimit(2...5)
                TextField("解释边界 / 尚未排除的解释（可选）", text: $limitations, axis: .vertical).lineLimit(2...4)
            }.formStyle(.grouped)
            if let errorMessage { Text(errorMessage).font(.system(size: 11)).foregroundStyle(Palette.warning) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("添加关系") { errorMessage = save(ScienceRelation(fromClaimID: fromID, toClaimID: toID, kind: kind, explanation: explanation, limitations: limitations)); if errorMessage == nil { dismiss() } }.keyboardShortcut(.defaultAction).disabled(fromID == toID || explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(22).frame(width: 520).background(Palette.canvas)
    }
}

private struct AtomicExperimentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AtomicExperiment
    @State private var errorMessage: String?
    let experiments: [Experiment]
    let save: (AtomicExperiment) -> String?
    init(initial: AtomicExperiment?, experiments: [Experiment], save: @escaping (AtomicExperiment) -> String?) {
        _draft = State(initialValue: initial ?? AtomicExperiment(title: "")); self.experiments = experiments; self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("原子实验").font(EditorialType.title(28))
            Text("把一次能独立回答问题的检验记为一个节点；Protocol 操作步骤与尚未执行的安排不是观察证据。")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Form {
                TextField("实验名称", text: $draft.title, axis: .vertical).lineLimit(2...3)
                TextField("方法 / 比较条件（可选）", text: $draft.method, axis: .vertical).lineLimit(2...5)
                Picker("进度", selection: $draft.status) {
                    ForEach(AtomicExperimentStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if draft.status == .recorded {
                    TextField("实际观察结果（必填）", text: $draft.observedResult, axis: .vertical).lineLimit(3...7)
                    DatePicker("记录日期", selection: $draft.recordedAt, displayedComponents: .date)
                }
                Picker("所属本机实验", selection: $draft.experimentID) {
                    Text("未关联").tag(UUID?.none)
                    ForEach(experiments) { experiment in Text(experiment.name).tag(Optional(experiment.id)) }
                }
                TextField("原始记录出处 / 笔记位置", text: $draft.sourceNote, axis: .vertical).lineLimit(2...4)
            }.formStyle(.grouped)
            if draft.status == .recorded && draft.experimentID == nil {
                Text("未关联本机实验时，请写明可追溯的原始记录出处。 ").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            if let errorMessage { Text(errorMessage).font(.system(size: 11)).foregroundStyle(Palette.warning) }
            HStack {
                Spacer(); Button("取消") { dismiss() }
                Button("保存原子实验") { errorMessage = save(draft); if errorMessage == nil { dismiss() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (draft.status == .recorded && draft.observedResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(22).frame(width: 600, height: 620).background(Palette.canvas)
            .onChange(of: draft.status) { _, status in if status == .planned { draft.observedResult = "" } }
    }
}

private struct AtomicEvidenceLinkEditor: View {
    @Environment(\.dismiss) private var dismiss
    let atoms: [AtomicExperiment]
    let claims: [ScienceClaim]
    let save: (AtomicEvidenceLink) -> String?
    @State private var atomID: UUID
    @State private var claimID: UUID
    @State private var kind: ScienceRelationKind = .supports
    @State private var explanation = ""
    @State private var limitations = ""
    @State private var errorMessage: String?
    init(atoms: [AtomicExperiment], claims: [ScienceClaim], defaultAtom: UUID?, save: @escaping (AtomicEvidenceLink) -> String?) {
        self.atoms = atoms; self.claims = claims; self.save = save
        _atomID = State(initialValue: defaultAtom ?? atoms.first?.id ?? UUID())
        _claimID = State(initialValue: claims.first?.id ?? UUID())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("连接实验证据").font(EditorialType.title(28))
            Text("连线是你的研究判断，不会自动把相关性写成因果或证明。")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            Form {
                Picker("已有结果的原子实验", selection: $atomID) {
                    ForEach(atoms) { atom in Text(atom.title).lineLimit(1).tag(atom.id) }
                }
                Picker("关系", selection: $kind) {
                    ForEach(ScienceRelationKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("指向论断", selection: $claimID) {
                    ForEach(claims) { claim in Text(claim.text).lineLimit(1).tag(claim.id) }
                }
                TextField("比较、观察如何支持或反驳这个下层结论？", text: $explanation, axis: .vertical).lineLimit(2...5)
                TextField("解释边界 / 尚未排除的解释（可选）", text: $limitations, axis: .vertical).lineLimit(2...4)
            }.formStyle(.grouped)
            if let errorMessage { Text(errorMessage).font(.system(size: 11)).foregroundStyle(Palette.warning) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("添加连线") {
                errorMessage = save(AtomicEvidenceLink(atomicExperimentID: atomID, claimID: claimID, kind: kind, explanation: explanation, limitations: limitations))
                if errorMessage == nil { dismiss() }
            }.keyboardShortcut(.defaultAction).disabled(atoms.isEmpty || claims.isEmpty || explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(22).frame(width: 550).background(Palette.canvas)
    }
}

private struct ScienceEvidenceReasonEditor: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    let save: (String, String) -> String?
    @State private var explanation: String
    @State private var limitations: String
    @State private var error: String?
    init(language: AppLanguage, explanation: String, limitations: String, save: @escaping (String, String) -> String?) {
        self.language = language; self.save = save
        _explanation = State(initialValue: explanation); _limitations = State(initialValue: limitations)
    }
    private func text(_ zh: String, _ en: String) -> String { language == .english ? en : zh }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text("解释证据如何支撑结论", "Explain the evidence warrant")).font(EditorialType.title(24))
            TextField(text("比较与观察是什么，为什么支持或反驳目标？", "What comparison and observation support or challenge the target, and why?"), text: $explanation, axis: .vertical).lineLimit(4...8)
            TextField(text("不能据此证明什么？（可选）", "What cannot be established from this evidence? (optional)"), text: $limitations, axis: .vertical).lineLimit(3...5)
            if let error { Text(error).foregroundStyle(Palette.warning) }
            HStack {
                Spacer(); Button(text("取消", "Cancel")) { dismiss() }
                Button(text("保存", "Save")) { error = save(explanation, limitations); if error == nil { dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled(explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 600).background(Palette.canvas)
    }
}
