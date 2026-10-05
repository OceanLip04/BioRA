import AppKit
import CryptoKit
import PersonalCore
import SwiftUI

struct PanelLogicSupplementTarget: Identifiable {
    let id = UUID()
    let reading: LiteratureReading
    var source = ""
}

struct PanelLogicSupplementView: View {
    let target: PanelLogicSupplementTarget
    let language: AppLanguage
    let archivedPDF: URL?
    var saveAllowed = true
    let apply: (PanelLogicSupplementExchange, PaperAnalysis) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var pageCount = ""
    @State private var response = ""
    @State private var exchange: PanelLogicSupplementExchange?
    @State private var preview: PaperAnalysis?
    @State private var error: String?
    @State private var notice: String?
    @State private var showSource = false
    @State private var showPrompt = false
    @State private var loading = false
    @State private var readTask: Task<Void, Never>?
    @State private var worker: Task<PDFReadResult, Error>?
    private func t(_ zh: String, _ en: String) -> String { language == .english ? en : zh }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "FIGURE LOGIC · SUPPLEMENT")
                    Text(t("补上图面板之间的逻辑", "Complete the figure-panel logic")).font(EditorialType.title(27))
                    Text(target.reading.fileName).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button(t("关闭", "Close")) { dismiss() }.buttonStyle(QuietButtonStyle())
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(t("复制专用提示词到你的 LLM 网站，带回 JSON，再审阅保存。只补充图面板与连边，必要时追加方法和发现；已有阅读、Discussion 和研究主线不会被替换。", "Copy a dedicated prompt to your LLM website, bring back JSON, then review and save. Only panels/links and necessary additional methods/findings are added; your reading, Discussion and mainline remain unchanged."))
                        .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Text(t("可在此读取同一篇 PDF 或粘贴图注；也可不附原文，但须在 LLM 网站自行附上原 PDF/图注。复制内容只包含当前文献与补充资料，不含其他工作区数据、API Key 或截图，软件不会自动发送。", "Read the same PDF here or paste its captions. Without source text, attach the original PDF/captions in your LLM website. The prompt includes only this reading and supplied source, not other workspace data, API keys or images. Nothing is sent automatically."))
                        .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(t("读取同一篇 PDF…", "Read the same PDF…"), systemImage: "doc.text") { choosePDF() }.buttonStyle(QuietButtonStyle()).disabled(loading)
                        if let archivedPDF {
                            Button(t("读取已归档 PDF", "Read archived PDF")) { readPDF(archivedPDF) }.buttonStyle(QuietButtonStyle()).disabled(loading)
                        }
                        if loading { ProgressView().controlSize(.small) }
                        Spacer()
                        Text(t("PDF 页数", "PDF pages")).font(.caption)
                        TextField("", text: $pageCount).textFieldStyle(.roundedBorder).frame(width: 60)
                            .disabled(target.reading.pageCount != nil || loading)
                            .accessibilityLabel(t("原始 PDF 页数", "Original PDF page count"))
                    }
                    DisclosureGroup(t("原文或图注（可选） · \(source.count) 字符", "Source or captions (optional) · \(source.count) characters"), isExpanded: $showSource) {
                        TextEditor(text: $source).font(.system(size: 11, design: .monospaced)).frame(height: 120)
                            .accessibilityLabel(t("补充的原文图注", "Supplementary source captions"))
                    }.font(.caption)
                    HStack {
                        Button(t("复制补充提示词", "Copy supplement prompt"), systemImage: "doc.on.doc") { copyPrompt() }
                            .buttonStyle(QuietButtonStyle(prominent: true)).disabled(loading)
                        Button(t("查看提示词", "Inspect prompt")) {
                            do { try prepareExchange(); showPrompt.toggle() }
                            catch { self.error = error.localizedDescription }
                        }.buttonStyle(QuietButtonStyle()).disabled(loading)
                        Spacer()
                        Button(t("从剪贴板粘贴结果", "Paste result from clipboard"), systemImage: "clipboard") { paste() }
                            .buttonStyle(QuietButtonStyle()).disabled(exchange == nil)
                    }
                    if showPrompt, let exchange {
                        Text(t("\(exchange.prompt.count) 字符 · 仅当前文献与补充资料", "\(exchange.prompt.count) characters · only this reading and supplied source")).font(.caption).foregroundStyle(Palette.muted)
                        ScrollView {
                            Text(exchange.prompt).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }.frame(height: 130).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let preview {
                        FigurePanelLogicView(analysis: preview, readingID: target.reading.id, language: language, canvasHeight: 310)
                        Text(t("请对照原文核对观察、解释、页码和连边依据。保存后仅补充这篇文献，原图谱不会变化。", "Verify observations, interpretations, pages and link warrants against the paper. Saving supplements only this reading; its existing graph stays unchanged."))
                            .font(.caption).foregroundStyle(Palette.muted)
                        Button(t("返回修改 JSON", "Edit JSON again")) { self.preview = nil }.buttonStyle(QuietButtonStyle())
                    } else {
                        Text(t("模型的七字段 JSON 回复", "The model's seven-field JSON response")).font(.system(size: 13, weight: .medium))
                        TextEditor(text: $response).font(.system(size: 12, design: .monospaced)).frame(height: 170)
                            .padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel(t("粘贴图面板补充 JSON", "Paste figure-panel supplement JSON"))
                        Text(t("先复制本次提示词；关闭窗口会丢弃未保存内容。", "Copy this session's prompt first. Closing discards unsaved content.")).font(.caption).foregroundStyle(Palette.muted)
                    }
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled) }
                    if let notice { Label(notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(Palette.success) }
                }.padding(.trailing, 6)
            }
            HStack {
                if error != nil, let exchange {
                    Button(t("复制修复提示词", "Copy repair prompt")) {
                        do { copy(try exchange.repairPrompt(response: response, error: error ?? "")) }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(QuietButtonStyle())
                }
                Spacer()
                if let preview, let exchange {
                    Button(t("确认保存补充", "Save reviewed supplement"), systemImage: "checkmark") {
                        do { try apply(exchange, preview); dismiss() }
                        catch { self.error = error.localizedDescription; notice = nil }
                    }.buttonStyle(QuietButtonStyle(prominent: true)).disabled(!saveAllowed)
                        .help(saveAllowed ? t("仅保存这篇文献的补充", "Save only this reading's supplement") : t("当前工作区只读，可复制与预览，但不能保存。", "This workspace is read-only. Copy and preview are available, but saving is disabled."))
                } else {
                    Button(t("校验并预览", "Validate and preview")) {
                        do { preview = try exchange?.parse(response); error = nil; notice = nil }
                        catch { self.error = error.localizedDescription; notice = nil }
                    }.buttonStyle(QuietButtonStyle(prominent: true)).disabled(exchange == nil || response.isEmpty || loading)
                }
            }
        }.padding(24).frame(width: 880, height: 760).background(Palette.canvas)
            .onAppear { source = target.source; pageCount = target.reading.pageCount.map(String.init) ?? "" }
            .onChange(of: source) { _, _ in invalidate() }
            .onChange(of: pageCount) { _, _ in invalidate() }
            .onChange(of: response) { _, _ in preview = nil; error = nil; notice = nil }
            .onDisappear { readTask?.cancel(); worker?.cancel() }
    }

    private func invalidate() { exchange = nil; preview = nil; error = nil; notice = nil; showPrompt = false }
    private func prepareExchange() throws {
        if exchange == nil { exchange = try PanelLogicSupplementExchange(reading: target.reading, language: language, pageCount: Int(pageCount) ?? 0, source: source) }
    }
    private func copyPrompt() {
        do {
            try prepareExchange()
            copy(exchange!.prompt)
        } catch { self.error = error.localizedDescription }
    }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) { notice = t("提示词已复制，请在你的 LLM 网站使用。", "Prompt copied. Use it in your LLM website."); error = nil }
        else { error = t("无法写入剪贴板。", "Could not write to the clipboard.") }
    }
    private func paste() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else { error = t("剪贴板没有文字。", "The clipboard contains no text."); return }
        guard value.utf8.count <= ManualPaperExchange.maxResponseBytes else { error = t("结果超过 2 MB，未粘贴。", "The response exceeds 2 MB; nothing was pasted."); return }
        response = value; preview = nil; error = nil; notice = nil
    }
    private func choosePDF() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { readPDF(url) }
    }
    private func readPDF(_ url: URL) {
        loading = true; error = nil; notice = nil
        readTask = Task { @MainActor in
            defer { loading = false; worker = nil; readTask = nil }
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= PDFLocalReader.maxFileBytes else { throw WorkspaceError.invalid(t("PDF 最多 20 MB。", "The PDF must be at most 20 MB.")) }
                let data = try Data(contentsOf: url)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest.hasPrefix(target.reading.fingerprint.lowercased()) else { throw WorkspaceError.invalid(t("这份 PDF 与当前阅读记录不匹配，请选择原文。", "This PDF does not match the reading. Select the original paper.")) }
                let task = Task.detached(priority: .userInitiated) { try PDFLocalReader.read(data) }
                worker = task
                let result = try await task.value
                try Task.checkCancellation()
                guard result.unreadablePages.isEmpty else { throw WorkspaceError.invalid(t("有页面无法读出文字；请在网站附上原PDF或截图，不会静默漏页。", "Some pages have no readable text. Attach the original PDF/images in your website; no page will be silently omitted.")) }
                guard target.reading.pageCount == nil || result.pages.count == target.reading.pageCount else { throw WorkspaceError.invalid(t("PDF 页数与原记录不一致。", "The page count does not match this reading.")) }
                source = try PDFTextBudget.source(result.pages, language: language)
                pageCount = String(result.pages.count); showSource = true
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
