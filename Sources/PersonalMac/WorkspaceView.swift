import AppKit
import PersonalCore
import SwiftUI
import UniformTypeIdentifiers

enum Screen: String, CaseIterable, Identifiable {
    case overview, assistant, science, literature, paperGraph, laboratory, instruments, protocols, experiments, calendar, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "我的一天"; case .assistant: "实验助手"; case .science: "科学问题"; case .literature: "文献阅读库"; case .paperGraph: "PDF 研究图谱"; case .laboratory: "每日研究"; case .instruments: "可用仪器"; case .protocols: "Protocol 库"
        case .experiments: "我的实验"; case .calendar: "实验排程"; case .settings: "设置"
        }
    }
    func title(_ language: AppLanguage) -> String {
        guard language == .english else { return title }
        return switch self {
        case .overview: "My Day"; case .assistant: "Assistant"; case .science: "Scientific Questions"; case .literature: "Literature Library"; case .paperGraph: "PDF to Graph"; case .laboratory: "Daily Research"
        case .instruments: "Instruments"; case .protocols: "Protocol Library"
        case .experiments: "My Experiments"; case .calendar: "Schedule"; case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "sun.max"; case .instruments: "waveform.path.ecg.rectangle"; case .protocols: "list.clipboard"
        case .assistant: "sparkles"; case .science: "questionmark.circle"; case .literature: "books.vertical"; case .paperGraph: "doc.text.magnifyingglass"; case .laboratory: "network"; case .experiments: "flask"; case .calendar: "calendar"; case .settings: "externaldrive"
        }
    }
}

enum Editor: Identifiable {
    case instrument(Instrument), procedure(Procedure), draft(AssistantArtifact), experiment(UUID?), busy, notes(Experiment)
    var id: String {
        switch self { case .instrument(let value): "instrument-\(value.id)"; case .procedure(let value): "procedure-\(value.id)"; case .draft(let value): "draft-\(value.id)"; case .experiment: "experiment"; case .busy: "busy"; case .notes(let value): "notes-\(value.id)" }
    }
}

struct WorkspaceView: View {
    let store: PersonalStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var screen: Screen = .assistant
    @State private var editor: Editor?
    @State private var search = ""
    @State private var weekOffset = 0
    @State private var showCreate = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var paperSidebarVisible = true
    @State private var protocolListVisible = true
    @State private var selectedProtocolID: UUID?
    @State private var settingsSection = "模型"
    @State private var assistantPrefill = ""

