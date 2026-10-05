import AppKit
import PersonalCore
import SwiftUI

struct ManualPaperExchangeView: View {
    let exchange: ManualPaperExchange
    let initiallyCopied: Bool
    let importDraft: (SciencePDFImport, ScientificQuestion) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var response = ""
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var showPrompt = false
    @FocusState private var responseFocused: Bool

    private func text(_ chinese: String, _ english: String) -> String { exchange.text(chinese, english) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "BRING YOUR OWN LLM")
                    Text(text("复制提示词，带回结果。", "Copy the prompt. Bring back the result."))
                        .font(EditorialType.title(27))
                    Text(exchange.fileName).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                Button(text("关闭", "Close")) { dismiss() }.buttonStyle(QuietButtonStyle())
            }
            Text(text("1. 复制完整提示词到你选的 LLM 网站。\n2. 等待完整 JSON 回复，复制后粘贴到下面。\n3. 本机校验后预览，再由你决定是否保存。", "1. Copy the complete prompt to your chosen LLM website.\n2. Wait for the complete JSON response, then paste it below.\n3. Validate locally, review the draft, and decide whether to save."))
                .font(.system(size: 13)).lineSpacing(5)
            Text(text("提示词包含这篇 PDF 的提取文字和文件名，不含工作区其他数据或 API Key；没有截图。软件不会打开网站或自动发送资料，请自行判断网站的隐私政策和输入长度上限。关闭此窗口会丢弃未导入的粘贴内容。", "The prompt includes this PDF's extracted text and filename, not other workspace data or API keys. It includes no images. The app does not open a website or send anything automatically; check your website's privacy policy and input limit. Closing this window discards any unimported pasted response."))
                .font(.caption).foregroundStyle(Palette.muted).lineSpacing(4)
            HStack {
                Button(text("复制完整提示词", "Copy complete prompt"), systemImage: "doc.on.doc") {
                    copy(exchange.prompt, notice: text("完整提示词已复制。", "Complete prompt copied."))
                }.buttonStyle(QuietButtonStyle(prominent: true))
                Text(text("\(exchange.prompt.count) 字符 · 仅文字", "\(exchange.prompt.count) characters · text only"))
                    .font(.caption).foregroundStyle(Palette.muted)
                Spacer()
            }
            DisclosureGroup(text("查看将复制的提示词", "Inspect the copied prompt"), isExpanded: $showPrompt) {
                ScrollView {
                    Text(exchange.prompt).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(height: 135).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            }.font(.caption)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(text("模型的完整 JSON 回复", "Complete JSON response")).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button(text("从剪贴板粘贴", "Paste from clipboard"), systemImage: "clipboard") { paste() }
                        .buttonStyle(QuietButtonStyle())
                }
                TextEditor(text: $response).font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
                    .focused($responseFocused).accessibilityLabel(text("粘贴模型 JSON 结果", "Paste model JSON result"))
                    .frame(minHeight: 160, maxHeight: .infinity)
            }
            if let errorMessage {
                ScrollView { Label(errorMessage, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Palette.warning).textSelection(.enabled) }
                    .frame(maxHeight: 70)
            }
            if let notice {
                Label(notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(Palette.success)
            }
            HStack {
                if errorMessage != nil {
                    Button(text("复制修复提示词", "Copy repair prompt"), systemImage: "doc.on.doc") {
                        do { copy(try exchange.repairPrompt(response: response, error: errorMessage ?? ""), notice: text("修复提示词已复制，请带回完整新结果。", "Repair prompt copied; bring back the complete corrected result.")) }
                        catch { errorMessage = error.localizedDescription }
                    }.buttonStyle(QuietButtonStyle())
                }
                Spacer()
                Button(text("校验并预览", "Validate and preview"), systemImage: "checkmark") { validate() }
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 820, height: 760).background(Palette.canvas)
            .onAppear { if initiallyCopied { notice = text("完整提示词已复制；在你选的网站粘贴即可。", "Complete prompt copied; paste it into your chosen website.") } }
    }

    private func copy(_ value: String, notice: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(value, forType: .string) { self.notice = notice }
        else { errorMessage = text("无法写入剪贴板，请展开提示词手动复制。", "Could not write to the clipboard. Expand the prompt and copy it manually.") }
    }

    private func paste() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            errorMessage = text("剪贴板中没有文字。", "The clipboard contains no text."); return
        }
        guard value.utf8.count <= ManualPaperExchange.maxResponseBytes else {
            errorMessage = text("剪贴板内容超过 2 MB；未粘贴。", "Clipboard text exceeds 2 MB; it was not pasted."); return
        }
        response = value; errorMessage = nil; notice = nil; responseFocused = true
    }

    private func validate() {
        do {
            let (draft, graph) = try exchange.parse(response)
            try importDraft(draft, graph)
            dismiss()
        } catch {
            errorMessage = exchange.language == .english && AppLanguage.containsHan(error.localizedDescription)
                ? "Graph validation failed. Check node references, page citations, recorded evidence and the ban on direct atomic-to-mainline links."
                : error.localizedDescription
            notice = nil
        }
    }
}
