import SwiftUI
import SimuCore

@MainActor
public struct AnalysisReadinessView: View {
    public let readiness: AnalysisReadiness
    public init(readiness: AnalysisReadiness) { self.readiness = readiness }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(readiness.eligible ? "此方法输入可用" : "此方法需要补充或修复", systemImage: readiness.eligible ? "checkmark.circle" : "exclamationmark.circle")
            ForEach(Array(readiness.blockers.enumerated()), id: \.offset) { _, issue in
                VStack(alignment: .leading) { Text(issue.message); Text(issue.fieldPath).font(.caption).foregroundStyle(.secondary) }
            }
            if !readiness.warnings.isEmpty {
                DisclosureGroup("未采用项与方法说明（\(readiness.warnings.count)）") {
                    ForEach(Array(readiness.warnings.enumerated()), id: \.offset) { _, issue in Text(issue.message).font(.caption) }
                }
            }
        }.accessibilityElement(children: .contain)
    }
}
