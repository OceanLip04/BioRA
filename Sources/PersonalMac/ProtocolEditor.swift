import AppKit
import PersonalCore
import SwiftUI
import UniformTypeIdentifiers

struct ProcedureEditor: View {
    let store: PersonalStore
    let initial: Procedure
    var artifactID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String; @State private var note: String
    @State private var content: ProtocolContent; @State private var versionID: UUID
    @State private var published = true; @State private var error: String?
    init(store: PersonalStore, initial: Procedure, artifactID: UUID? = nil) {
        self.store = store; self.initial = initial; self.artifactID = artifactID
        let version = initial.versions.max { $0.number < $1.number }!
        _name = State(initialValue: initial.name); _note = State(initialValue: initial.note)
        _content = State(initialValue: version.content); _versionID = State(initialValue: version.id)
        _published = State(initialValue: artifactID == nil && version.status == .published)
    }
    var body: some View {
        EditorShell(title: "整理你的 Protocol", subtitle: "目的 · 材料 · 三层步骤 · 原理 · 注意事项 · 每次保存保留独立版本。", error: error, saveTitle: published ? "保存并确认版本" : "保存草稿", width: 850, save: save) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Protocol 名称", text: $name).font(.title3).textFieldStyle(.roundedBorder)
                    TextField("说明", text: $note).textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("声明总耗时（分钟，0 为未知）", value: $content.estimatedTotalDurationMinutes, format: .number).textFieldStyle(.roundedBorder).frame(width: 260)
                        TextField("Protocol 总设备清单（逗号分隔）", text: Binding(get: { content.equipmentNeeded.joined(separator: ", ") }, set: { content.equipmentNeeded = $0.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } })).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Picker("查看版本", selection: $versionID) { ForEach(initial.versions) { v in Text("v\(v.number) · \(v.status == .published ? "已确认" : "草稿")").tag(v.id) } }.frame(width: 220)
                        Toggle("确认为可用版本", isOn: $published)
                        Spacer(); Button("导入 V3 JSON", action: importContent); Button("导出 JSON", action: exportContent)
                    }
                    if initial.versions.count > 1 { Text("历史版本均保留；选择某个版本后编辑，将另存为新版本。").font(.caption).foregroundStyle(Palette.muted) }
                    Divider().padding(.vertical, 8)
                    ProtocolPartHeading(number: "01", title: "实验目的")
                    TextField("研究对象与实验目标", text: $content.objective, axis: .vertical).lineLimit(3...7).textFieldStyle(.roundedBorder)
                    ProtocolMaterialsEditor(materials: $content.materials)
                    Divider().padding(.vertical, 8)
                    ProtocolPartHeading(number: "03", title: "实验步骤")
                    ProtocolTreeEditor(content: $content, instruments: store.workspace.instruments)
                    ProtocolBulletEditor(number: "04", title: "实验原理", items: $content.principles)
                    ProtocolBulletEditor(number: "05", title: "注意事项", items: $content.precautions)
                    Text("\(content.blocks.count) 个阶段 · \(content.atomicSteps.count) 个原子操作 · 未知耗时 \(content.atomicSteps.filter { $0.durationMinutes == 0 }.count) 项").font(.caption).foregroundStyle(Palette.muted)
                    let old = initial.currentVersion.content.atomicSteps
                    let new = content.atomicSteps
                    Text("本次步骤变更：新增 \(new.filter { n in !old.contains { $0.id == n.id } }.count) · 移除 \(old.filter { o in !new.contains { $0.id == o.id } }.count) · 修改 \(new.filter { n in old.contains { $0.id == n.id && $0 != n } }.count)")
                        .font(.caption).foregroundStyle(Palette.green)
                }.padding(22)
            }.frame(height: 540)
        }.onChange(of: versionID) { _, id in if let v = initial.versions.first(where: { $0.id == id }) { content = v.content } }
    }
    private func save() {
        do {
            content.renumber(); try content.validated()
            if let artifactID {
                try store.commit { workspace in
                    guard let i = workspace.artifacts.firstIndex(where: { $0.id == artifactID }), workspace.artifacts[i].appliedID == nil else { throw WorkspaceError.invalid("草稿已应用或不存在。") }
                    workspace.artifacts[i].procedure?.name = name.trimmingCharacters(in: .whitespacesAndNewlines); workspace.artifacts[i].procedure?.note = note
                    let oldVersion = workspace.artifacts[i].procedure?.currentVersion
                    var version = ProcedureVersion(status: .draft, content: content)
                    // An unreviewed draft is mutable; keep its ID and preparation checklist until it is saved.
                    if let oldVersion { version.id = oldVersion.id; version.createdAt = oldVersion.createdAt }
                    workspace.artifacts[i].procedure?.versions = [version]
                    if let checks = workspace.materialPreparation[version.id.uuidString] {
                        workspace.materialPreparation[version.id.uuidString] = checks.filter { id in
                            content.materials.contains { material in material.id == id && oldVersion?.content.materials.contains(material) == true }
                        }
                    }
                }
                try store.saveProtocolArtifact(artifactID, published: published); dismiss(); return
            }
            var value = initial; value.name = name.trimmingCharacters(in: .whitespacesAndNewlines); value.note = note
            let exists = store.workspace.procedures.contains { $0.id == initial.id }
            let number = exists ? (initial.versions.map(\.number).max() ?? 0) + 1 : 1
            let version = ProcedureVersion(number: number, status: published ? .published : .draft, content: content)
            if exists { value.versions.append(version) } else { value.versions = [version] }
            try store.saveProcedure(value); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func importContent() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { do { content = try ProtocolExchange.read(url) } catch { self.error = error.localizedDescription } }
    }
    private func exportContent() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "protocol-v3.json"
        if panel.runModal() == .OK, let url = panel.url { do { var value = content; value.renumber(); try value.validated(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(value).write(to: url, options: .atomic) } catch { self.error = error.localizedDescription } }
    }
}

