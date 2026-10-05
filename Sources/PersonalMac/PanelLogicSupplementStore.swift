import PersonalCore

@MainActor extension PersonalStore {
    func applyPanelLogicSupplement(_ exchange: PanelLogicSupplementExchange, analysis: PaperAnalysis) throws {
        guard workspace.language == exchange.language else { throw WorkspaceError.invalid("Language changed. Copy a fresh prompt. / 语言已改变，请重新复制提示词。") }
        try exchange.validateApplication(analysis)
        try commit { current in
            guard let index = current.literatureReadings.firstIndex(where: { $0.id == exchange.reading.id }),
                  current.literatureReadings[index].fingerprint == exchange.reading.fingerprint,
                  current.literatureReadings[index].fileName == exchange.reading.fileName,
                  current.literatureReadings[index].pageCount == exchange.reading.pageCount,
                  current.literatureReadings[index].analysis == exchange.reading.analysis else {
                throw WorkspaceError.invalid(exchange.t("原阅读已变更或已补充，请重新打开；未覆盖内容。", "The reading changed or was already supplemented. Reopen it; nothing was overwritten."))
            }
            current.literatureReadings[index].analysis = analysis
            if current.literatureReadings[index].pageCount == nil { current.literatureReadings[index].pageCount = exchange.pageCount }
            try current.literatureReadings[index].validated()
        }
    }
}
