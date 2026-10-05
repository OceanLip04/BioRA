import AppKit
import PersonalCore
import SwiftUI

struct LaboratorySettingsView: View {
    let store: PersonalStore
    @State private var draft = LaboratoryConfiguration()
    @State private var token = ""
    @State private var notice: String?
    @State private var failure: String?
    private func text(_ zh: String, _ en: String) -> String { store.assistantText(zh, en) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(text("实验室 · 每日研究摘要", "Laboratory · Daily Research"), systemImage: "network")
                .font(.system(size: 15, weight: .semibold))
            Toggle(text("开启实验室功能", "Enable Laboratory"), isOn: Binding(get: { store.workspace.laboratory.enabled }, set: { enabled in
                do { var config = store.workspace.laboratory; config.enabled = enabled; try store.saveLaboratoryConfiguration(config); draft.enabled = enabled }
                catch { failure = error.localizedDescription }
            })).disabled(store.readOnly)
            Text(text("可选的云端阅读模块。仅向你配置的服务器发送日期、语言、时区、频道及独立访问令牌，不上传本机实验、Protocol、对话或模型 Key。关闭后停止自动请求，已有缓存保留。",
                      "An optional cloud reading module. Only the date, language, time zone, feed and separate access token go to your configured server. Local experiments, Protocols, chats and model keys are never uploaded. Disabling stops automatic requests and keeps the cache."))
                .font(.caption).foregroundStyle(Palette.muted)
            if store.workspace.laboratory.enabled {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(text("HTTPS 服务器根地址，例如 https://research.example.org/api", "HTTPS server base URL, e.g. https://research.example.org/api"), text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField(text("频道", "Feed"), text: $draft.feed).textFieldStyle(.roundedBorder)
                        TextField(text("IANA 时区，例如 Asia/Shanghai", "IANA time zone, e.g. Asia/Shanghai"), text: $draft.timezone).textFieldStyle(.roundedBorder)
                    }
                    Toggle(text("应用运行时自动获取每日摘要", "Automatically fetch daily research while the app is running"), isOn: $draft.automatic)
                    Text(text("启动／回到前台及运行期间检查当日摘要；最新缓存最多每 6 小时复核一次。无发布或失败会延后重试。完全退出应用后不运行后台服务。",
                              "Checks today's digest on launch, return to the foreground, and while running; fresh cache is revalidated at most every 6 hours. Unpublished or failed requests retry later. No background service runs after the app quits."))
                        .font(.caption).foregroundStyle(Palette.muted)
                    SecureField(text("服务器访问令牌（可选；空白保留已有令牌）", "Server access token (optional; blank keeps the saved token)"), text: $token)
                        .textFieldStyle(.roundedBorder)
                    Text(text("此令牌不是模型 API Key，按工作区、服务器和频道隔离保存在钥匙串，不进入 JSON 备份。更换服务器不会把旧令牌发到新地址。公开频道可以不填。",
                              "This is not a model API key. It is stored in Keychain per workspace/server/feed, excluded from JSON backups. Changing servers never sends the old token to the new address. Public feeds can leave it empty."))
                        .font(.caption).foregroundStyle(Palette.muted)
                    HStack {
                        Button(text("保存服务器设置", "Save Server Settings")) { save() }.buttonStyle(QuietButtonStyle(prominent: true))
                        Button(text("移除当前服务器令牌", "Remove Current Server Token")) {
                            do {
                                let account = try ResearchDigestClient.tokenAccount(configuration: store.workspace.laboratory, directory: store.file.directory)
                                try AssistantKeychain().delete(account: account); token = ""
                                store.researchNextAttempt = [:]
                                notice = text("已移除当前服务器令牌。", "Current server token removed."); failure = nil
                            } catch { failure = error.localizedDescription }
                        }.buttonStyle(QuietButtonStyle()).disabled(store.workspace.laboratory.baseURL.isEmpty)
                    }
                }.disabled(store.readOnly)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(Palette.green) }
            if let failure { Text(failure).font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled) }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).card()
            .onAppear { draft = store.workspace.laboratory }
    }
    private func save() {
        do {
            guard !store.readOnly else { throw WorkspaceError.invalid("Read-only workspace. / 只读工作区。") }
            draft.enabled = store.workspace.laboratory.enabled
            draft.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.feed = draft.feed.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.timezone = draft.timezone.trimmingCharacters(in: .whitespacesAndNewlines)
            try draft.validated(); _ = try draft.serverURL()
            let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                _ = try ResearchDigestClient.request(configuration: draft, date: draft.day(Date()), language: store.workspace.language, token: value, etag: nil)
                let account = try ResearchDigestClient.tokenAccount(configuration: draft, directory: store.file.directory)
                try AssistantKeychain().save(value, account: account)
                token = ""
            }
            try store.saveLaboratoryConfiguration(draft)
            notice = text("设置已保存，可在「每日研究」获取摘要。", "Settings saved. Open Daily Research to fetch a digest."); failure = nil
        } catch { failure = error.localizedDescription }
    }
}

