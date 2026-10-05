import AppKit
import PDFKit
import PersonalCore
import Vision

enum PDFTextSource: String, Sendable {
    case textLayer, localOCR, unreadable
}

struct PDFReadResult: Sendable {
    let pages: [SciencePDFPage]
    var ocrPages: [Int] { pages.filter { $0.source == .localOCR }.map(\.number) }
    var unreadablePages: [Int] { pages.filter { $0.source == .unreadable }.map(\.number) }
}

/// Uses only macOS frameworks. PDF bytes stay local until a separate Generate action.
enum PDFLocalReader {
    static let maxFileBytes = 20_000_000
    static let maxPages = 120
    static let maxCharacters = PDFTextBudget.maxCharacters
    static let maxImagePages = 4
    static let maxImageBytes = 1_000_000

    static func read(_ data: Data) throws -> PDFReadResult {
        guard data.count <= maxFileBytes, let document = PDFDocument(data: data),
              !document.isLocked, (1...maxPages).contains(document.pageCount) else {
            throw WorkspaceError.invalid("PDF must be unlocked, under 20 MB, and contain 1–120 pages. / PDF 需未加密、小于 20 MB、页数为 1–120。")
        }
        var pages: [SciencePDFPage] = []
        var total = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw WorkspaceError.invalid("A PDF page could not be read. / 无法读取某一 PDF 页。") }
            let native = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let broken = native.filter { $0 == "�" }.count > max(2, native.count / 10)
            var text = native
            var source: PDFTextSource = native.isEmpty ? .unreadable : .textLayer
            if native.count < 12 || broken {
                if let jpeg = try? jpegData(for: page, longestSide: 1900, quality: 0.82),
                   let recognized = try? recognize(jpeg), !recognized.isEmpty,
                   native.isEmpty || broken || recognized.count > native.count * 2 {
                    text = recognized
                    source = .localOCR
                }
            }
            let extracted = SciencePDFPage(number: index + 1, text: text, source: source)
            total += PDFTextBudget.pageText(extracted).count + (pages.isEmpty ? 0 : 2)
            try PDFTextBudget.validate(total)
            pages.append(extracted)
        }
        return PDFReadResult(pages: pages)
    }

    static func screenshots(_ numbers: [Int], from data: Data) throws -> [SciencePDFImage] {
        guard !numbers.isEmpty, numbers.count <= maxImagePages, Set(numbers).count == numbers.count,
              let document = PDFDocument(data: data), !document.isLocked else {
            throw WorkspaceError.invalid("Select up to four distinct PDF pages for visual context. / 视觉补充最多选择四个不同页码。")
        }
        return try numbers.map { number in
            try Task.checkCancellation()
            guard (1...document.pageCount).contains(number), let page = document.page(at: number - 1) else {
                throw WorkspaceError.invalid("A selected screenshot page is outside the PDF. / 截图页码超出 PDF 范围。")
            }
            var jpeg: Data?
            for (side, quality) in [(1500.0, 0.72), (1200.0, 0.64), (1000.0, 0.55), (800.0, 0.48)] {
                let candidate = try jpegData(for: page, longestSide: side, quality: quality)
                if candidate.count <= maxImageBytes { jpeg = candidate; break }
            }
            guard let jpeg else {
                throw WorkspaceError.invalid("A page image exceeds 1 MB. Try a simpler page. / 单页截图超过 1 MB，请选择较简单的页面。")
            }
            return SciencePDFImage(number: number, jpeg: jpeg)
        }
    }

    static func pageNumbers(_ raw: String, pageCount: Int) throws -> [Int] {
        var values: [Int] = []
        for part in raw.split(separator: ",", omittingEmptySubsequences: false) {
            let token = part.trimmingCharacters(in: .whitespaces)
            if let number = Int(token), (1...pageCount).contains(number) { values.append(number); continue }
            let ends = token.split(separator: "-", omittingEmptySubsequences: false)
            guard ends.count == 2, let first = Int(ends[0]), let last = Int(ends[1]),
                  first >= 1, first <= last, last <= pageCount, last - first < maxImagePages else {
                throw WorkspaceError.invalid("Use page numbers like 1,3-4 within the PDF. / 请填写 PDF 范围内的页码，如 1,3-4。")
            }
            values.append(contentsOf: first...last)
        }
        var seen: Set<Int> = []
        let unique = values.filter { seen.insert($0).inserted }
        guard !unique.isEmpty, unique.count <= maxImagePages else {
            throw WorkspaceError.invalid("Choose 1–4 distinct page images. / 请选择 1–4 张不同页的截图。")
        }
        return unique
    }

    private static func jpegData(for page: PDFPage, longestSide: CGFloat, quality: Double) throws -> Data {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { throw WorkspaceError.invalid("PDF page has no renderable area. / PDF 页无法渲染。") }
        let scale = longestSide / max(bounds.width, bounds.height)
        let size = NSSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let image = page.thumbnail(of: size, for: .cropBox)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw WorkspaceError.invalid("PDF page image could not be encoded. / PDF 页截图编码失败。")
        }
        return jpeg
    }

    private static func recognize(_ jpeg: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = false // Preserve scientific names, formulas, and units as seen.
        try VNImageRequestHandler(data: jpeg).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> (Double, Double, String)? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return (Double(observation.boundingBox.midY), Double(observation.boundingBox.minX), text)
        }.sorted { abs($0.0 - $1.0) > 0.012 ? $0.0 > $1.0 : $0.1 < $1.1 }
        return lines.map(\.2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
