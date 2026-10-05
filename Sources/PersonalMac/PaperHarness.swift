import CryptoKit
import Foundation
import PersonalCore

@MainActor extension PersonalStore {
    func executePaperRequest(_ request: PaperRequest, history: [WireMessage], selection: ModelSelection, runID: UUID) async throws -> (String, [UUID]) {
        if request.action == .save {
            guard let id = request.artifact_id, workspace.artifacts.contains(where: { $0.id == id && $0.kind == .paperDraft }) else {
                throw WorkspaceError.invalid(assistantText("请指定待审阅文献草稿。", "Specify a paper reading draft to save."))
            }
            try await confirmTool(assistantText("将这份文献阅读草稿保存到阅读库？", "Save this reviewed paper draft to the Literature Library?"))
            _ = try savePaperArtifact(id)
            return (assistantText("文献阅读记录已保存，未写入个人实验记录。", "The paper reading was saved separately from your own experiments."), [id])
        }
        let pages: [SciencePDFPage]
        let name: String
        let fingerprint: String
        var storageName: String?
        if let id = request.reading_id {
            guard let reading = workspace.literatureReadings.first(where: { $0.id == id }), let stored = reading.pdfStorageName else {
                return (assistantText("这条记录没有原始 PDF，请重新附上论文后再分析。", "This record has no archived PDF. Attach the original paper to analyze it again."), [])
            }
            let url = file.directory.appendingPathComponent("LiteraturePDFs").appendingPathComponent(stored)
            let data = try Data(contentsOf: url)
            pages = try await Task.detached(priority: .userInitiated) { try PDFLocalReader.read(data).pages }.value
            name = reading.fileName; fingerprint = reading.fingerprint; storageName = stored
        } else {
            let input = history.last(where: { $0.role == "user" })?.content ?? ""
            let regex = try NSRegularExpression(pattern: #"\[PAGE (\d+); (PDF TEXT LAYER|LOCAL OCR|NO LOCAL TEXT)\]\n"#)
            let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
            guard !matches.isEmpty else {
                return (assistantText("请在对话中附上 PDF，或指定阅读库中的文献。我会先精读方法、结果与局限，再构建待审阅图谱。", "Attach a PDF here or select a paper from the Literature Library. I will read its methods, findings, and limitations before building a reviewable evidence map."), [])
            }
            let ns = input as NSString
            // The local attachment wrapper is not part of the last PDF page.
            // Keep any task written after it out of the source budget, too.
            let lastPageStart = NSMaxRange(matches.last!.range)
            let endings = ["\nEnd of source.\n", "\n资料结束。\n"].compactMap { marker -> Int? in
                let range = ns.range(of: marker, options: .backwards)
                return range.location != NSNotFound && range.location >= lastPageStart ? range.location : nil
            }
            let sourceEnd = endings.max() ?? ns.length
            pages = matches.enumerated().map { offset, match in
                let start = NSMaxRange(match.range), end = offset + 1 < matches.count ? matches[offset + 1].range.location : sourceEnd
                var text = ns.substring(with: NSRange(location: start, length: end - start))
                if offset + 1 < matches.count, text.hasSuffix("\n\n") { text.removeLast(2) }
                return SciencePDFPage(number: Int(ns.substring(with: match.range(at: 1))) ?? 0,
                    text: text,
                    source: ns.substring(with: match.range(at: 2)) == "LOCAL OCR" ? .localOCR : .textLayer)
            }
            name = "attached-paper.pdf"
            fingerprint = SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        let result = try await proposeScienceGraph(from: pages, fileName: name, fingerprint: fingerprint, modelID: selection.1.id, focus: request.focus) { stage in
            try? self.runEvent(runID, stage)
        }
        let reading = LiteratureReading(fileName: name, fingerprint: fingerprint, pageCount: pages.count,
            pdfStorageName: storageName, graph: result.1, analysis: result.0.analysis)
        var artifact = AssistantArtifact(kind: .paperDraft, title: result.0.analysis?.paper_title ?? result.1.title)
        try Task.checkCancellation()
        artifact.paper = reading
        try commit { $0.artifacts.append(artifact) }
        try runEvent(runID, assistantText("已生成文献阅读草稿，等待审阅。", "Paper reading draft created for review."), artifactID: artifact.id)
        return (assistantText("已生成详细文献阅读记录与证据图谱，请审阅后存入文献阅读库。", "A detailed reading and evidence map are ready. Review the draft before saving it to the Literature Library."), [artifact.id])
    }

    @discardableResult func savePaperArtifact(_ id: UUID) throws -> UUID {
        guard let artifact = workspace.artifacts.first(where: { $0.id == id && $0.kind == .paperDraft }), let paper = artifact.paper else {
            throw WorkspaceError.invalid("Paper draft not found.")
        }
        if let applied = artifact.appliedID { return applied }
        try commit { current in
            guard let index = current.artifacts.firstIndex(where: { $0.id == id }), !current.literatureReadings.contains(where: { $0.id == paper.id }) else { throw WorkspaceError.invalid("Paper draft already saved or changed.") }
            try paper.validated()
            current.literatureReadings.append(paper); current.artifacts[index].appliedID = paper.id
        }
        return paper.id
    }
}
