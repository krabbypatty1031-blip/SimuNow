import Foundation
import SimuCore
import SimuSimulation

public struct NativeRestorationInput: Equatable, Sendable {
    public let project: ProjectDocument
    public let configuration: AnalysisConfigurationStore?
    public let scenarioID: UUID?
    public let revision: UUID
    public init(project: ProjectDocument, configuration: AnalysisConfigurationStore?, scenarioID: UUID?, revision: UUID) {
        self.project = project; self.configuration = configuration; self.scenarioID = scenarioID; self.revision = revision
    }
}
public enum NativeEvidenceRestoration {
    public static func restoreCost(_ input: NativeRestorationInput, artifacts: [NativeAnalysisArtifact], entries: [String: ProjectPackageEntry]) throws -> CostEvaluationRecord? {
        guard let scenario = input.project.scenarios.first(where: { $0.id == input.scenarioID }),
              let configuration = input.configuration?.configuration(scenarioID: scenario.id, kind: .powerEstimate),
              let current = try? AnalysisInputResolver().request(project: input.project, scenarioID: scenario.id, method: .init(kind: .powerEstimate), configuration: configuration),
              let parent = artifacts.first(where: { $0.request.method == current.method && $0.request.identity.scenarioID == scenario.id && $0.request.identity.inputHash == current.identity.inputHash }),
              case .powerEstimate(let payload) = parent.result.payload else { return nil }
        let tariff = CostEvaluationConfiguration(requestedWindows: payload.requestedWindows, currency: scenario.evaluation.cost.currency,
            tariffs: scenario.evaluation.cost.tariffs.map { .init(startMinute: $0.startMinute, endMinute: $0.endMinute, rate: $0.rate) })
        let hash = try AnalysisHasher().evaluationHash(identity: parent.result.identity, evaluationConfiguration: JSONTreeCoding.encode(tariff))
        return try NativeCostEvaluationCodec.load(hash: hash, parent: parent, entries: entries)
    }
    /// At most one matching run per registered method plus the first saved comparison's references.
    /// Historical inputs remain unchanged; no unavailable record is reconstructed from current inputs.
    public static func restore(_ input: NativeRestorationInput, entries: [String: ProjectPackageEntry]) throws -> [NativeAnalysisArtifact] {
        var loaded: [UUID: NativeAnalysisArtifact] = [:]
        let index = NativeArtifactCodec().index(entries: entries, projectID: input.project.id)
        if let scenario = input.scenarioID {
            for kind in AnalysisKind.allCases {
                try Task.checkCancellation()
                guard let config = input.configuration?.configuration(scenarioID: scenario, kind: kind),
                      let current = try? AnalysisInputResolver().request(project: input.project, scenarioID: scenario, method: .init(kind: kind), configuration: config) else { continue }
                for entry in index where entry.scenarioID == scenario {
                    try Task.checkCancellation()
                    guard let artifact = try? NativeArtifactCodec().load(runID: entry.id, entries: entries, projectID: input.project.id),
                          artifact.request.method == current.method, artifact.request.identity.inputHash == current.identity.inputHash,
                          artifact.result.checks.state == .passed else { continue }
                    loaded[entry.id] = artifact; break
                }
            }
        }
        for (id, data) in FixedComparisonArtifacts.data(entries: entries).prefix(12) {
            try Task.checkCancellation()
            guard let comparison = try? FixedComparisonArtifacts.load(data, entries: entries, projectID: input.project.id), comparison.record.id == id else { continue }
            for run in comparison.record.snapshot.runs {
                if loaded[run.runID] == nil { loaded[run.runID] = try NativeArtifactCodec().load(runID: run.runID, entries: entries, projectID: input.project.id) }
            }
            break
        }
        return loaded.values.sorted { $0.request.identity.runID.uuidString < $1.request.identity.runID.uuidString }
    }
}
