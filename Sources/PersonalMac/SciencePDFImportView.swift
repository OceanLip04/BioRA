import AppKit
import CryptoKit
import PersonalCore
import SwiftUI
import UniformTypeIdentifiers

struct SciencePDFImportView: View {
    let store: PersonalStore
    let openLiterature: () -> Void
    @State private var fileName = ""
    @State private var fingerprint = ""
    @State private var pdfData: Data?
    @State private var pages: [SciencePDFPage] = []
    @State private var draft: SciencePDFImport?
    @State private var preview: ScientificQuestion?
    @State private var modelID: UUID?
    @State private var processing = false
    @State private var processingStage = ""
    @State private var reading = false
    @State private var generationTask: Task<Void, Never>?
    @State private var readingTask: Task<Void, Never>?
    @State private var extractionTask: Task<PDFReadResult, Error>?
    @State private var renderTask: Task<[SciencePDFImage], Error>?
    @State private var includePageImages = false
    @State private var imagePageInput = ""
    @State private var imagePreviews: [SciencePDFImage] = []
    @State private var showImagePreview = false
    @State private var errorMessage: String?
    @State private var savedReadingID: UUID?
    @State private var showPreviewFocus = false
    @State private var manualExchange: ManualPaperExchange?
    @State private var manualPromptCopied = false
    @State private var panelSupplement: PanelLogicSupplementTarget?