    var body: some View {
        themedLayout
        .background(Palette.canvas).foregroundStyle(Palette.ink).tint(Palette.accent)
        .environment(\.locale, Locale(identifier: store.workspace.language.localeIdentifier))
        .sheet(item: $editor) { editor in
            switch editor {
            case .instrument(let value): InstrumentEditor(store: store, initial: value)
            case .procedure(let value): ProcedureEditor(store: store, initial: value)
            case .draft(let value): if let procedure = value.procedure { ProcedureEditor(store: store, initial: procedure, artifactID: value.id) }
            case .experiment(let procedureID): ExperimentEditor(store: store, initialProcedureID: procedureID)
            case .busy: BusyEditor(store: store)
            case .notes(let value): ExperimentNotesEditor(store: store, experiment: value)
            }
        }
        .onChange(of: screen) { _, _ in search = "" }
        .onChange(of: store.workspace.laboratory.enabled) { _, enabled in
            if !enabled, screen == .laboratory { screen = .settings }
        }
        .task(id: store.researchAutomaticIdentity + "|\(scenePhase)") {
            guard scenePhase == .active, store.workspace.laboratory.enabled, store.workspace.laboratory.automatic, !store.readOnly else { return }
            while !Task.isCancelled {
                await store.fetchResearchDigest(date: store.workspace.laboratory.day(Date()), automatic: true)
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
        .onChange(of: store.requestedPage, initial: true) { _, page in
            if let page, let destination = Screen(rawValue: page) {
                screen = destination == .laboratory && !store.workspace.laboratory.enabled ? .settings : destination
                if store.requestedDataAction == "restore" { settingsSection = "数据" }
                store.requestedPage = nil
            }
        }
        .onChange(of: store.runningRunID) { _, run in
            if run == nil, store.requestedDataAction == "restore" {
                store.requestedDataAction = nil; settingsSection = "数据"; screen = .settings; restoreBackup()
            }
        }
    }


    @ViewBuilder private var themedLayout: some View {
        if store.workspace.theme == .paper {
            HStack(spacing: 0) {
                if paperSidebarVisible { paperSidebar }
                VStack(spacing: 0) { paperHeader; pageContent }
            }
        } else { nativeLayout }
    }

    private var nativeLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            pageContent
            .navigationTitle(screen.title(store.workspace.language))
            .toolbar {
                ToolbarItemGroup {
                    if screen == .protocols {
                        Button { protocolListVisible.toggle() } label: { Label(store.assistantText("Protocol 列表", "Protocol List"), systemImage: "rectangle.split.2x1") }
                            .help(store.assistantText("显示或隐藏 Protocol 列表", "Show or hide the Protocol list"))
                    }
                    if [.instruments, .protocols, .experiments].contains(screen) {
                        TextField(store.assistantText("搜索名称", "Search names"), text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
                    }
                    if [.instruments, .protocols, .experiments, .calendar, .overview].contains(screen) {
                        Menu {
                            Button(store.assistantText("新建实验", "New Experiment"), systemImage: "flask") { editor = .experiment(nil) }
                            Button(store.assistantText("添加仪器", "Add Instrument"), systemImage: "waveform.path.ecg.rectangle") { editor = .instrument(Instrument(name: "")) }
                            Button(store.assistantText("新建 Protocol", "New Protocol"), systemImage: "list.clipboard") { editor = .procedure(Procedure(name: "", steps: [ProcedureStep(title: "", minutes: 0)])) }
                            Button(store.assistantText("添加忙碌时间", "Add Busy Time"), systemImage: "calendar.badge.clock") { editor = .busy }
                        } label: { Label(store.assistantText("新建", "New"), systemImage: "plus") }.disabled(store.readOnly)
                    }
                }
            }
        }
    }

    private var pageContent: some View {
        VStack(spacing: 0) {
            if let error = store.errorMessage, screen == .assistant || screen == .science || screen == .literature || screen == .paperGraph || screen == .settings || store.readOnly {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.warning)
                    Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if error.contains("Key") || error.contains("钥匙串") { Button("模型设置") { screen = .settings; settingsSection = "模型" }.buttonStyle(.plain).foregroundStyle(Palette.accent) }
                    Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭提示")
                }.padding(14).background(Palette.warning.opacity(0.07)).overlay(alignment: .bottom) { Divider() }
            }
            if screen == .assistant {
                AssistantChatView(store: store, prefill: $assistantPrefill, openSettings: { screen = .settings }, openScience: { screen = .science })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screen == .science {
                ScienceQuestionsView(store: store, discuss: { question in
                    assistantPrefill = store.assistantText(
                        "请结合我记录的科学问题「\(question.title)」（ID: \(question.id.uuidString)）、原子实验结果、论断与支持/反驳连线，梳理证据链、尚不确定的地方，并建议下一步如何验证。请区分计划、真实观察和推测，不要编造结果或把连线当成自动证明。",
                        "Discuss my scientific question (ID: \(question.id.uuidString)), its atomic experiment results, claims, and support/contradiction links. Explain the evidence chain, remaining uncertainty, and useful next tests. Distinguish plans, observations, and hypotheses; do not invent results or treat a link as proof. Answer in English."
                    )
                    screen = .assistant
                }).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screen == .paperGraph {
                SciencePDFImportView(store: store, openLiterature: { screen = .literature })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screen == .literature {
                LiteratureReadingsView(store: store, importPDF: { screen = .paperGraph })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screen == .laboratory {
                DailyResearchView(store: store, openSettings: { screen = .settings }).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screen == .instruments {
                instruments.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if screen == .protocols {
                protocols
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                    switch screen {
                    case .overview: overview
                    case .assistant: EmptyView()
                    case .science: EmptyView()
                    case .literature: EmptyView()
                    case .paperGraph: EmptyView()
                    case .laboratory: EmptyView()
                    case .instruments: instruments
                    case .protocols: EmptyView()
                    case .experiments: experiments
                    case .calendar: calendar
                    case .settings: settings
                    }
                    }.frame(maxWidth: screen == .settings ? 960 : 1240, alignment: .leading)
                        .padding(.horizontal, 32).padding(.vertical, 34).frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private var paperHeader: some View {
        HStack(spacing: 12) {
            Button { paperSidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.plain).help(store.assistantText("显示或隐藏侧栏", "Show or hide sidebar"))
            Text(screen.title(store.workspace.language)).font(.system(size: 13, weight: .medium))
            Spacer()
            if screen == .protocols {
                Button { protocolListVisible.toggle() } label: { Label(store.assistantText("Protocol 列表", "Protocol List"), systemImage: "rectangle.split.2x1") }.buttonStyle(QuietButtonStyle())
            }
            if [.instruments, .protocols, .experiments].contains(screen) {
                TextField(store.assistantText("搜索名称", "Search names"), text: $search).textFieldStyle(.roundedBorder).frame(width: 190)
            }
            Menu {
                Button(store.assistantText("新建实验", "New Experiment")) { editor = .experiment(nil) }
                Button(store.assistantText("添加仪器", "Add Instrument")) { editor = .instrument(Instrument(name: "")) }
                Button(store.assistantText("新建 Protocol", "New Protocol")) { editor = .procedure(Procedure(name: "", steps: [ProcedureStep(title: "", minutes: 0)])) }
                Button(store.assistantText("添加忙碌时间", "Add Busy Time")) { editor = .busy }
            } label: { Label(store.assistantText("新建", "New"), systemImage: "plus") }.disabled(store.readOnly)
        }.foregroundStyle(Palette.ink).padding(.horizontal, 24).frame(height: 58).background(Palette.canvas)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 0.5) }
    }

    private var paperSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BioRA").font(.system(size: 20, weight: .medium, design: .serif))
                    Text("Research Assistant").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }.padding(.top, 24).padding(.bottom, 32).padding(.horizontal, 18)
            Eyebrow(text: "WORKSPACE").padding(.horizontal, 22).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach([Screen.assistant, .science, .literature, .paperGraph] + (store.workspace.laboratory.enabled ? [.laboratory] : []) + [.overview, .protocols, .calendar, .experiments, .instruments]) { item in
                        Button { screen = item } label: {
                            HStack(spacing: 13) {
                                Image(systemName: item.symbol).font(.system(size: 15)).frame(width: 20)
                                Text(item.title(store.workspace.language)).font(.system(size: 13, weight: screen == item ? .semibold : .regular))
                                Spacer()
                                if screen == item { Circle().fill(Palette.accent).frame(width: 4, height: 4) }
                            }.padding(.horizontal, 15).frame(height: 43)
                                .background(screen == item ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(screen == item ? Palette.ink : Palette.muted)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 7) {
                Text("A little more space\nto think.").font(.system(size: 17, design: .serif)).foregroundStyle(Palette.muted).lineSpacing(3)
                Label(store.assistantText("数据保存在本机", "Data stays on this Mac"), systemImage: "lock").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(22)
            Divider().padding(.horizontal, 18)
            Button { screen = .settings } label: {
                HStack { Image(systemName: "slider.horizontal.3"); Text(store.assistantText("设置", "Settings")); Spacer(); Image(systemName: "chevron.right").font(.caption2) }
                    .font(.system(size: 12)).padding(20).foregroundStyle(Palette.muted)
            }.buttonStyle(.plain)
        }.frame(width: 218).background(Palette.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.line.opacity(0.5)).frame(width: 0.5) }
    }

    private var sidebar: some View {
        List(selection: Binding<Screen?>(get: { screen }, set: { if let value = $0 { screen = value } })) {
            Section(store.assistantText("工作区", "Workspace")) {
                sidebarRows([.assistant, .overview])
            }
            Section(store.assistantText("研究", "Research")) {
                sidebarRows([.science, .literature, .paperGraph, .protocols])
            }
            if store.workspace.laboratory.enabled {
                Section(store.assistantText("实验室", "Laboratory")) { sidebarRows([.laboratory]) }
            }
            Section(store.assistantText("实验", "Experiments")) {
                sidebarRows([.experiments, .calendar, .instruments])
            }
            Section { sidebarRows([.settings]) }
        }.listStyle(.sidebar).navigationTitle("BioRA")
            .safeAreaInset(edge: .bottom) {
                Label(store.assistantText("本机工作区", "Local Workspace"), systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }
    }

    private func sidebarRows(_ screens: [Screen]) -> some View {
        ForEach(screens) { item in Label(item.title(store.workspace.language), systemImage: item.symbol).tag(item) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: LocalDate.string(Date(), "M月d日 · EEEE"))
                    Text("今天，留一点思考的空间。").font(EditorialType.title(34))
                    Text("接下来的步骤、时间与资源，都在这里。").font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { editor = .experiment(nil) } label: { Label("安排一个实验", systemImage: "plus") }
                    .buttonStyle(QuietButtonStyle(prominent: true)).padding(.top, 24)
            }
            if store.workspace.isDemo {
                HStack(spacing: 9) {
                    Image(systemName: "sparkle")
                    Text("可编辑示例工作区").fontWeight(.medium)
                    Text("· 示例数据，不是你的真实实验；修改会保存在本机。")
                    Spacer()
                }.font(.system(size: 11)).foregroundStyle(Palette.green).padding(12)
                    .background(Palette.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 16) {
                metric("待进行实验", value: store.workspace.experiments.filter { $0.status == .planned || $0.status == .active }.count, symbol: "flask", subtitle: "下一步，心里有数")
                metric("可用仪器", value: store.workspace.instruments.filter(\.available).count, symbol: "waveform.path.ecg.rectangle", subtitle: "自己的资源清单")
                metric("Protocol", value: store.workspace.procedures.count, symbol: "list.clipboard", subtitle: "让步骤可重复")
            }
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeading("今天的安排", caption: "\(store.workspace.preferences.workStartMinute / 60):\(String(format: "%02d", store.workspace.preferences.workStartMinute % 60)) — \(store.workspace.preferences.workEndMinute / 60):\(String(format: "%02d", store.workspace.preferences.workEndMinute % 60))")
                    let today = store.activePlan.filter { $0.start < Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400) && $0.end > Calendar.current.startOfDay(for: Date()) }
                    if today.isEmpty { empty("今天留有余地", detail: "创建一个实验，按 Protocol 自动安排步骤。", symbol: "sun.max") }
                    else { ForEach(today) { step in agendaRow(step) } }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).card()
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeading("我的 Protocol", caption: "\(store.workspace.procedures.count) 个")
                    if store.workspace.procedures.isEmpty { empty("从一个步骤开始", detail: "手动编辑，不需要 AI Key。", symbol: "list.clipboard") }
                    ForEach(store.workspace.procedures.prefix(3)) { procedure in
                        Button { editor = .procedure(procedure) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Image(systemName: "list.clipboard").foregroundStyle(Palette.green)
                                Text(procedure.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                                Text("\(procedure.steps.count) 步 · \(procedure.totalMinutes) 分钟").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                    Button { screen = .protocols } label: { Label("查看 Protocol 库", systemImage: "arrow.up.right") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.green)
                }.padding(22).frame(width: 255, alignment: .leading).card()
            }
            Button { screen = .assistant } label: { HStack { Image(systemName: "bubble.left"); Text("需要调整安排？直接告诉实验助手。"); Spacer(); Image(systemName: "arrow.right") }.font(.system(size: 12)).padding(16).background(Palette.sidebar.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
        }
    }

    private func metric(_ title: String, value: Int, symbol: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted)
                Text(String(format: "%02d", value)).font(.system(size: 34, weight: .regular, design: .serif))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Image(systemName: symbol).font(.system(size: 19, weight: .light)).foregroundStyle(Palette.muted).padding(10)
        }.padding(20).frame(maxWidth: .infinity).card()
    }

    private var instruments: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(store.assistantText("个人仪器清单", "Your instruments")).font(.headline)
                Spacer()
                Button(store.assistantText("添加仪器", "Add Instrument"), systemImage: "plus") { editor = .instrument(Instrument(name: "")) }.disabled(store.readOnly)
            }.padding(.horizontal, 20).padding(.top, 20)
            let values = store.workspace.instruments.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            if values.isEmpty { empty("还没有可用仪器", detail: "点击右上角「新建」添加仪器；不需要建立实验室。", symbol: "waveform.path.ecg.rectangle") }
            if store.workspace.theme == .paper {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 18) {
                        ForEach(values) { item in
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "waveform.path.ecg.rectangle").font(.system(size: 25)).foregroundStyle(Palette.accent)
                                    Spacer()
                                    StatusPill(title: item.available ? store.assistantText("可用", "Available") : store.assistantText("暂不可用", "Unavailable"), color: item.available ? Palette.success : Palette.warning)
                                }
                                Text(item.name).font(.system(size: 18, weight: .semibold))
                                Label(item.location.isEmpty ? store.assistantText("未记录位置", "Location not recorded") : item.location, systemImage: "mappin.and.ellipse")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                Text(item.note).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(3).frame(minHeight: 36, alignment: .top)
                                Divider()
                                Button(store.assistantText("编辑仪器", "Edit Instrument")) { editor = .instrument(item) }.buttonStyle(QuietButtonStyle()).disabled(store.readOnly)
                            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).card()
                        }
                    }.padding(24)
                }
            } else { Table(values) {
                TableColumn(store.assistantText("名称", "Name")) { item in
                    Button(item.name) { editor = .instrument(item) }.buttonStyle(.plain).disabled(store.readOnly)
                }.width(min: 140, ideal: 220)
                TableColumn(store.assistantText("状态", "Availability")) { item in
                    Label(item.available ? store.assistantText("可用", "Available") : store.assistantText("不可用", "Unavailable"), systemImage: item.available ? "checkmark.circle" : "minus.circle")
                        .foregroundStyle(item.available ? Palette.success : Palette.muted)
                }.width(130)
                TableColumn(store.assistantText("位置", "Location"), value: \.location)
                TableColumn(store.assistantText("备注", "Notes"), value: \.note)
                TableColumn("") { item in Button(store.assistantText("编辑", "Edit")) { editor = .instrument(item) }.disabled(store.readOnly) }.width(60)
            } }
        }
    }

    private var protocols: some View {
        let values = store.workspace.procedures.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let drafts = store.workspace.artifacts.filter { $0.kind == .protocolDraft && $0.appliedID == nil && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
        let selected = values.first(where: { $0.id == selectedProtocolID }) ?? values.first
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                pageHeading(store.workspace.theme == .paper ? "把经验，写成可重复的步骤。" : "Protocol 文档", subtitle: "目的、材料、分层步骤、原理与注意事项。")
                Spacer()
                Button("让助手构建", systemImage: "sparkles") { screen = .assistant }.buttonStyle(QuietButtonStyle()).padding(.top, 12)
            }
            HStack(alignment: .top, spacing: protocolListVisible ? 22 : 0) {
                ScrollView {
                    protocolList(values: values, drafts: drafts, selectedID: selected?.id)
                        .padding(.vertical, 4)
                }
                // Keep the list in the view hierarchy so collapsing it does not recreate
                // the document ScrollView and discard the reader's scroll position.
                .frame(width: 240)
                .frame(width: protocolListVisible ? 240 : 0, alignment: .leading)
                .frame(maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(!protocolListVisible)
                .allowsHitTesting(protocolListVisible)
                .accessibilityLabel("Protocol 列表")
                ScrollView {
                    protocolDetail(selected, hasDrafts: !drafts.isEmpty)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 32)
                }
                .id(selected?.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Protocol 文档")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 32).padding(.top, 28)
        .frame(maxWidth: 1440, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func protocolList(values: [Procedure], drafts: [AssistantArtifact], selectedID: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "LIBRARY · \(values.count)").padding(.bottom, 4)
            ForEach(values) { procedure in
                let isSelected = procedure.id == selectedID
                Button { selectedProtocolID = procedure.id } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Image(systemName: "doc.text").foregroundStyle(isSelected ? Palette.accent : Palette.muted); Spacer(); Text("v\(procedure.currentVersion.number)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted) }
                        Text(procedure.name).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading)
                        Text("\(procedure.currentVersion.content.atomicSteps.count) 个操作 · \(procedure.totalMinutes) 分钟").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Palette.line : .clear, lineWidth: 0.7))
                }.buttonStyle(.plain)
            }
            if !drafts.isEmpty {
                Eyebrow(text: "待审阅 · \(drafts.count)").padding(.top, 20)
                ForEach(drafts.reversed()) { draft in
                    Button { editor = .draft(draft) } label: {
                        HStack(alignment: .top) {
                            Image(systemName: "doc.badge.clock").foregroundStyle(Palette.warning)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(draft.title).font(.system(size: 12, weight: .medium))
                                Text("助手草稿 · 审阅后存入库").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Spacer(); Image(systemName: "arrow.up.right").font(.caption2)
                        }.padding(12).background(Palette.warning.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private func protocolDetail(_ procedure: Procedure?, hasDrafts: Bool) -> some View {
        if let procedure {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(procedure.name).font(EditorialType.title(31)).fixedSize(horizontal: false, vertical: true)
                        if !procedure.note.isEmpty { Text(procedure.note).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5) }
                    }
                    Spacer()
                    Button(store.assistantText("从此 Protocol 创建实验", "Create experiment from this Protocol"), systemImage: "flask") { editor = .experiment(procedure.id) }
                        .buttonStyle(QuietButtonStyle()).disabled(store.readOnly || procedure.currentVersion.status != .published)
                    Button("编辑", systemImage: "slider.horizontal.3") { editor = .procedure(procedure) }.buttonStyle(QuietButtonStyle())
                }
                HStack(spacing: 14) {
                    StatusPill(title: procedure.currentVersion.status == .published ? "已确认 · v\(procedure.currentVersion.number)" : "草稿 · v\(procedure.currentVersion.number)", color: procedure.currentVersion.status == .published ? Palette.success : Palette.warning)
                    Text("\(procedure.currentVersion.content.blocks.count) 个阶段 · \(procedure.versions.count) 个版本").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                let missing = procedure.currentVersion.content.atomicSteps.filter { $0.durationMinutes == 0 }.count
                if missing > 0 { Label("\(missing) 项耗时待补齐，排程前需要完善。", systemImage: "clock").font(.system(size: 12)).foregroundStyle(Palette.warning) }
                Divider()
                ProtocolDocumentView(store: store, version: procedure.currentVersion).id(procedure.currentVersion.id)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading).card()
        } else if hasDrafts {
            empty("草稿已为你保留", detail: "显示左侧列表并选择草稿，审阅后存入 Protocol 库。", symbol: "doc.text")
        } else {
            empty("写下第一个 Protocol", detail: "直接让助手整理实验说明，也可以手动创建。", symbol: "list.clipboard")
        }
    }

    private var experiments: some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeading(store.workspace.theme == .paper ? "每个实验，都有下一步。" : "实验记录", subtitle: "安排、执行状态与观察记录。")
            let values = store.workspace.experiments.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            if values.isEmpty { empty("准备开始新实验", detail: "先添加一个 Protocol，再点击「新建实验」。", symbol: "flask") }
            ForEach(values) { experiment in
                let plan = store.workspace.plan.filter { $0.experimentID == experiment.id }.sorted { $0.start < $1.start }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(experiment.name).font(.system(size: 18, weight: .semibold))
                            Text(store.workspace.procedures.first { $0.id == experiment.procedureID }?.name ?? "Protocol").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        let overdue = experiment.status == .planned && (plan.first?.start ?? .distantFuture) < Date()
                        badge(overdue ? "计划已过期" : experiment.status.title, color: overdue ? Palette.warning : (experiment.status == .completed ? Palette.muted : Palette.success))
                        if experiment.status == .planned { Button("开始实验") { store.setStatus(experiment.id, .active) }.buttonStyle(QuietButtonStyle()) }
                        if experiment.status == .active { Button("标记完成") { store.setStatus(experiment.id, .completed) }.buttonStyle(QuietButtonStyle(prominent: true)) }
                        if experiment.status == .planned || experiment.status == .active {
                            Button("取消安排") { store.setStatus(experiment.id, .cancelled) }.buttonStyle(.borderless).foregroundStyle(Palette.muted)
                        }
                    }
                    if let first = plan.first, let last = plan.last {
                        Label("\(LocalDate.dateTime(first.start)) → \(LocalDate.dateTime(last.end)) · \(plan.count) 个步骤", systemImage: "clock").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    HStack {
                        let version = store.workspace.procedures.first { $0.id == experiment.procedureID }?.versions.first { $0.id == experiment.versionID }
                        Text(version.map { "使用 Protocol v\($0.number)" } ?? "历史 Protocol").font(.caption2).foregroundStyle(Palette.muted)
                        Text(experiment.sampleCount.map { store.assistantText("\($0) 个样品 · \(experiment.stepTimings.count) 条耗时记录", "\($0) samples · \(experiment.stepTimings.count) timing records") } ?? store.assistantText("样品数尚未填写", "Sample count not recorded")).font(.caption2).foregroundStyle(Palette.muted)
                        Spacer()
                        Button(store.assistantText("记录耗时与观察", "Record timings & observations")) { editor = .notes(experiment) }
                        Button("生成总结") { screen = .assistant; store.startAssistant("总结实验：" + experiment.name, modelID: store.workspace.routing.report ?? store.selectedModelID, operation: .report(experiment.id)) }.disabled(store.runningRunID != nil)
                    }
                    if !experiment.note.isEmpty { Text(experiment.note).font(.callout).textSelection(.enabled) }
                    if experiment.status != .cancelled { DisclosureGroup("查看 \(plan.count) 个步骤") { ForEach(plan) { agendaRow($0) } }.font(.system(size: 12)).padding(.top, 4) }
                }.padding(22).card()
            }
        }
    }

    private var calendar: some View {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let base = cal.dateInterval(of: .weekOfYear, for: Date())!.start
        let start = cal.date(byAdding: .weekOfYear, value: weekOffset, to: base)!
        let last = cal.date(byAdding: .day, value: 6, to: start)!
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                pageHeading(store.workspace.theme == .paper ? "让时间，一目了然。" : "本周安排", subtitle: "\(LocalDate.string(start, "M月d日")) — \(LocalDate.string(last, "M月d日")) · \(TimeZone.current.identifier)")
                Spacer()
                HStack(spacing: 10) {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).help("上一周")
                    Button("本周") { weekOffset = 0 }.buttonStyle(QuietButtonStyle())
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).help("下一周")
                }.padding(.top, 12)
            }
            HStack(spacing: 14) {
                StatusPill(title: "本人操作", color: Palette.accent)
                StatusPill(title: "无人值守", color: Palette.success)
                StatusPill(title: "忙碌 / 仪器占用", color: Palette.warning)
                Spacer()
                Menu("日历文件") { Button("导入 ICS…", action: importCalendar); Button("导出安排…", action: exportCalendar) }.fixedSize()
                Button("添加忙碌时间", systemImage: "plus") { editor = .busy }.buttonStyle(QuietButtonStyle())
            }
            PersonalWeekCalendar(store: store, start: start).id(weekOffset)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .leading, spacing: 14) {
                Text(store.assistantText("外观主题", "Appearance Theme")).font(.headline)
                Picker(store.assistantText("主题", "Theme"), selection: Binding(get: { store.workspace.theme }, set: { theme in
                    do { try store.setTheme(theme) } catch { store.errorMessage = error.localizedDescription }
                })) {
                    Text(store.assistantText("暖色纸感", "Warm Paper")).tag(AppTheme.paper)
                    Text(store.assistantText("macOS 原生", "Native macOS")).tag(AppTheme.macOS)
                }.pickerStyle(.segmented).frame(maxWidth: 420).disabled(store.readOnly)
                Text(store.assistantText("暖色纸感保留原来的配色、衬线标题与侧栏；原生主题使用系统导航、字体与浅色 / 深色外观。只改变显示，不改变数据、模型或提示词。", "Warm Paper restores the original palette, editorial titles, and sidebar. Native macOS uses system navigation, typography, and light/dark appearance. Themes change presentation only—not your data, models, or prompts."))
                    .font(.caption).foregroundStyle(Palette.muted)
            }.padding(20).card()
            pageHeading("设置", subtitle: "模型连接、语言、时间偏好与本机数据。")
            LaboratorySettingsView(store: store)
            VStack(alignment: .leading, spacing: 10) {
                Label(store.assistantText("语言", "Language"), systemImage: "globe").font(.system(size: 14, weight: .semibold))
                Text(store.assistantText("界面与生成语言", "Interface and output language")).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Picker("界面与生成语言 / Interface & output", selection: Binding(
                    get: { store.workspace.language },
                    set: { language in
                        do { try store.setLanguage(language); store.errorMessage = nil }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in Text(language.title).tag(language) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300).disabled(store.readOnly || store.runningRunID != nil)
                Text("切换后，新对话、Protocol 生成、排程说明和助手提示均使用所选语言；已有记录与历史消息不会自动翻译。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).card()
            Picker("设置类别", selection: $settingsSection) { Text("模型").tag("模型"); Text("排程偏好").tag("排程"); Text("数据与备份").tag("数据") }.pickerStyle(.segmented).frame(width: 380)
            if settingsSection == "模型" { AssistantSettingsView(store: store) }
            if settingsSection == "数据" {
            VStack(alignment: .leading, spacing: 18) {
                Label(store.workspace.isDemo ? "当前为可编辑示例工作区" : "当前为个人工作区", systemImage: "externaldrive").font(.headline)
                Text(store.file.directory.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Text("工作区保存在 workspace.sqlite，采用事务写入。旧 workspace.json 原样保留作迁移前备份。导出 JSON 包含会话与实验记录，不含钥匙串中的 API Key。").font(.system(size: 13)).foregroundStyle(Palette.muted)
                Button("在 Finder 中打开数据目录") { NSWorkspace.shared.open(store.file.directory) }
                HStack { Button("导出工作区备份", action: exportBackup); Button("从备份恢复…", action: restoreBackup).disabled(store.runningRunID != nil || store.readOnly) }
            }.padding(24).card()
            }
            if settingsSection == "排程" { PreferencesSettings(store: store) }
            HStack { BrandMark(size: 24); Text("BioRA · Research Assistant").font(.system(size: 12, design: .serif)); Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development") · Apache-2.0").font(.system(size: 10)).foregroundStyle(Palette.muted) }.padding(.top, 12)
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "labmonitor-backup.json"
        if panel.runModal() == .OK, let url = panel.url { do { try store.file.export(store.workspace, to: url) } catch { store.errorMessage = error.localizedDescription } }
    }
    private func restoreBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            let alert = NSAlert(); alert.messageText = "恢复工作区备份？"; alert.informativeText = "将替换当前工作区；恢复前会在当前目录保留一份 JSON 备份。API Key 不会从备份导入。"; alert.addButton(withTitle: "恢复"); alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn { do { try store.restore(url) } catch { store.errorMessage = error.localizedDescription } }
        }
    }
    private func importCalendar() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowedContentTypes = [.init(filenameExtension: "ics") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url { do { let busy = try CalendarExchange.read(url); try store.commit { $0.busyIntervals += busy }; store.errorMessage = "已导入 \(busy.count) 个个人忙碌时段；重复导入会产生重复记录。" } catch { store.errorMessage = error.localizedDescription } }
    }
    private func exportCalendar() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "labmonitor-plan.ics"
        if panel.runModal() == .OK, let url = panel.url { do { try CalendarExchange.export(store.activePlan).write(to: url, atomically: true, encoding: .utf8) } catch { store.errorMessage = error.localizedDescription } }
    }

    private func agendaRow(_ step: PlannedStep) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(timeRange(step)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted).frame(width: 90, alignment: .leading).padding(.top, 3)
            RoundedRectangle(cornerRadius: 2).fill(step.instrumentID == nil ? Palette.green.opacity(0.25) : Palette.green).frame(width: 3, height: 38)
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).font(.system(size: 13, weight: .medium))
                Text("\(store.experimentName(step.experimentID)) · \(store.instrumentName(step.instrumentID))").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6)
    }
    private func timeRange(_ step: PlannedStep) -> String {
        "\(LocalDate.time(step.start))–\(LocalDate.time(step.end))"
    }
    private func pageHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title)).font(EditorialType.title(33)).fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringKey(subtitle)).font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(4)
        }
    }
    private func sectionHeading(_ title: String, caption: String) -> some View {
        HStack { Text(LocalizedStringKey(title)).font(.system(size: 15, weight: .semibold)); Spacer(); Text(caption).font(.system(size: 10)).foregroundStyle(Palette.muted) }
    }
    private func badge(_ title: String, color: Color) -> some View {
        StatusPill(title: title, color: color)
    }
    private func empty(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Palette.green.opacity(0.7))
            Text(LocalizedStringKey(title)).font(.system(size: 18, weight: .medium))
            Text(LocalizedStringKey(detail)).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }.padding(25).frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func card() -> some View {
        background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.line.opacity(0.7), lineWidth: 0.7))
    }
}
