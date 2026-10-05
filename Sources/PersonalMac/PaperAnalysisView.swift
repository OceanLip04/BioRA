import PersonalCore
import SwiftUI

/// A reading document, deliberately separate from the user's own evidence graph.
struct PaperAnalysisView: View {
    let analysis: PaperAnalysis
    let language: AppLanguage
    private func t(_ zh: String, _ en: String) -> String { language == .english ? en : zh }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(analysis.paper_title).font(.title2.weight(.semibold))
            Text(([analysis.authors.joined(separator: ", "), analysis.year, analysis.doi].filter { !$0.isEmpty }).joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            field(t("核心科学问题", "Central question"), analysis.central_question)
            field(t("背景与知识缺口", "Background and gap"), analysis.background_and_gap)
            field(t("全文概述", "Summary"), analysis.summary)
            Divider()
            Text(t("研究设计与方法", "Design and methods")).font(.headline)
            ForEach(analysis.methods, id: \.key) { method in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        field(t("研究体系", "System / sample"), method.system)
                        field(t("设计", "Design"), method.design)
                        field(t("干预 / 暴露", "Intervention / exposure"), method.intervention)
                        field(t("对照", "Controls"), method.controls)
                        field(t("测量指标", "Readouts"), method.measurements)
                        field(t("样本量与重复", "Sample size / replicates"), method.sample_size)
                        field(t("统计方法", "Statistics"), method.statistics)
                    }.padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(method.title).fontWeight(.medium)
                        citation(method.source_pages, figures: method.figure_refs)
                    }
                }
            }
            Divider()
            Text(t("主要发现", "Findings")).font(.headline)
            ForEach(analysis.findings, id: \.key) { finding in
                VStack(alignment: .leading, spacing: 8) {
                    Text(finding.statement).fontWeight(.medium)
                    field(t("定量结果", "Quantitative result"), finding.quantitative_result)
                    field(t("不确定性", "Uncertainty"), finding.uncertainty)
                    field(t("解释", "Interpretation"), finding.interpretation)
                    if !finding.method_keys.isEmpty {
                        Text(t("对应方法：", "Methods: ") + analysis.methods.filter { finding.method_keys.contains($0.key) }.map(\.title).joined(separator: "; "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    citation(finding.source_pages, figures: finding.figure_refs)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
            statements(t("结论与适用范围", "Conclusions and scope"), analysis.conclusions)
            statements(t("局限", "Limitations"), analysis.limitations)
            statements(t("未解问题与下一步检验", "Open questions and next checks"), analysis.open_questions)
            if let discussion = analysis.discussion {
                Divider()
                Text(t("Discussion · 综合讨论", "Discussion · synthesis")).font(.headline)
                Text(discussion.summary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(discussion.origin == .reported ? t("原文报告", "Reported") : t("审慎综合，需核对", "Inferred synthesis; verify"))
                    citation(discussion.source_pages)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.font(.body).textSelection(.enabled).frame(maxWidth: 900, alignment: .leading)
    }
    @ViewBuilder private func field(_ title: String, _ text: String) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func citation(_ pages: [Int], figures: [String] = []) -> some View {
        Text(([pages.isEmpty ? "" : t("PDF 页 ", "PDF pp. ") + pages.map(String.init).joined(separator: ", ")] + figures).filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.caption).foregroundStyle(.secondary)
    }
    @ViewBuilder private func statements(_ title: String, _ values: [PaperAnalysis.Statement]) -> some View {
        if !values.isEmpty {
            Divider()
            Text(title).font(.headline)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                VStack(alignment: .leading, spacing: 5) {
                    Text(value.text)
                    HStack {
                        Text(value.origin == .reported ? t("原文报告", "Reported") : t("审慎推断", "Inferred"))
                        citation(value.source_pages)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