    private var english: Bool { store.workspace.language == .english }
    private func wording(_ chinese: String, _ englishText: String) -> String { english ? englishText : chinese }
    private var selectedModel: ModelProfile? {
        let id = modelID ?? store.workspace.routing.assistant
        return store.workspace.models.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "PAPER TO GRAPH")
                    Text(wording("从 PDF，梳理科学证据。", "Turn a paper into an evidence map."))
                        .font(EditorialType.title(35))
                    Text(wording("本机提取 PDF 文字，对扫描页自动尝试 OCR；你也可选几页截图作为视觉补充。模型提出问题、原子实验、论断与连线，审阅后存入独立的文献阅读库。", "Text is extracted locally, with OCR attempted on scanned pages. You may add page images for visual context. After review, the paper map goes to the separate Literature Library."))
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(4)
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "doc.richtext").font(.system(size: 23, weight: .light)).foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fileName.isEmpty ? wording("还未选择 PDF", "No PDF selected") : fileName).font(.system(size: 14, weight: .medium)).lineLimit(2)
                            if !pages.isEmpty {
                                Text(wording("\(pages.count) 页 · 本机 OCR \(pages.filter { $0.source == .localOCR }.count) 页 · SHA-256 前缀 \(fingerprint)", "\(pages.count) pages · local OCR on \(pages.filter { $0.source == .localOCR }.count) · SHA-256 prefix \(fingerprint)"))
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
                            }
                        }
                        Spacer()
                        if reading { ProgressView().controlSize(.small); Text(wording("正在本机读取与 OCR…", "Reading and OCR on this Mac…")).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        Button(wording("选择 PDF", "Choose PDF"), systemImage: "doc.badge.plus", action: choosePDF)
                            .buttonStyle(QuietButtonStyle()).disabled(processing || reading)
                    }
                    HStack(spacing: 12) {
                        Picker(wording("解析模型", "Extraction model"), selection: $modelID) {
                            Text(wording("助手默认模型", "Assistant default model")).tag(nil as UUID?)
                            ForEach(store.workspace.models) { model in Text(model.name).tag(Optional(model.id)) }
                        }.frame(maxWidth: 440)
                        if processing {
                            ProgressView().controlSize(.small)
                            Button(wording("取消解析", "Cancel")) { generationTask?.cancel(); renderTask?.cancel() }.buttonStyle(.plain)
                        } else {
                            Button(wording("生成待审阅图谱", "Generate Review Draft"), systemImage: "point.3.connected.trianglepath.dotted", action: generate)
                                .buttonStyle(QuietButtonStyle(prominent: true)).disabled(pages.isEmpty || reading || store.readOnly)
                        }
                    }
                    HStack(spacing: 12) {
                        Button(wording("复制提示词", "Copy prompt"), systemImage: "doc.on.doc") { openManualExchange(copyPrompt: true) }
                            .buttonStyle(QuietButtonStyle()).disabled(pages.isEmpty || reading || processing)
                        Button(wording("粘贴模型结果…", "Paste model result…"), systemImage: "clipboard") { openManualExchange(copyPrompt: false) }
                            .buttonStyle(QuietButtonStyle()).disabled(pages.isEmpty || reading || processing)
                        Text(wording("使用自己的 LLM 网站 · 无需 API", "Use your own LLM website · no API needed"))
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Text(wording("复制内容含当前 PDF 的全文提取文字和文件名（不含截图）。只有你粘贴到网站后，资料才会离开本机；带回 JSON 后仍需校验与审阅。", "The copied prompt includes this PDF's extracted text and filename (no images). Only you decide whether to paste it into a website. Returned JSON still requires local validation and review."))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Toggle(isOn: $includePageImages) {
                        Text(wording("附加页面截图（仅视觉模型）", "Add page images (vision models only)"))
                    }.toggleStyle(.switch).disabled(selectedModel?.supportsVision != true || pages.isEmpty || processing)
                    if includePageImages {
                        HStack(spacing: 12) {
                            TextField(wording("页码，如 1,3-4；留空自动选首页和未识别页", "Pages, e.g. 1,3-4; blank selects the first and unreadable pages"), text: $imagePageInput)
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 520)
                            Button(wording("预览截图", "Preview Images"), action: previewSelectedImages).buttonStyle(QuietButtonStyle())
                        }
                        Text(wording("最多 4 页，每页 JPEG 不超过 1 MB。截图会以 image_url 数据 URL 发送，可能增加模型费用；不会发送 PDF 原文件。", "Up to four JPEG pages, at most 1 MB each. Images are sent as image_url data URLs and may add model cost; the original PDF is never uploaded."))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    } else if selectedModel?.supportsVision != true {
                        Text(wording("要补充截图，请先在模型设置中确认并开启“支持图片输入”。", "To add images, first confirm and enable image input in Model Settings."))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    let unreadable = pages.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.number)
                    if !unreadable.isEmpty {
                        Text(wording("第 \(unreadable.map(String.init).joined(separator: ", ")) 页未识别出文字，必须用视觉模型附加这些页；如果超过 4 页，请先拆分文件。", "No text was found on pages \(unreadable.map(String.init).joined(separator: ", ")). Add these pages with a vision model; split the file if there are more than four."))
                            .font(.system(size: 11)).foregroundStyle(Palette.warning)
                    }
                    Text(wording("只有点击生成后，提取的文字和你选的截图才会发送到所选模型；本机 OCR 也可能识别错公式、表格和双栏顺序。上限 20 MB、120 页、100 万字符（含页码标记），不会静默截断。所选模型须有足够的上下文容量，长文会增加费用。", "Extracted text and selected images go to your model only after Generate. Local OCR can misread formulas, tables, and two-column order. Limits: 20 MB, 120 pages, 1,000,000 characters including page labels; no silent truncation. Your model must have enough context capacity; long sources increase costs."))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(22).card()
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Palette.warning)
                        .padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Palette.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                if processing { HStack { ProgressView().controlSize(.small); Text(processingStage).foregroundStyle(.secondary) } }
                if let preview, let draft {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Eyebrow(text: "REVIEW DRAFT")
                                Text(preview.title).font(EditorialType.title(27))
                                Text(wording("模型提议 · \(preview.claims.count) 条论断 · \(preview.atomicExperiments.count) 个原子实验 · \(preview.evidenceLinks.count + preview.relations.count) 条连线", "Model proposal · \(preview.claims.count) claims · \(preview.atomicExperiments.count) atomic tests · \(preview.evidenceLinks.count + preview.relations.count) links"))
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button(wording("放大预览", "Focus Preview"), systemImage: "arrow.up.left.and.arrow.down.right") { showPreviewFocus = true }
                                .buttonStyle(QuietButtonStyle())
                            Button(wording("导出 JSON…", "Export JSON…"), systemImage: "square.and.arrow.up", action: { exportJSON(draft) })
                                .buttonStyle(QuietButtonStyle())
                        }
                        Text(wording("请逐项核对原文页码、方法、观察结果与连线。模型提议不是证明；下方显示的是将要保存的结构。导入的文献实验会标为文献来源，而不是你的实测记录。", "Check every page citation, method, observed result, and link against the PDF. A model proposal is not proof. Paper-reported tests are marked as literature sources, not your own measurements."))
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
                        if let analysis = draft.analysis {
                            DisclosureGroup(wording("详细阅读：方法、结果与局限", "Detailed reading: methods, findings, and limitations")) {
                                PaperAnalysisView(analysis: analysis, language: store.workspace.language).padding(.vertical, 16)
                                DisclosureGroup(store.assistantText("图面板逻辑预览", "Figure-panel logic preview")) {
                                    FigurePanelLogicView(analysis: analysis, readingID: preview.id, language: store.workspace.language,
                                        supplement: {
                                            let record = savedReadingID.flatMap { id in store.workspace.literatureReadings.first { $0.id == id } }
                                                ?? LiteratureReading(id: preview.id, fileName: fileName, fingerprint: fingerprint, pageCount: pages.count, graph: preview, analysis: draft.analysis)
                                            panelSupplement = PanelLogicSupplementTarget(reading: record, source: (try? PDFTextBudget.source(pages, language: store.workspace.language)) ?? "")
                                        })
                                        .padding(.vertical, 16)
                                }
                            }
                        }
                        ScienceArgumentView(question: preview, language: store.workspace.language)
                        graph(preview)
                        HStack {
                            if savedReadingID == nil {
                                Button(wording("审阅后存入文献阅读库", "Save to Literature Library"), systemImage: "checkmark", action: save)
                                    .buttonStyle(QuietButtonStyle(prominent: true)).disabled(store.readOnly)
                            } else {
                                Label(wording("已存入本机工作区", "Saved to the local workspace"), systemImage: "checkmark.circle")
                                    .foregroundStyle(Palette.success)
                                Button(wording("打开文献阅读库", "Open Literature Library"), action: openLiterature).buttonStyle(QuietButtonStyle())
                            }
                            Spacer()
                        }
                    }
                }
            }.frame(maxWidth: 1250, alignment: .leading).padding(34).frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
        .onDisappear { generationTask?.cancel(); renderTask?.cancel(); readingTask?.cancel(); extractionTask?.cancel() }
        .onChange(of: selectedModel?.supportsVision) { _, supportsVision in
            if supportsVision != true { includePageImages = false }
        }
        .sheet(item: $manualExchange) { exchange in
            ManualPaperExchangeView(exchange: exchange, initiallyCopied: manualPromptCopied) { imported, graph in
                guard exchange.fingerprint == fingerprint, exchange.pageCount == pages.count,
                      exchange.language == store.workspace.language else {
                    throw WorkspaceError.invalid(wording("PDF 或语言已经变更，请复制新的提示词。", "The PDF or language changed. Copy a fresh prompt."))
                }
                draft = imported; preview = graph; savedReadingID = nil; errorMessage = nil
            }
        }
        .sheet(item: $panelSupplement) { target in
            PanelLogicSupplementView(target: target, language: store.workspace.language, archivedPDF: nil,
                saveAllowed: !store.readOnly) { exchange, analysis in
                    guard exchange.language == store.workspace.language, exchange.reading.fingerprint == fingerprint,
                          exchange.pageCount == pages.count, exchange.reading.analysis == draft?.analysis else {
                        throw WorkspaceError.invalid(wording("PDF 或阅读草稿已改变，请重新打开补充。", "The PDF or reading draft changed. Reopen the supplement."))
                    }
                    try exchange.validateApplication(analysis)
                    if savedReadingID != nil { try store.applyPanelLogicSupplement(exchange, analysis: analysis) }
                    draft?.analysis = analysis
                }
        }
        .sheet(isPresented: $showImagePreview) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text(wording("将发送的页面截图", "Page Images to Send")).font(EditorialType.title(24)); Spacer(); Button(wording("完成", "Done")) { showImagePreview = false }.buttonStyle(QuietButtonStyle()) }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(imagePreviews, id: \.number) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(wording("第 \(item.number) 页", "Page \(item.number)")).font(.system(size: 12, weight: .semibold))
                                if let image = NSImage(data: item.jpeg) { Image(nsImage: image).resizable().scaledToFit().frame(width: 370, height: 500) }
                            }
                        }
                    }.padding(.bottom, 8)
                }
            }.padding(22).frame(width: 850, height: 620).background(Palette.canvas)
        }
        .sheet(isPresented: $showPreviewFocus) {
            if let preview {
                let width = min(1500, max(980, (NSScreen.main?.visibleFrame.width ?? 1360) - 60))
                let height = min(920, max(630, (NSScreen.main?.visibleFrame.height ?? 800) - 80))
                VStack(spacing: 0) {
                    HStack {
                        Text(wording("PDF 图谱预览", "PDF Graph Preview")).font(EditorialType.title(24))
                        Spacer()
                        Button(wording("完成", "Done")) { showPreviewFocus = false }.buttonStyle(QuietButtonStyle())
                    }.padding(20)
                    graph(preview, height: height - 220).padding(.horizontal, 20).padding(.bottom, 20)
                }.frame(width: width, height: height).background(Palette.canvas)
            }
        }
    }

    private func graph(_ question: ScientificQuestion, height: CGFloat = 550) -> some View {
        ScienceMindMapView(question: question, language: store.workspace.language, canEdit: false,
            canMoveNodes: savedReadingID == nil, experimentName: { _ in "" },
            moveNode: { id, point in
                guard preview != nil else { return false }
                preview?.graphPositions[id.uuidString] = point
                return true
            },
            resetLayout: { preview?.graphPositions = [:] }, addClaim: {}, addAtom: {},
            editQuestion: {}, editClaim: { _ in }, editAtom: { _ in }, linkClaim: { _ in }, linkAtom: { _ in }, canvasHeight: height)
    }

    private func choosePDF() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= 20_000_000 else {
                throw WorkspaceError.invalid(wording("PDF 必须小于 20 MB。", "PDF must be under 20 MB."))
            }
            let data = try Data(contentsOf: url)
            fileName = url.lastPathComponent
            fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12).description
            pdfData = data; pages = []; draft = nil; preview = nil; savedReadingID = nil; errorMessage = nil
            imagePreviews = []; includePageImages = false; imagePageInput = ""
            reading = true
            readingTask = Task { @MainActor in
                defer { reading = false; readingTask = nil; extractionTask = nil }
                do {
                    let worker = Task.detached(priority: .userInitiated) { try PDFLocalReader.read(data) }
                    extractionTask = worker
                    let result = try await worker.value
                    try Task.checkCancellation()
                    pages = result.pages
                } catch is CancellationError { errorMessage = wording("本机读取已取消。", "Local reading was cancelled.") }
                catch { pdfData = nil; errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func generate() {
        guard !pages.isEmpty, !processing, let pdfData else { return }
        processing = true; errorMessage = nil; draft = nil; preview = nil; savedReadingID = nil
        let capturedPages = pages, capturedName = fileName, capturedFingerprint = fingerprint, capturedModelID = modelID
        let capturedIncludeImages = includePageImages
        let capturedImageInput = imagePageInput
        generationTask = Task { @MainActor in
            defer { processing = false; generationTask = nil; renderTask = nil }
            do {
                var images: [SciencePDFImage] = []
                if capturedIncludeImages {
                    let numbers = try selectedImagePages(capturedImageInput, in: capturedPages)
                    let worker = Task.detached(priority: .userInitiated) { try PDFLocalReader.screenshots(numbers, from: pdfData) }
                    renderTask = worker
                    images = try await worker.value
                }
                let result = try await store.proposeScienceGraph(from: capturedPages, fileName: capturedName,
                    fingerprint: capturedFingerprint, modelID: capturedModelID, images: images, progress: { processingStage = $0 })
                try Task.checkCancellation()
                draft = result.0; preview = result.1
            } catch is CancellationError {
                errorMessage = wording("解析已取消，未保存图谱。", "Extraction cancelled; no graph was saved.")
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func openManualExchange(copyPrompt: Bool) {
        do {
            let exchange = try ManualPaperExchange(pages: pages, fileName: fileName, fingerprint: fingerprint, language: store.workspace.language)
            manualPromptCopied = false
            if copyPrompt {
                NSPasteboard.general.clearContents()
                manualPromptCopied = NSPasteboard.general.setString(exchange.prompt, forType: .string)
            }
            manualExchange = exchange; errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func selectedImagePages(_ raw: String, in pages: [SciencePDFPage]) throws -> [Int] {
        if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try PDFLocalReader.pageNumbers(raw, pageCount: pages.count)
        }
        let unreadable = pages.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.number)
        guard unreadable.count <= PDFLocalReader.maxImagePages else {
            throw WorkspaceError.invalid(wording("未识别页超过 4 页，请先拆分 PDF。", "More than four pages were unreadable; split the PDF first."))
        }
        if unreadable.isEmpty { return [1] }
        return unreadable.count < PDFLocalReader.maxImagePages && !unreadable.contains(1) ? [1] + unreadable : unreadable
    }

    private func previewSelectedImages() {
        guard let pdfData else { return }
        do {
            let numbers = try selectedImagePages(imagePageInput, in: pages)
            Task { @MainActor in
                do {
                    imagePreviews = try await Task.detached(priority: .userInitiated) { try PDFLocalReader.screenshots(numbers, from: pdfData) }.value
                    showImagePreview = true; errorMessage = nil
                } catch { errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func save() {
        guard let preview, let pdfData, savedReadingID == nil else { return }
        let reading = LiteratureReading(fileName: fileName, fingerprint: fingerprint,
                                       pageCount: pages.count, graph: preview, analysis: draft?.analysis)
        do { try store.saveLiteratureReading(reading, originalPDF: pdfData); savedReadingID = reading.id; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func exportJSON(_ value: SciencePDFImport) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "science-graph.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
