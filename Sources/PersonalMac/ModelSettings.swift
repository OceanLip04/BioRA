import PersonalCore
import SwiftUI

struct AssistantSettingsView: View {
    let store: PersonalStore
    @State private var editingConnection: ProviderConnection?
    @State private var editingModel: ModelProfile?
    @State private var routing = ModelRouting()
    @State private var notice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 6) { Text("你的模型连接").font(EditorialType.title(25)); Text("一个服务连接，可以配置多个模型。").font(.system(size: 12)).foregroundStyle(Palette.muted) }; Spacer(); Button("添加连接", systemImage: "plus") { editingConnection = ProviderConnection() }.buttonStyle(QuietButtonStyle()) }
            ForEach(store.workspace.connections) { connection in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(connection.name).fontWeight(.medium); Text(connection.baseURL).font(.caption).foregroundStyle(Palette.muted).textSelection(.enabled) }
                    Spacer(); Text(store.assistantText(connection.isLocal ? "本地" : "云端", connection.isLocal ? "Local" : "Cloud")).font(.caption).foregroundStyle(Palette.green)
                    Button("编辑连接 / Key") { editingConnection = connection }.buttonStyle(QuietButtonStyle())
                }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            HStack { Text("模型目录").font(EditorialType.title(25)); Spacer(); Button("添加模型", systemImage: "plus") { if let connection = store.workspace.connections.first { editingModel = ModelProfile(connectionID: connection.id) } }.buttonStyle(QuietButtonStyle()).disabled(store.workspace.connections.isEmpty) }
            ForEach(store.workspace.models) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(store.displayModelName(model.name)).fontWeight(.medium); Text((store.workspace.connections.first { $0.id == model.connectionID }?.name ?? "") + " · " + model.model).font(.caption).foregroundStyle(Palette.muted) }
                    Spacer(); if store.workspace.routing.assistant == model.id { StatusPill(title: store.assistantText("默认助手", "Default assistant")) }
                    Button("编辑") { editingModel = model }.buttonStyle(QuietButtonStyle())
                    Button("移除") { do { try store.deleteModel(model.id); routing = store.workspace.routing } catch { notice = error.localizedDescription } }.foregroundStyle(.red)
                }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
            }
            Divider(); Text("为任务选择默认模型").font(EditorialType.title(25))
            HStack { modelPicker("Assistant", $routing.assistant); modelPicker(store.assistantText("Protocol 构建", "Protocol Builder"), $routing.protocolBuilder) }
            HStack { modelPicker(store.assistantText("排程任务", "Scheduling"), $routing.scheduling); modelPicker(store.assistantText("实验总结", "Experiment Summary"), $routing.report) }
            HStack { Button("保存默认模型") { do { try store.saveRouting(routing); notice = store.assistantText("默认模型已保存。", "Default models saved.") } catch { notice = error.localizedDescription } }.buttonStyle(QuietButtonStyle(prominent: true)); if let notice { Text(notice).font(.caption).foregroundStyle(Palette.muted) } }
            Text("问题与任务所需数据会发送到所选连接。API Key 放 macOS 钥匙串，各连接独立保存；本地兼容接口可不填 Key。")
                .font(.caption).foregroundStyle(Palette.muted)
        }.padding(22).card().disabled(store.readOnly || store.runningRunID != nil)
            .onAppear { routing = store.workspace.routing }
            .sheet(item: $editingConnection) { ConnectionEditor(store: store, initial: $0) }
            .sheet(item: $editingModel) { ModelEditor(store: store, initial: $0) }
    }
    private func modelPicker(_ title: String, _ value: Binding<UUID?>) -> some View {
        Picker(LocalizedStringKey(title), selection: value) { Text("跟随 Assistant 默认").tag(nil as UUID?); ForEach(store.workspace.models) { Text(store.displayModelName($0.name)).tag(Optional($0.id)) } }.frame(maxWidth: .infinity)
    }
}
private struct ConnectionEditor: View {
    let store: PersonalStore
    @Environment(\.dismiss) private var dismiss
    @State private var connection: ProviderConnection; @State private var key = ""; @State private var hasKey = false; @State private var error: String?
    init(store: PersonalStore, initial: ProviderConnection) { self.store = store; _connection = State(initialValue: initial) }
    var body: some View {
        EditorShell(title: "模型连接", subtitle: "一个连接可添加多个模型，每个连接使用自己的 API Key。", error: error, save: save) {
            Form {
                TextField("显示名称", text: $connection.name)
                TextField("兼容 API 地址", text: $connection.baseURL)
                HStack {
                    Button("OpenAI") { preset("OpenAI", "https://api.openai.com/v1") }
                    Button("DeepSeek") { preset("DeepSeek", "https://api.deepseek.com/v1") }
                    Button("OpenRouter") { preset("OpenRouter", "https://openrouter.ai/api/v1") }
                    Button("LM Studio") { preset("LM Studio", "http://localhost:1234/v1") }
                    Button("Ollama") { preset("Ollama", "http://localhost:11434/v1") }
                }.buttonStyle(.borderless)
                SecureField(hasKey ? "已保存 Key；输入新 Key 替换" : "API Key（本地可留空）", text: $key)
                if hasKey { Button("移除此连接的 Key", role: .destructive, action: removeKey) }
                Text("协议：OpenAI-compatible Chat Completions。地址可填写 /v1 或完整 /chat/completions。") .font(.caption).foregroundStyle(Palette.muted)
            }.formStyle(.grouped)
        }.onAppear { hasKey = (try? store.apiKey(connection)) != nil }
    }
    private func preset(_ name: String, _ url: String) { connection.name = name; connection.baseURL = url }
    private func save() {
        do {
            connection.name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines); connection.baseURL = connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            try connection.validated(); try store.saveConnection(connection)
            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { try AssistantKeychain().save(value, account: store.keyAccount(connection)); key = "" }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func removeKey() {
        do {
            try AssistantKeychain().delete(account: store.keyAccount(connection))
            if connection.legacyKey { try AssistantKeychain().delete(account: store.file.directory.standardizedFileURL.path); connection.legacyKey = false; try store.saveConnection(connection) }
            hasKey = false; key = ""
        } catch { self.error = error.localizedDescription }
    }
}
private struct ModelEditor: View {
    let store: PersonalStore
    @Environment(\.dismiss) private var dismiss
    @State private var model: ModelProfile; @State private var error: String?; @State private var discovered: [String] = []; @State private var discovering = false
    init(store: PersonalStore, initial: ModelProfile) { self.store = store; _model = State(initialValue: initial) }
    var body: some View {
        EditorShell(title: "模型资料", subtitle: "添加多个模型；每次任务可选择模型或跟随用途默认值。", error: error, save: save) {
            Form {
                Picker("连接", selection: $model.connectionID) { ForEach(store.workspace.connections) { Text($0.name).tag($0.id) } }
                TextField("显示名称 / 别名", text: $model.name)
                TextField("模型 ID", text: $model.model)
                HStack { Button(discovering ? "读取中…" : "读取服务模型列表", action: discover).disabled(discovering); if !discovered.isEmpty { Menu("选择发现的模型") { ForEach(discovered, id: \.self) { name in Button(name) { model.model = name; if model.name == "新模型" { model.name = name } } } } } }
                Toggle("支持 JSON response_format", isOn: $model.supportsJSON)
                Toggle(store.assistantText("支持图片输入（视觉模型）", "Supports image input (vision model)"), isOn: $model.supportsVision)
                DisclosureGroup("高级参数") {
                Toggle("发送 Temperature 参数", isOn: Binding(get: { model.temperature != nil }, set: { model.temperature = $0 ? 0.4 : nil }))
                if model.temperature != nil { Slider(value: Binding(get: { model.temperature ?? 0.4 }, set: { model.temperature = $0 }), in: 0...2, step: 0.1) { Text("Temperature") }; Text("Temperature：\(model.temperature ?? 0.4, specifier: "%.1f")") }
                Stepper("最大输出 Token：\(model.maxOutputTokens)", value: $model.maxOutputTokens, in: 256...32768, step: 256)
                Picker("输出 Token 参数", selection: $model.tokenParameter) { Text("max_tokens").tag("max_tokens"); Text("max_completion_tokens").tag("max_completion_tokens") }
                }
                Text(store.assistantText("只有确认模型及其兼容接口支持图片输入，才开启视觉选项。图片使用 Chat Completions 的 image_url 数据 URL 格式。", "Enable vision only when the model and its compatible endpoint accept image input. Images use Chat Completions image_url data URLs.")) .font(.caption).foregroundStyle(Palette.muted)
                Text("模型先返回完整结果，再由 App 校验。JSON 和 Token 参数需与你的服务一致。") .font(.caption).foregroundStyle(Palette.muted)
            }.formStyle(.grouped).frame(height: 530)
        }
    }
    private func save() { do { model.model = model.model.trimmingCharacters(in: .whitespacesAndNewlines); try store.saveModel(model); dismiss() } catch { self.error = error.localizedDescription } }
    private func discover() {
        guard let connection = store.workspace.connections.first(where: { $0.id == model.connectionID }) else { return }
        discovering = true; error = nil
        Task { @MainActor in
            do { discovered = try await ModelClient.discover(connection: connection, apiKey: store.apiKey(connection)); if discovered.isEmpty { error = "服务返回空目录，可手动填写模型 ID。" } }
            catch { self.error = error.localizedDescription }; discovering = false
        }
    }
}
