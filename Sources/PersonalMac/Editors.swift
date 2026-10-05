import PersonalCore
import SwiftUI

struct InstrumentEditor: View {
    let store: PersonalStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Instrument; @State private var error: String?
    init(store: PersonalStore, initial: Instrument) { self.store = store; _draft = State(initialValue: initial) }
    var body: some View {
        EditorShell(title: "仪器资料", subtitle: "记录自己能够使用的仪器。", error: error, save: save) {
            Form { TextField("仪器名称", text: $draft.name); TextField("位置", text: $draft.location); TextField("备注", text: $draft.note, axis: .vertical); Toggle("可用于个人安排", isOn: $draft.available) }.formStyle(.grouped)
        }
    }
    private func save() { do { draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines); try store.saveInstrument(draft); dismiss() } catch { self.error = error.localizedDescription } }
}
struct ExperimentEditor: View {
    let store: PersonalStore
    var initialProcedureID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var procedureID: UUID?; @State private var date = Date(); @State private var error: String?
    @State private var sampleCount = 1
    var body: some View {
        EditorShell(title: "安排一个实验", subtitle: "使用已确认的 Protocol 版本生成个人安排。", error: error, saveTitle: "创建并排程", save: save) {
            Form {
                TextField("实验名称", text: $name)
                Picker("Protocol", selection: $procedureID) {
                    Text("请选择").tag(nil as UUID?)
                    ForEach(store.workspace.procedures.filter { $0.currentVersion.status == .published }) { p in Text("\(p.name) · v\(p.currentVersion.number)").tag(Optional(p.id)) }
                }
                DatePicker("希望开始", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Stepper(store.assistantText("样品数：\(sampleCount)", "Sample count: \(sampleCount)"), value: $sampleCount, in: 1...100_000)
                TextField(store.assistantText("样品数", "Sample count"), value: $sampleCount, format: .number)
                if let procedure = store.workspace.procedures.first(where: { $0.id == procedureID }) {
                    TimingEstimateSummary(store: store, procedure: procedure, sampleCount: sampleCount)
                }
                Text("遵循本机工作时间、个人日历、仪器占用和步骤的连续、暂停及过夜条件。工作时间可在排程面板调整。").font(.caption).foregroundStyle(Palette.muted)
            }.formStyle(.grouped)
        }.onAppear {
            procedureID = initialProcedureID ?? store.workspace.procedures.first { $0.currentVersion.status == .published }?.id
            if let p = store.workspace.procedures.first(where: { $0.id == procedureID }) { name = p.name + store.assistantText(" · 实验", " · Experiment") }
        }
    }
    private func save() { do { guard let procedureID else { throw WorkspaceError.invalid("请先确认一个 Protocol 版本。") }; try store.addExperiment(name: name, procedureID: procedureID, date: date, sampleCount: sampleCount); dismiss() } catch { self.error = error.localizedDescription } }
}
struct EditorShell<Content: View>: View {
    let title: String; let subtitle: String; let error: String?
    var saveTitle = "保存"; var width: CGFloat = 620
    let save: () -> Void; @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) { Text(LocalizedStringKey(title)).font(EditorialType.title(29)); Text(LocalizedStringKey(subtitle)).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4) }.padding(26)
            Divider(); content()
            if let error { Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 12) }
            Divider(); HStack { Spacer(); Button("取消") { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction); Button(LocalizedStringKey(saveTitle), action: save).buttonStyle(QuietButtonStyle(prominent: true)).keyboardShortcut(.defaultAction) }.padding(20)
        }.frame(width: width).background(Palette.canvas).foregroundStyle(Palette.ink).tint(Palette.accent)
    }
}
