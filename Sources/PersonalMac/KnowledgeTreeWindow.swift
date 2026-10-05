import AppKit
import SwiftUI

/// Owns only the presentation, never a copy of the workspace or a persistence path.
/// A separate native full-screen space leaves the original reading and scroll position intact.
@MainActor final class KnowledgeTreeWindow: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isPresented = false
    private var window: KnowledgeCanvasWindow?
    private weak var returnWindow: NSWindow?
    private var host: NSHostingController<KnowledgeTreeFullScreenContent>?

    func present(title: String, languageIsEnglish: Bool, content: AnyView) {
        if let window {
            update(title: title, languageIsEnglish: languageIsEnglish, content: content)
            window.makeKeyAndOrderFront(nil)
            return
        }
        returnWindow = NSApp.keyWindow
        let screen = returnWindow?.screen ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1360, height: 880)
        let next = KnowledgeCanvasWindow(contentRect: frame.insetBy(dx: 20, dy: 20),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        next.title = title
        next.isReleasedWhenClosed = false
        next.collectionBehavior = [.fullScreenPrimary]
        next.minSize = NSSize(width: 860, height: 600)
        next.delegate = self
        let controller = NSHostingController(rootView: root(languageIsEnglish: languageIsEnglish, content: content))
        next.contentViewController = controller
        window = next; host = controller; isPresented = true
        next.makeKeyAndOrderFront(nil)
        // AppKit needs the window installed before the native transition begins.
        Task { @MainActor [weak self] in
            guard let window = self?.window, !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    func update(title: String, languageIsEnglish: Bool, content: AnyView) {
        guard let window, let host else { return }
        window.title = title
        host.rootView = root(languageIsEnglish: languageIsEnglish, content: content)
    }

    private func root(languageIsEnglish: Bool, content: AnyView) -> KnowledgeTreeFullScreenContent {
        KnowledgeTreeFullScreenContent(languageIsEnglish: languageIsEnglish, content: content,
            fitRevision: host?.rootView.fitRevision ?? 0,
            close: { [weak self] in self?.close() })
    }

    func close() { window?.close() }

    func windowDidEnterFullScreen(_ notification: Notification) {
        // Fit after AppKit finishes expanding the viewport, not to the hosting
        // controller's temporary initial size. Later data updates preserve zoom.
        host?.rootView.fitRevision += 1
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // The green window control / system fullscreen shortcut also returns to reading.
        close()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil; host = nil; isPresented = false
        if let returnWindow, returnWindow.isVisible { returnWindow.makeKeyAndOrderFront(nil) }
        returnWindow = nil
    }
}

@MainActor private final class KnowledgeCanvasWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

private struct KnowledgeTreeFullScreenContent: View {
    let languageIsEnglish: Bool
    let content: AnyView
    var fitRevision: Int
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(languageIsEnglish ? "Knowledge tree" : "知识树", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 13, weight: .semibold))
                Text(languageIsEnglish ? "Scroll to pan · ⌘ scroll / ⌘± to zoom" : "滚动平移 · ⌘ 滚动 / ⌘± 缩放")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button(languageIsEnglish ? "Return to reading" : "返回阅读", systemImage: "arrow.down.right.and.arrow.up.left", action: close)
                    .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                    .help(languageIsEnglish ? "Close the full-screen canvas (Esc)" : "关闭全屏画布（Esc）")
            }.padding(.horizontal, 20).padding(.vertical, 12)
            content.padding(.horizontal, 14).padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Palette.ink).background(Palette.canvas)
            .environment(\.locale, Locale(identifier: languageIsEnglish ? "en" : "zh-Hans"))
            .environment(\.knowledgeTreeFitRevision, fitRevision)
            .preferredColorScheme(ThemeAppearance.shared.theme == .paper ? .light : nil)
    }
}

private struct KnowledgeTreeFitRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var knowledgeTreeFitRevision: Int {
        get { self[KnowledgeTreeFitRevisionKey.self] }
        set { self[KnowledgeTreeFitRevisionKey.self] = newValue }
    }
}
