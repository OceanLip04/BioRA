import AppKit
import PersonalCore
import SwiftUI

struct LiteratureReadingsView: View {
    let store: PersonalStore
    let importPDF: () -> Void
    @State private var selectedID: UUID?
    @State private var content = 0
    @State private var panelSupplement: PanelLogicSupplementTarget?

    private var readings: [LiteratureReading] {
        store.workspace.literatureReadings.sorted { $0.importedAt > $1.importedAt }
    }
    private var selected: LiteratureReading? {
        readings.first { $0.id == selectedID } ?? readings.first
    }
    private func wording(_ chinese: String, _ english: String) -> String {
        store.assistantText(chinese, english)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "LITERATURE LIBRARY")
                        Text(wording("文献阅读库", "Literature Library")).font(EditorialType.title(23))
                    }
                    Spacer()
                    Button { importPDF() } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).help(wording("解析新 PDF", "Import a PDF"))
                }.padding(18)
                Rectangle().fill(Palette.line).frame(height: 0.5)
                if readings.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(wording("这里保存从论文提取的阅读图谱，与自己的科学问题分开。", "Paper reading maps live here, separate from your own scientific questions."))
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Button(wording("解析 PDF", "Import PDF"), action: importPDF)
                            .buttonStyle(QuietButtonStyle(prominent: true))
                    }.padding(20)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(readings) { reading in
                                Button { selectedID = reading.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(reading.graph.title).font(.system(size: 12, weight: .semibold))
                                            .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(reading.fileName).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selected?.id == reading.id ? Palette.selection : .clear,
                                                    in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }.padding(10)
                    }
                }
            }.frame(width: 294).background(Palette.surface)
            Rectangle().fill(Palette.line).frame(width: 0.5)
            if let reading = selected {
                GeometryReader { geometry in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(reading.fileName).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                Text(wording("PDF 文献提取 · 页码需对照原文核实", "Extracted from a paper · verify page citations against the PDF"))
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                Text(wording("SHA-256 前缀 \(reading.fingerprint)", "SHA-256 prefix \(reading.fingerprint)"))
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
                            }
                            Spacer()
                            if let name = reading.pdfStorageName {
                                let url = store.file.directory.appendingPathComponent("LiteraturePDFs").appendingPathComponent(name)
                                Button(wording("打开原 PDF", "Open PDF"), systemImage: "doc.richtext") {
                                    NSWorkspace.shared.open(url)
                                }.buttonStyle(QuietButtonStyle())
                                    .disabled(!FileManager.default.fileExists(atPath: url.path))
                            } else {
                                Text(wording("旧记录未保存原 PDF", "Original PDF unavailable for this older record"))
                                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                        }.padding(.horizontal, 20).padding(.top, 16)
                        Picker(wording("内容", "Content"), selection: $content) {
                            Text(wording("研究主线", "Mainline")).tag(0)
                            Text(wording("详细阅读", "Reading")).tag(1)
                            Text(wording("论证画布", "Argument Canvas")).tag(2)
                            Text(wording("图面板逻辑", "Figure Logic")).tag(3)
                        }.pickerStyle(.segmented).frame(maxWidth: 560).padding(.horizontal, 20)
                        if content == 0 {
                            ScrollView {
                                ScienceArgumentView(question: reading.graph, language: store.workspace.language)
                                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if content == 1 {
                            if let analysis = reading.analysis {
                                ScrollView { PaperAnalysisView(analysis: analysis, language: store.workspace.language).padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                            } else {
                                Text(wording("旧记录未保存详细阅读，请重新解析原 PDF。", "Detailed analysis is unavailable for this older reading. Reanalyze the original PDF."))
                                    .foregroundStyle(Palette.muted).padding(24)
                                Spacer()
                            }
                        } else if content == 3 {
                            ScrollView {
                                FigurePanelLogicView(analysis: reading.analysis, readingID: reading.id, language: store.workspace.language,
                                    canvasHeight: max(370, geometry.size.height - 230),
                                    supplement: { panelSupplement = PanelLogicSupplementTarget(reading: reading) }).padding(20)
                            }.id(reading.id)
                        } else {
                        ScienceMindMapView(question: reading.graph, language: store.workspace.language, canEdit: false,
                            canMoveNodes: !store.readOnly, experimentName: { _ in "" },
                            moveNode: { id, point in
                                do { try store.setLiteratureGraphPosition(readingID: reading.id, nodeID: id, point: point); store.errorMessage = nil; return true }
                                catch { store.errorMessage = error.localizedDescription; return false }
                            },
                            resetLayout: {
                                do { try store.resetLiteratureGraphLayout(readingID: reading.id); store.errorMessage = nil }
                                catch { store.errorMessage = error.localizedDescription }
                            }, addClaim: {}, addAtom: {},
                            editQuestion: {}, editClaim: { _ in }, editAtom: { _ in }, linkClaim: { _ in }, linkAtom: { _ in },
                            fitsAvailableHeight: true)
                            .padding(.horizontal, 20).padding(.bottom, 15)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical").font(.system(size: 32)).foregroundStyle(Palette.muted)
                    Text(wording("选择一篇文献开始阅读", "Select a paper to read"))
                        .font(EditorialType.title(24))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Palette.canvas)
            .sheet(item: $panelSupplement) { target in
                PanelLogicSupplementView(target: target, language: store.workspace.language,
                    archivedPDF: target.reading.pdfStorageName.map { store.file.directory.appendingPathComponent("LiteraturePDFs").appendingPathComponent($0) }, saveAllowed: !store.readOnly) { exchange, analysis in
                        try store.applyPanelLogicSupplement(exchange, analysis: analysis)
                    }
            }
    }
}
