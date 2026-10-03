import SwiftUI
import SimuCore

/// Validation issues grouped by gate; tapping an issue locates the entity when identifiable.
public struct ValidationIssueListView: View {
    let session: ProjectSession

    public init(session: ProjectSession) { self.session = session }

    public var body: some View {
        List {
            Section {
                statusRow("房间设置是否有效", passes: session.validation.passes(.projectIntegrity))
                statusRow("是否可以开始估算", passes: session.validation.passes(.inputPreparation))
            }
            let issues = session.validation.issues
            if issues.isEmpty {
                Section { Text("信息已齐，可以开始估算。").foregroundStyle(.secondary) }
            } else {
                Section("待补充或核对 · \(issues.count) 项") {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(InputPresentation.fieldTitle(issue.path)).font(.headline)
                            Text(InputPresentation.action(for: issue)).font(.subheadline).foregroundStyle(.secondary)
                            if let id = issue.entityID, let selection = session.selection(forEntityID: id) {
                                Button("在设置中选中") { session.selection = selection }
                                    .font(.caption)
                                Text("关闭此列表后，在右侧查看已选对象。").font(.caption2).foregroundStyle(.secondary)
                            }
                            DisclosureGroup("查看详细原因") {
                                Text(issue.message).font(.caption)
                                Text("\(issue.code)\n\(issue.path)")
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func statusRow(_ title: String, passes: Bool) -> some View {
        Label(title, systemImage: passes ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(passes ? .green : .orange)
    }
}
