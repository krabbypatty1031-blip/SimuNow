import SwiftUI
import SimuCore
import SimuReporting
import SimuSimulation
#if os(macOS)
import AppKit
#endif

/// Report page (P5): preview the fixed report snapshot and export a basic PDF.
/// Export is blocked with an explanation when no run is eligible (completed + quality-passed + current).
public struct ReportView: View {
    let session: ProjectSession
    let runStore: RunStore
    let exporter: any ReportExporter
    @State private var message: String?
    @State private var exportedURL: URL?

    public init(session: ProjectSession, runStore: RunStore, exporter: any ReportExporter = BasicReportExporter()) {
        self.session = session
        self.runStore = runStore
        self.exporter = exporter
    }

    private var content: ReportContent? {
        let rows = ComparisonModel.rows(project: session.project, records: runStore.records, currentHashes: runStore.currentHashes)
        return ReportBuilder.content(project: session.project, rows: rows,
                                     cards: ComparisonModel.cards(rows: rows))
    }

    public var body: some View {
        Group {
            if let content {
                preview(content)
            } else {
                ContentUnavailableView {
                    Label("结果不可用于报告", systemImage: "doc.text")
                } description: {
                    Text("报告只收录已完成、质量通过且未过期（输入哈希一致）的运行。请先在「计算任务」页运行 L0 估算。")
                }
            }
        }
        .alert("报告导出", isPresented: .constant(message != nil)) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func preview(_ content: ReportContent) -> some View {
        List {
            Section {
                Text("报告将包含 \(content.entries.count) 个有效方案、\(content.cards.count) 张建议卡、假设与限制清单。")
                    .font(.caption)
                Text("范围：L0 平均估算（非 CFD）；代表日不推全年；缺失不填 0；位置级舒适未评价。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("收录的运行") {
                ForEach(content.entries, id: \.runID) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.scenarioName).font(.callout)
                        Text("run \(String(entry.runID.prefix(8))) · 哈希 \(String(entry.inputHash.prefix(12)))… · \(entry.quality)")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                exportButton(content)
            }
        }
    }

    private func exportButton(_ content: ReportContent) -> some View {
        #if os(macOS)
        Button("导出 PDF 报告…") { export(content) }
        #else
        VStack(alignment: .leading, spacing: 4) {
            Button("生成 PDF 报告") { export(content) }
            if let exportedURL {
                ShareLink(item: exportedURL) { Label("分享报告", systemImage: "square.and.arrow.up") }
            }
        }
        #endif
    }

    private func export(_ content: ReportContent) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(session.project.name)-报告.pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await exporter.export(content, to: url)
                message = "已导出：\(url.lastPathComponent)"
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
        }
        #else
        Task {
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(session.project.name)-报告.pdf")
                try await exporter.export(content, to: url)
                exportedURL = url
                message = "已生成，可用下方「分享报告」导出。"
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
        }
        #endif
    }
}
