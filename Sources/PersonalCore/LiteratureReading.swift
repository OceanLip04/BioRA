import Foundation

/// A graph extracted from a publication, kept separate from the user's own questions and experiments.
public struct LiteratureReading: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var fileName: String
    public var fingerprint: String
    public var pageCount: Int?
    /// Managed PDF in the workspace's LiteraturePDFs directory. Legacy imports may not have one.
    public var pdfStorageName: String?
    public var importedAt: Date
    public var graph: ScientificQuestion
    public var analysis: PaperAnalysis?

    public init(id: UUID = UUID(), fileName: String, fingerprint: String, pageCount: Int?,
                pdfStorageName: String? = nil, importedAt: Date = Date(), graph: ScientificQuestion, analysis: PaperAnalysis? = nil) {
        self.id = id; self.fileName = fileName; self.fingerprint = fingerprint
        self.pageCount = pageCount; self.pdfStorageName = pdfStorageName
        self.importedAt = importedAt; self.graph = graph; self.analysis = analysis
    }

    public func validated() throws {
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fileName.count <= 300, !fingerprint.isEmpty, fingerprint.count <= 128,
              pageCount.map({ (1...500).contains($0) }) ?? true,
              pdfStorageName.map({ name in
                  name.count == 68 && name.hasSuffix(".pdf") && name.dropLast(4).utf8.allSatisfy {
                      (48...57).contains($0) || (97...102).contains($0)
                  }
              }) ?? true,
              graph.atomicExperiments.allSatisfy({ $0.experimentID == nil }),
              graph.claims.allSatisfy({ $0.experimentIDs.isEmpty }) else {
            throw WorkspaceError.invalid("文献阅读记录的出处或实验引用无效。")
        }
        try graph.validated(experimentIDs: [])
        if let analysis, let pageCount { try analysis.validated(pageCount: pageCount, language: .chinese) }
    }

    /// Recognize only records created by the former PDF importer. Hand-authored questions remain untouched.
    public static func fromLegacyPDFQuestion(_ question: ScientificQuestion) -> LiteratureReading? {
        guard question.atomicExperiments.allSatisfy({ $0.experimentID == nil }),
              question.claims.allSatisfy({ $0.experimentIDs.isEmpty }) else { return nil }
        let markers = [
            ("AI 从 PDF《", "》提取（SHA-256 前缀 ", "）"),
            ("AI-extracted from PDF “", "” (SHA-256 prefix ", ")")
        ]
        for (start, middle, end) in markers {
            guard let startRange = question.detail.range(of: start),
                  let middleRange = question.detail.range(of: middle, range: startRange.upperBound..<question.detail.endIndex),
                  let endRange = question.detail.range(of: end, range: middleRange.upperBound..<question.detail.endIndex) else { continue }
            let fileName = String(question.detail[startRange.upperBound..<middleRange.lowerBound])
            let fingerprint = String(question.detail[middleRange.upperBound..<endRange.lowerBound])
            guard !fileName.isEmpty, !fingerprint.isEmpty,
                  fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { continue }
            let reading = LiteratureReading(id: question.id, fileName: fileName, fingerprint: fingerprint,
                                            pageCount: nil, importedAt: question.createdAt, graph: question)
            guard (try? reading.validated()) != nil else { continue }
            return reading
        }
        return nil
    }
}
