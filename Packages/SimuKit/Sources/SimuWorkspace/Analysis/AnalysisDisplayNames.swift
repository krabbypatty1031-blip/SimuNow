import Foundation
import SimuCore

extension ElectricalPowerBasis {
    var consumerTitle: String {
        switch self {
        case .measuredAverage: String(localized: "实测平均电功率")
        case .declaredScenario: String(localized: "声明运行情景")
        case .ratedContinuous: String(localized: "额定功率连续运行假设")
        }
    }
}
extension ParameterSource {
    var consumerTitle: String {
        switch self {
        case .scan: String(localized: "扫描几何")
        case .measured: String(localized: "现场实测")
        case .manufacturer: String(localized: "厂家资料")
        case .user: String(localized: "用户录入")
        case .preset: String(localized: "预设")
        case .assumed: String(localized: "明确假设")
        }
    }
}
func heatFieldTitle(_ field: String) -> String {
    switch field {
    case "conductance": "围护总传热系数 UA"
    case "indoorTemperature": "工况室内温度"
    case "outdoorTemperature": "工况室外温度"
    case "density": "空气密度"
    case "specificHeat": "空气比热容"
    case "outdoorAir": "室外新风显热"
    case "infiltration": "渗透交换显热"
    case "internalSensibleHeat", "internalSensible": "内部显热源"
    case "solarSensibleHeat", "solarSensible": "太阳显热"
    case "outdoorAirVolumeFlow": "室外交换风量"
    case "supplyAirVolumeFlow": "设备循环送风量"
    case "supplyTemperature": "工况送风温度"
    default: field
    }
}
func comparisonRankingTitle(_ value: String) -> String {
    switch value {
    case "cannotRank": "输入或口径不足，不能排序"
    case "sameDeclaredEstimate": "声明情景的估算相同"
    case "overlapNoStableRanking": "情景范围重叠，不能稳定排序"
    case "disjointDeclaredEnvelopes": "声明端点范围分离；只适用于此情景"
    case "qualitativeOnly": "只比较几何关系，不做数值排名"
    default: "不支持的排序口径；请查看原固定证据"
    }
}
