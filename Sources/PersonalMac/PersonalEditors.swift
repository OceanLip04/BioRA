import PersonalCore
import SwiftUI

struct BusyEditor: View {
    let store: PersonalStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var start = Date(); @State private var end = Date().addingTimeInterval(3600)
    @State private var instrumentID: UUID?; @State private var error: String?
    var body: some View {
        EditorShell(title: "忙碌时间 / 仪器占用", subtitle: "个人忙碌阻止需要本人操作的步骤；仪器占用阻止使用该仪器的所有步骤。", error: error, save: save) {
            VStack(spacing: 16) {
                TextField("标题", text: $title).textFieldStyle(.roundedBorder)
                DatePicker("开始", selection: $start); DatePicker("结束", selection: $end)
                Picker("占用对象", selection: $instrumentID) { Text("我本人").tag(UUID?.none); ForEach(store.workspace.instruments) { Text($0.name).tag(Optional($0.id)) } }
            }.padding(24)
        }
    }
    private func save() { do { try store.saveBusy(BusyInterval(title: title, start: start, end: end, instrumentID: instrumentID)); dismiss() } catch { self.error = error.localizedDescription } }
}
struct ExperimentNotesEditor: View {
    let store: PersonalStore; let experiment: Experiment
    var body: some View {
        ExperimentTimingEditor(store: store, experiment: experiment)
    }
}
struct PreferencesSettings: View {
    let store: PersonalStore
    @State private var preferences = SchedulePreferences(); @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("默认排程偏好").font(.headline)
            SchedulePreferencesEditor(preferences: $preferences)
            Button("保存排程偏好") { do { try store.savePreferences(preferences); message = "已保存" } catch { message = error.localizedDescription } }.disabled(store.readOnly)
            if let message { Text(message).font(.caption) }
        }.padding(24).card().onAppear { preferences = store.workspace.preferences }
    }
}
