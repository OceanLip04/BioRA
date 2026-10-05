import AppKit
import PersonalCore
import SwiftUI

@main struct PersonalApp: App {
    @State private var store: PersonalStore
    @State private var authorizedWorkspace: URL?
    private let demo: Bool
    private let mainlinePreview: Bool

    @MainActor init() {
        let arguments = CommandLine.arguments
        let directory: URL
        if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) {
            directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else if let path = ProcessInfo.processInfo.environment["LABMONITOR_PERSONAL_DATA_DIR"] {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("PersonalData", isDirectory: true)
        }
        demo = arguments.contains("--demo")
        let timingPreview = arguments.contains("--preview-experiment-timing") || Bundle.main.bundleIdentifier == "com.labmonitor.personal.swift.timingpreview"
        let dailyPreview = arguments.contains("--preview-daily-research") || Bundle.main.bundleIdentifier == "com.labmonitor.personal.swift.dailyresearchpreview"
        let supplementPreview = arguments.contains("--preview-panel-supplement") || Bundle.main.bundleIdentifier == "com.labmonitor.personal.swift.panelsupplementpreview"
        let paperLogicPreview = arguments.contains("--preview-paper-logic") || Bundle.main.bundleIdentifier == "com.labmonitor.personal.swift.paperlogicpreview" || supplementPreview
        mainlinePreview = arguments.contains("--preview-mainline") || Bundle.main.bundleIdentifier == "com.labmonitor.personal.swift.mainlinepreview" || paperLogicPreview || dailyPreview || timingPreview
        if mainlinePreview {
            var preview = paperLogicPreview ? Workspace.paperLogicPreview() : Workspace.demo()
            if timingPreview { preview = (try? Workspace.experimentTimingPreview()) ?? Workspace() }
            if dailyPreview {
                do { preview = try Workspace.dailyResearchPreview() }
                catch { preview = Workspace(); preview.language = .english }
            }
            if supplementPreview {
                preview.literatureReadings[0].analysis?.figure_panels = nil
                preview.literatureReadings[0].analysis?.panel_links = nil
            }
            if arguments.contains("--native-theme") { preview.theme = .macOS }
            let previewStore = PersonalStore(previewDirectory: directory, previewWorkspace: preview)
            previewStore.requestedPage = timingPreview ? "protocols" : (dailyPreview ? "laboratory" : (paperLogicPreview ? "literature" : "science"))
            _store = State(initialValue: previewStore)
        } else {
            _store = State(initialValue: PersonalStore(directory: directory, demo: demo, loadImmediately: false))
        }
    }

    var body: some Scene {
        WindowGroup("BioRA") {
            Group {
                if store.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading your workspace… / 正在读取工作区…").font(.headline)
                        Text("If macOS asks for access to this folder, allow it to continue. / 如 macOS 请求访问此文件夹，请授权后继续。")
                            .foregroundStyle(.secondary)
                        Text(store.file.directory.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Authorize this workspace folder… / 授权此工作区文件夹…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                            panel.directoryURL = store.file.directory
                            panel.message = "Select this exact folder to grant local access. / 请选择这个文件夹授予本机访问权限：\n" + store.file.directory.path
                            guard panel.runModal() == .OK, let url = panel.url else { return }
                            guard url.standardizedFileURL == store.file.directory.standardizedFileURL else {
                                store.errorMessage = "Select the existing workspace folder; no data were moved. / 请选择现有工作区文件夹，数据未移动。"; return
                            }
                            if url.startAccessingSecurityScopedResource() { authorizedWorkspace = url }
                            store.errorMessage = nil
                        }.buttonStyle(.bordered)
                        if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        if mainlinePreview {
                            HStack {
                            Text("只读界面预览 · 虚构示例 · 未读取数据库 / Read-only preview · fictional data · no database access")
                                .font(.caption).foregroundStyle(Palette.muted)
                            Picker("主题 / Theme", selection: Binding(get: { store.workspace.theme }, set: { try? store.setTheme($0) })) {
                                Text("暖色纸感").tag(AppTheme.paper)
                                Text("macOS 原生").tag(AppTheme.macOS)
                            }.pickerStyle(.segmented).frame(width: 230)
                            }.padding(8).frame(maxWidth: .infinity)
                                .foregroundStyle(Palette.ink).background(Palette.canvas)
                        }
                        WorkspaceView(store: store)
                    }
                }
            }.frame(minWidth: 980, minHeight: 680)
                .task { await store.loadWorkspace(demo: demo) }
                .preferredColorScheme(store.workspace.theme == .paper ? .light : nil)
                .onChange(of: store.workspace.theme, initial: true) { _, theme in ThemeAppearance.shared.theme = theme }
        }
        .defaultSize(width: 1360, height: 880)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开数据文件夹") { NSWorkspace.shared.open(store.file.directory) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }

}
