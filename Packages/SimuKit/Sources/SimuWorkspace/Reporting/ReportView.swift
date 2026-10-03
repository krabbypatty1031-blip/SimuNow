import SwiftUI
import SimuCore
import SimuReporting
import SimuSimulation
import SimuDesignSystem
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
                    Label("先完成一次估算", systemImage: "doc.text")
                } description: {
                    Text("到「用电估算」完成计算。结果通过检查，且设置没有改变后，就能导出报告。")
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
                RoomPageIntro("把方案留存下来", detail: "报告包含 \(content.entries.count) 个方案、建议和参数说明。")
                Text("这是选定一天的平均估算，不能用来判断各座位舒适度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("将收录的方案") {
                ForEach(content.entries, id: \.runID) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.scenarioName).font(.callout)
                        DisclosureGroup("计算记录") {
                            Text("编号 \(String(entry.runID.prefix(8))) · 哈希 \(String(entry.inputHash.prefix(12)))… · \(entry.quality)")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        .font(.caption)
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