struct DailyResearchView: View {
    let store: PersonalStore
    let openSettings: () -> Void
    @State private var date = Date()
    @State private var followsToday = true
    @State private var content = 0
    @State private var manualTask: Task<Void, Never>?
    private func text(_ zh: String, _ en: String) -> String { store.assistantText(zh, en) }
    private var day: String { store.workspace.laboratory.day(followsToday ? Date() : date) }
    private var selected: CachedResearchDigest? { store.researchCache(date: day) }
    private var history: [CachedResearchDigest] {
        store.workspace.researchDigests.filter { entry in
            (try? ResearchDigestClient.key(configuration: store.workspace.laboratory, date: entry.digest.date, language: store.workspace.language)) == entry.key
        }.sorted { $0.digest.date > $1.digest.date }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "LABORATORY · DAILY RESEARCH")
                        Text(text("每日研究", "Daily Research")).font(EditorialType.title(30))
                        Text(text("从问题到结果，从结果到论证树。", "Follow the question, the findings, and their evidence trees."))
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button(text("服务器设置", "Server Settings"), action: openSettings).buttonStyle(QuietButtonStyle())
                }
                HStack(spacing: 12) {
                    DatePicker(text("日期", "Date"), selection: Binding(get: { followsToday ? Date() : date }, set: { date = $0; followsToday = false }), in: ...Date(), displayedComponents: .date).frame(width: 240)
                        .environment(\.timeZone, TimeZone(identifier: store.workspace.laboratory.timezone) ?? .current)
                    Button(text("今天", "Today")) { followsToday = true }.buttonStyle(QuietButtonStyle())
                    Text(store.workspace.laboratory.timezone).font(.caption).foregroundStyle(Palette.muted)
                    Spacer()
                    if store.researchFetching { ProgressView().controlSize(.small) }
                    Button(text("获取／刷新", "Fetch / Refresh"), systemImage: "arrow.clockwise") {
                        let requestedDay = day
                        manualTask = Task { await store.fetchResearchDigest(date: requestedDay) }
                    }.buttonStyle(QuietButtonStyle(prominent: true))
                        .disabled(store.readOnly || store.researchFetching || store.workspace.laboratory.baseURL.isEmpty || !store.workspace.laboratory.enabled)
                }
                if let error = store.researchFailure { Text(error).font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled) }
                else if let message = store.researchMessage { Text(message).font(.caption).foregroundStyle(Palette.muted) }
            }.padding(24)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(text("离线缓存", "OFFLINE CACHE")).font(.caption).foregroundStyle(Palette.muted).padding(.horizontal, 16).padding(.top, 18)
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(history) { entry in
                                Button { selectDay(entry.digest.date) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.digest.date).font(.system(size: 12, weight: .semibold))
                                        Text(entry.digest.title).font(.system(size: 11)).lineLimit(3)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .background(entry.digest.date == day ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }.padding(8)
                    }
                }.frame(width: 190).background(Palette.sidebar)
                Divider()
                if let entry = selected {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.digest.title).font(EditorialType.title(24))
                            Text(text("服务器版本 \(entry.digest.revision) · \(entry.digest.date) · 云端文献，不是本人实验", "Server revision \(entry.digest.revision) · \(entry.digest.date) · Literature, not your own experiment"))
                                .font(.caption).foregroundStyle(Palette.muted)
                        }.padding(.horizontal, 20).padding(.top, 18)
                        Picker(text("阅读方式", "Reading View"), selection: $content) {
                            Text(text("主线与树", "Mainline & Trees")).tag(0)
                            Text(text("知识画布", "Knowledge Canvas")).tag(1)
                            Text(text("摘要与来源", "Summary & Sources")).tag(2)
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520).padding(.horizontal, 20)
                        if content == 0 {
                            ScrollView { ScienceArgumentView(question: entry.graph, language: store.workspace.language).padding(20) }
                        } else if content == 1 {
                            ScienceMindMapView(question: entry.graph, language: store.workspace.language, canEdit: false, canMoveNodes: false,
                                experimentName: { _ in "" }, moveNode: { _, _ in false }, resetLayout: {}, addClaim: {}, addAtom: {},
                                editQuestion: {}, editClaim: { _ in }, editAtom: { _ in }, linkClaim: { _ in }, linkAtom: { _ in }, fitsAvailableHeight: true)
                                .padding(.horizontal, 20).padding(.bottom, 12)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) {
                                    Text(entry.digest.summary).textSelection(.enabled)
                                    Text(text("发布时间：", "Published: ") + entry.digest.published_at).font(.caption).foregroundStyle(Palette.muted)
                                    Text(text("来源 · 点击后由浏览器打开", "Sources · open in your browser")).font(.headline)
                                    ForEach(entry.digest.sources, id: \.id) { source in
                                        VStack(alignment: .leading, spacing: 5) {
                                            if let url = URL(string: source.url) { Link(source.title, destination: url) }
                                            Text(source.url).font(.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
                                        }
                                    }
                                    Text(text("这是服务器提供的研究解读，不自动成为你工作区里的结论、实验或排程。请对照原文核实观察、推理和边界。",
                                              "This is server-supplied research interpretation, not an automatic addition to your conclusions, experiments or schedule. Verify observations, reasoning and limitations against the originals."))
                                        .font(.caption).foregroundStyle(Palette.warning)
                                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.id(entry.key + "-\(entry.digest.revision)")
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 32)).foregroundStyle(Palette.muted)
                        Text(text("这一天尚无缓存摘要", "No cached digest for this day")).font(EditorialType.title(24))
                        Text(text("配置研究服务器后获取；摘要未发布时不会编造内容。", "Configure your server and fetch. An unpublished digest is never fabricated."))
                            .font(.caption).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.background(Palette.canvas).onDisappear { manualTask?.cancel() }
    }
    private func selectDay(_ day: String) {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: store.workspace.laboratory.timezone)
        formatter.dateFormat = "yyyy-MM-dd"
        if let selectedDate = formatter.date(from: day) { date = selectedDate; followsToday = false }
    }
}
