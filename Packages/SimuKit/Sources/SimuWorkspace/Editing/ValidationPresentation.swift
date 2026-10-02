import Foundation
import SimuCore

/// UI wording stays outside the cross-language validation contract.
public enum ValidationPresentation {
    public static func describe(_ issue: ValidationIssue) -> String {
        let message = issue.code.hasPrefix("weather_asset_") || ["baseline_reference", "package_metadata", "project_contract"].contains(issue.code)
            ? issue.message : message(for: issue.code)
        return "\(message)（\(fieldPath(issue.path))）"
    }
    public static func message(for code: String) -> String {
        switch code {
        case "parameter_range": "数值超出允许范围"
        case "missing_parameter", "required_input": "输入待补充"
        case "source_required": "请补充参数出处或假设说明"
        case "unknown_reason": "请说明参数未知的原因"
        case "uncertainty_bounds": "区间应包含当前值，并说明其含义"
        case "surface_topology": "矩形房间需要六个不同表面"
        case "opening_bounds": "门窗超出所属表面"
        case "opening_overlap": "同一表面的门窗发生重叠"
        case "obstacle_bounds": "家具超出房间"
        case "obstacle_overlap": "家具发生重叠"
        case "point_bounds": "点位超出允许的房间区域"
        case "point_in_solid": "点位位于家具内部或表面"
        case "geometry_uncheckable", "surface_uncheckable": "请补全几何尺寸"
        case "duplicate_id": "对象身份重复"
        case "dangling_reference": "对象引用已失效"
        case "duplicate_assignment": "同一对象被重复配置"
        case "unsupported_type": "当前版本不能编辑或计算此扩展类型"
        case "room_count": "当前计算配置需要一个房间"
        case "scenario_required": "请创建或选择方案"
        case "device_count": "当前计算配置需要一台空调"
        case "port_topology": "请配置送风口和回风口"
        case "direction_unit": "风口方向需要为单位向量"
        case "flow_area_speed": "风量、面积与风速不一致"
        case "mass_balance_uncheckable": "请补全流量和密度以检查质量平衡"
        case "recirculation_balance": "送回风质量流量不平衡"
        case "outdoor_exchange_balance": "室外交换流量不平衡"
        case "envelope_incomplete": "围护表面配置待补充"
        case "windows_incomplete": "窗热工配置待补充"
        case "control_incomplete": "空调控制配置待补充"
        case "ventilation_incomplete": "房间通风配置待补充"
        case "opening_states_incomplete": "门窗开启状态待补充"
        case "boundary_exclusive": "表面温度与热流边界只能选用一种"
        case "boundary_unresolved": "表面边界等待 L1 计算提供"
        case "schedule_interval", "schedule_overlap": "时间区间无效、未排序或重叠"
        case "schedule_coverage": "时间表需要覆盖完整代表日，停用时段显式设为零"
        case "sample_required": "座位需要有效采样点"
        case "representative_date": "代表日格式或日期无效"
        case "time_zone": "请选择有效的 IANA 时区"
        case "relative_path": "资源必须使用包内有效相对路径"
        case "content_hash": "资源 SHA-256 格式无效"
        case "currency_required", "currency": "请填写三位大写币种代码"
        case "contract_error": "项目结构不符合当前数据契约"
        default: "输入需要检查：\(code)"
        }
    }
    public static func fieldPath(_ path: String) -> String {
        if path.isEmpty { return "项目" }
        return path.split(separator: "/").map { part in
            if let index = Int(part) { return "第\(index + 1)项" }
            return names[String(part)] ?? String(part)
        }.joined(separator: " / ")
    }
    private static let names: [String: String] = [
        "geometry": "空间", "rooms": "房间", "obstacles": "家具", "shape": "形状",
        "payload": "参数", "dimensions": "尺寸", "width": "宽度", "depth": "深度", "height": "高度",
        "northAngle": "北向", "surfaces": "表面", "openings": "门窗", "offsetU": "水平偏移", "offsetV": "垂直偏移",
        "scenarios": "方案", "inputs": "输入", "usage": "使用条件", "seats": "座位", "occupants": "人员",
        "equipment": "设备热源", "samples": "采样点", "position": "位置", "hvac": "空调", "definition": "设备性能",
        "ports": "风口", "direction": "方向", "area": "面积", "volumeFlow": "风量", "speed": "风速", "density": "密度",
        "supplyTemperature": "送风温度", "controls": "控制", "setpoint": "设定温度", "sensorPosition": "传感点",
        "envelope": "围护", "windows": "窗热工", "boundary": "热边界", "uValue": "传热系数",
        "ventilation": "室外通风", "environment": "环境", "weather": "天气", "representativeDate": "代表日",
        "timeZone": "时区", "schedule": "时间表", "intervals": "时间区间", "source": "来源", "reason": "未知原因",
        "evaluation": "评价", "cost": "费用", "currency": "币种", "uncertainty": "不确定区间"
    ]
}
