import SwiftUI
import SimuCore

/// Validation issues grouped by gate; tapping an issue locates the entity when identifiable.
public struct ValidationIssueListView: View {
    let session: ProjectSession

    public init(session: ProjectSession) { self.session = session }

    public var body: some View {
        List {
            Section {
                statusRow("项目完整性", passes: session.validation.passes(.projectIntegrity))
                statusRow("计算输入就绪", passes: session.validation.passes(.inputPreparation))
            }
            let issues = session.validation.issues
            if issues.isEmpty {
                Section { Text("没有校验问题。").foregroundStyle(.secondary) }
            } else {
                Section("问题（\(issues.count)）") {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Button {
                            if let id = issue.entityID { session.selection = session.selection(forEntityID: id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(issue.code).font(.caption.monospaced())
                                    Spacer()
                                    Text(issue.blocks == [.projectIntegrity, .inputPreparation] ? "完整性" : "输入")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(issue.message).font(.caption)
                                Text(issue.path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(issue.entityID == nil)
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

/// Scenario list: current scenario, duplication as candidates, per-scenario validation status.
public struct ScenarioListView: View {
    let session: ProjectSession

    public init(session: ProjectSession) { self.session = session }

    public var body: some View {
        List {
            Section("方案") {
                ForEach(session.project.scenarios, id: \.id) { scenario in
                    HStack {
                        Button {
                            session.currentScenarioID = scenario.id
                        } label: {
                            HStack {
                                Text(scenario.name)
                                if scenario.id == session.currentScenarioID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            session.duplicateScenario(scenario.id, name: scenario.name + " 候选")
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("复制为候选方案（实体身份保留，可独立改参数）")
                    }
                }
            }
            Section {
                Text("候选对比与指标展示在计算接入后开放；比较使用相同天气、人数与时段口径。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
