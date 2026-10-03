import SwiftUI
import SimuCore

/// Validation issues grouped by gate; tapping an issue locates the entity when identifiable.
public struct ValidationIssueListView: View {
    let session: ProjectSession
    var onOpen: (SettingTarget) -> Void

    public init(session: ProjectSession, onOpen: @escaping (SettingTarget) -> Void = { _ in }) {
        self.session = session
        self.onOpen = onOpen
    }

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
                            if let target = session.settingTarget(for: issue) {
                                Button {
                                    onOpen(target)
                                } label: {
                                    Label("去填写 · \(InputPresentation.placeTitle(target))", systemImage: "arrow.right.circle")
                                }
                                .font(.caption)
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
