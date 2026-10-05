import PersonalCore
import SwiftUI

/// The document surround is separate from the executable three-level operation tree.
struct ProtocolDocumentView: View {
    let store: PersonalStore
    let version: ProcedureVersion
    @State private var error: String?
    private var content: ProtocolContent { version.content }
    private var prepared: Set<String> { Set(store.workspace.materialPreparation[version.id.uuidString] ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                ProtocolPartHeading(number: "01", title: "实验目的")
                documentText(content.objective, empty: "尚未填写实验目的。")
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ProtocolPartHeading(number: "02", title: "实验材料")
                    Spacer()
                    Text("\(content.materials.filter { prepared.contains($0.id) }.count) / \(content.materials.count) 已备齐")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                if content.materials.isEmpty { documentText("", empty: "尚未填写材料清单。") }
                else { materialsTable }
                Text("勾选仅记录此版本的准备状态，不代表实验已完成，也不影响排程。")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 12) {
                ProtocolPartHeading(number: "03", title: "实验步骤")
                ProtocolTreePreview(content: content)
                ProtocolTimingPanel(store: store, version: version)
            }
            VStack(alignment: .leading, spacing: 12) {
                ProtocolPartHeading(number: "04", title: "实验原理")
                itemList(content.principles, empty: "尚未填写实验原理。", warning: false)
            }
            VStack(alignment: .leading, spacing: 12) {
                ProtocolPartHeading(number: "05", title: "注意事项")
                itemList(content.precautions, empty: "尚未填写注意事项；这不表示没有实验风险。", warning: true)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var materialsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("材料 / 规格").frame(maxWidth: .infinity, alignment: .leading)
                Text("用量").frame(width: 78, alignment: .leading)
                Text("备齐").frame(width: 40)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                .padding(12).background(Palette.canvas)
            ForEach(content.materials) { material in
                Divider().overlay(Palette.line)
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(material.name).font(.system(size: 13, weight: .medium))
                        Text([material.category.title, material.specification].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        if !material.notes.isEmpty { Text(material.notes).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(material.quantity.isEmpty ? "待确认" : material.quantity).font(.system(size: 12))
                        .frame(width: 78, alignment: .leading)
                    Toggle("已备齐：\(material.name)", isOn: Binding(get: { prepared.contains(material.id) }, set: { value in
                        do { try store.setMaterialPrepared(material.id, versionID: version.id, prepared: value); error = nil }
                        catch { self.error = error.localizedDescription }
                    })).toggleStyle(.checkbox).labelsHidden().frame(width: 40).disabled(store.readOnly)
                }.fixedSize(horizontal: false, vertical: true).padding(12)
            }
        }.background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line, lineWidth: 0.7))
    }
    private func documentText(_ text: String, empty: String) -> some View {
        Text(text.isEmpty ? empty : text).font(.system(size: 13)).foregroundStyle(text.isEmpty ? Palette.muted : Palette.ink)
            .lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
    private func itemList(_ items: [String], empty: String, warning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty { documentText("", empty: empty) }
            ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 10) {
                    Text(warning ? "•" : String(format: "%02d", index + 1))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(warning ? Palette.warning : Palette.accent).frame(width: 20).padding(.top, 2)
                    documentText(text, empty: "")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(warning ? 14 : 0)
            .background(warning ? Palette.warning.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct ProtocolPartHeading: View {
    let number: String
    let title: String
    var body: some View {
        HStack(spacing: 9) {
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.accent)
            Text(title).font(EditorialType.title(20)).foregroundStyle(Palette.ink)
        }
    }
}

struct ProtocolMaterialsEditor: View {
    @Binding var materials: [ProtocolMaterial]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProtocolPartHeading(number: "02", title: "实验材料")
            Text("只列物品、规格和用量；配制、称量等实际操作写入下方实验步骤。")
                .font(.caption).foregroundStyle(Palette.muted)
            ForEach($materials) { $material in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        TextField("材料名称", text: $material.name)
                        Picker("类别", selection: $material.category) {
                            ForEach(MaterialCategory.allCases, id: \.self) { category in Text(category.title).tag(category) }
                        }.labelsHidden().frame(width: 105)
                        Button("移除") { materials.removeAll { $0.id == material.id } }.buttonStyle(.borderless)
                    }
                    HStack { TextField("规格 / 浓度（未知填待确认）", text: $material.specification); TextField("用量 / 数量", text: $material.quantity) }
                    TextField("备注", text: $material.notes, axis: .vertical).lineLimit(1...3)
                }.textFieldStyle(.roundedBorder).padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 9))
            }
            Button("添加材料", systemImage: "plus") { materials.append(ProtocolMaterial(name: "")) }.buttonStyle(.borderless)
        }
    }
}

struct ProtocolBulletEditor: View {
    let number: String
    let title: String
    @Binding var items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProtocolPartHeading(number: number, title: title)
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top) {
                    Text("\(index + 1).").font(.caption).foregroundStyle(Palette.muted).padding(.top, 7)
                    TextField("填写一条\(title)", text: $items[index], axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                    Button("移除") { items.remove(at: index) }.buttonStyle(.borderless).padding(.top, 5)
                }
            }
            Button("添加一条\(title)", systemImage: "plus") { items.append("") }.buttonStyle(.borderless)
        }
    }
}
