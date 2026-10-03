import Foundation
import SimuCore

public enum PreviewRecommendationRules {
    public static func suggestions(request: LocalAnalysisRequest, result: LocalAnalysisResult,
                                   currentInputHash: String) throws -> [SuggestionCard] {
        try NativeAnalysisCodec().validateResult(result)
        try AnalysisInputResolver().validate(request)
        guard request.identity == result.identity, request.method == result.method,
              result.assumptions == request.resolvedInput.adoptedAssumptions,
              result.identity.inputHash == currentInputHash, result.checks.state == .passed,
              case .airflowPreview(let payload) = result.payload,
              case .airflowPreview(let profile) = request.resolvedInput.configuration.payload,
              payload.profileID == profile.profileID, payload.profileVersion == profile.profileVersion else {
            throw ProjectDataError.contract("建议需要当前输入匹配、方法检查通过的固定规则证据。")
        }
        guard payload.validEmissionCount > 0 else {
            throw ProjectDataError.contract("没有有效规则路径。请检查风口与几何，不生成当前建议。")
        }
        return try payload.relations.map { relation in
            let expectedRule: String
            switch relation.state {
            case .occluded: expectedRule = "preview.occlusion.v1"
            case .notEvaluated: expectedRule = "preview.unsupported.v1"
            case .intersectsAssumedPath, .outsideAssumedPath: expectedRule = "preview.pathIntersection.v1"
            }
            guard relation.ruleID == expectedRule else { throw ProjectDataError.contract("不支持的关注点规则，不能生成当前建议。") }
            let message: String
            switch relation.state {
            case .intersectsAssumedPath:
                message = "在当前假设路径下，此关注点与路径相交。可尝试将风向移开该位置，再生成候选比较；这不是实测吹风或舒适结论。"
            case .occluded:
                message = "在当前假设路径下，家具挡住了此方向。请检查遮挡家具；其后区域未模拟绕流，调整后需重新预览。"
            case .outsideAssumedPath:
                message = "此点位于当前假设路径范围外。模型未评价现实气流，不能据此判断无风或舒适。"
            case .notEvaluated:
                message = "此点不可评价。" + (relation.missingReason.map { $0.reason + "。" } ?? "")
                    + "请核对采样位置、房间边界及家具内部位置；不能用缺失结果参加排序。"
            }
            return .init(identity: result.identity, ruleID: relation.ruleID, seatID: relation.seatID,
                         sampleID: relation.sampleID, obstacleID: relation.hitEntityID,
                         profileID: payload.profileID, profileVersion: payload.profileVersion,
                         relation: relation.state, message: message)
        }
    }
}
