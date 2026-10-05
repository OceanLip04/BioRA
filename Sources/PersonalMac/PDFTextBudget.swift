import Foundation
import PersonalCore

/// One source budget for local extraction, API analysis, copied prompts and attachments.
/// Includes page labels and separators, but not model instructions or attachment wrappers.
enum PDFTextBudget {
    static let maxCharacters = 1_000_000
    static let assistantRequestCharacters = maxCharacters + 50_000
    static let previousHistoryCharacters = 80_000

    static func pageText(_ page: SciencePDFPage) -> String {
        let label = page.source == .localOCR ? "LOCAL OCR" : page.source == .unreadable ? "NO LOCAL TEXT" : "PDF TEXT LAYER"
        return "[PAGE \(page.number); \(label)]\n\(page.text)"
    }

    static func validate(_ count: Int, language: AppLanguage? = nil) throws {
        guard count <= maxCharacters else {
            let english = "PDF text exceeds 1,000,000 characters (including page labels). Split the PDF; nothing was silently truncated."
            let chinese = "PDF 文字超过 100 万字符（含页码标记），请拆分文件；内容不会静默截断。"
            throw WorkspaceError.invalid(language == .english ? english : language == .chinese ? chinese : english + " / " + chinese)
        }
    }

    static func source(_ pages: [SciencePDFPage], language: AppLanguage? = nil) throws -> String {
        let text = pages.map(pageText).joined(separator: "\n\n")
        try validate(text.count, language: language)
        return text
    }
}