struct ProtocolTreeEditor: View {
    @Binding var content: ProtocolContent
    let instruments: [Instrument]
    @State private var collapsedBlocks: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach($content.blocks) { $block in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("阶段 \(block.order)", systemImage: "square.stack.3d.up").font(.headline).draggable("block/" + block.id)
                        Button(collapsedBlocks.contains(block.id) ? "展开阶段" : "折叠阶段") { if !collapsedBlocks.insert(block.id).inserted { collapsedBlocks.remove(block.id) } }
                        Spacer(); Button("上移") { moveBlock(block.id) }; Button("移除阶段") { content.blocks.removeAll { $0.id == block.id } }
                    }
                    if !collapsedBlocks.contains(block.id) {
                    TextField("阶段名称", text: $block.title).textFieldStyle(.roundedBorder)
                    TextField("阶段描述", text: $block.description).textFieldStyle(.roundedBorder)
                    LoopEditor(kind: $block.kind, loop: $block.loop)
                    ForEach($block.subblocks) { $group in
                        GroupEditor(group: $group, instruments: instruments, remove: { block.subblocks.removeAll { $0.id == group.id } }, move: { if let i = block.subblocks.firstIndex(where: { $0.id == group.id }), i > 0 { block.subblocks.swapAt(i, i - 1) } }, drop: { payload, before in
                            if payload.hasPrefix("step/") { return content.moveStep(String(payload.dropFirst(5)), toGroup: group.id, before: before) }
                            if payload.hasPrefix("group/") { return content.moveGroup(String(payload.dropFirst(6)), toBlock: block.id, before: group.id) }
                            return false
                        })
                    }
                    Button("添加动作分组", systemImage: "plus") { block.subblocks.append(ProtocolSubblock(title: "新分组", steps: [ProtocolStep(title: "新操作")])) }
                    }
                }.padding(16).background(Palette.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
                    .dropDestination(for: String.self) { values, _ in
                        guard let payload = values.first else { return false }
                        if payload.hasPrefix("group/") { return content.moveGroup(String(payload.dropFirst(6)), toBlock: block.id) }
                        guard payload.hasPrefix("block/"), let from = content.blocks.firstIndex(where: { $0.id == String(payload.dropFirst(6)) }), let to = content.blocks.firstIndex(where: { $0.id == block.id }) else { return false }
                        let moved = content.blocks.remove(at: from); content.blocks.insert(moved, at: min(to, content.blocks.count)); content.renumber(); return true
                    }
            }
            Button("添加主要阶段", systemImage: "plus.rectangle.on.rectangle") { content.blocks.append(ProtocolBlock(title: "新阶段", subblocks: [ProtocolSubblock(title: "新分组", steps: [ProtocolStep(title: "新操作")])])) }
        }.buttonStyle(.borderless)
    }
    private func moveBlock(_ id: String) { if let i = content.blocks.firstIndex(where: { $0.id == id }), i > 0 { content.blocks.swapAt(i, i - 1); content.renumber() } }
}
private struct GroupEditor: View {
    @Binding var group: ProtocolSubblock
    let instruments: [Instrument]; let remove: () -> Void; let move: () -> Void
    let drop: (String, String?) -> Bool
    @State private var expanded = true
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("分组名称", text: $group.title).textFieldStyle(.roundedBorder)
                TextField("分组描述", text: $group.description).textFieldStyle(.roundedBorder)
                LoopEditor(kind: $group.kind, loop: $group.loop)
                ForEach($group.steps) { $step in
                    StepEditor(step: $step, instruments: instruments, remove: { group.steps.removeAll { $0.id == step.id } }, move: { if let i = group.steps.firstIndex(where: { $0.id == step.id }), i > 0 { group.steps.swapAt(i, i - 1) } })
                        .dropDestination(for: String.self) { values, _ in values.first.map { drop($0, step.id) } ?? false }
                }
                Button("添加原子操作", systemImage: "plus") { group.steps.append(ProtocolStep(title: "新操作")) }
            }.padding(.top, 10)
        } label: {
            HStack { Label(group.title, systemImage: "rectangle.3.group").fontWeight(.medium).draggable("group/" + group.id); Spacer(); Button("上移", action: move); Button("移除分组", action: remove) }
        }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 9))
            .dropDestination(for: String.self) { values, _ in values.first.map { drop($0, nil) } ?? false }
    }
}
private struct StepEditor: View {
    @Binding var step: ProtocolStep
    let instruments: [Instrument]; let remove: () -> Void; let move: () -> Void
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 11) {
                TextField("操作名称", text: $step.title).textFieldStyle(.roundedBorder)
                TextField("详细操作描述", text: $step.description, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                HStack { Stepper("\(step.durationMinutes) 分钟（0 表示未知）", value: $step.durationMinutes, in: 0...7200); Spacer(); Picker("本机仪器", selection: $step.instrumentID) { Text("无指定仪器").tag(nil as UUID?); ForEach(instruments) { Text($0.name).tag(Optional($0.id)) } }.frame(width: 250) }
                HStack { Toggle("可暂停", isOn: $step.canPause); Toggle("必须连续", isOn: $step.requiresContinuous); Toggle("过夜安全", isOn: $step.overnightSafe) }
                Toggle("无需本人持续在场（等待 / 无人值守）", isOn: $step.unattended)
                TextField("试剂，以逗号分隔", text: strings($step.reagents)).textFieldStyle(.roundedBorder)
                TextField("设备名称，以逗号分隔", text: strings($step.equipmentNeeded)).textFieldStyle(.roundedBorder)
                TextField("备注", text: $step.notes, axis: .vertical).textFieldStyle(.roundedBorder)
            }.padding(.top, 10)
        } label: {
            HStack { Text(step.title.isEmpty ? "未命名操作" : step.title).draggable("step/" + step.id); Spacer(); Text("\(step.durationMinutes) 分钟").foregroundStyle(Palette.muted); Button("上移", action: move); Button("移除", action: remove) }.font(.system(size: 12))
        }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: step.canPause) { _, value in if value { step.requiresContinuous = false } }
            .onChange(of: step.requiresContinuous) { _, value in if value { step.canPause = false } }
    }
    private func strings(_ values: Binding<[String]>) -> Binding<String> { Binding(get: { values.wrappedValue.joined(separator: ", ") }, set: { values.wrappedValue = $0.components(separatedBy: CharacterSet(charactersIn: ",，\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }) }
}
private struct LoopEditor: View {
    @Binding var kind: String; @Binding var loop: ProtocolLoop?
    var body: some View {
        HStack {
            Toggle("循环", isOn: Binding(get: { kind == "loop" }, set: { kind = $0 ? "loop" : "section"; loop = $0 ? ProtocolLoop() : nil })).frame(width: 90)
            if kind == "loop" {
                Picker("方式", selection: Binding(get: { loop?.type ?? "count" }, set: { loop?.type = $0 })) { Text("指定次数").tag("count"); Text("直到条件").tag("until") }.frame(width: 180)
                if loop?.type == "until" { TextField("终止条件", text: Binding(get: { loop?.until ?? "" }, set: { loop?.until = $0 })).textFieldStyle(.roundedBorder) }
                else { Stepper("\(loop?.count ?? 1) 次", value: Binding(get: { loop?.count ?? 1 }, set: { loop?.count = $0 }), in: 1...100) }
            }
        }.font(.system(size: 12))
    }
}
