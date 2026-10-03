import Foundation
import SimuCore

/// UI wording stays outside the cross-language validation contract.
public enum ValidationPresentation {
    public static func describe(_ issue: ValidationIssue) -> String {
        "\(message(for: issue))（\(fieldPath(issue.path))）"
    }
    public static func message(for issue: ValidationIssue) -> String {
        issue.code.hasPrefix("weather_asset_") || ["baseline_reference", "package_metadata", "project_contract"].contains(issue.code)
            ? issue.message : message(for: issue.code)
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
        "coolingCapacity": "制冷量", "electricalPower": "电功率", "cop": "COP", "heat": "热量", "sensible": "总显热", "latent": "潜热", "convectiveFraction": "对流比例", "activity": "活动水平", "clothing": "衣着热阻", "outdoorTemperature": "室外温度", "indoorHumidity": "室内相对湿度", "outdoorHumidity": "室外相对湿度", "outdoorAir": "室外新风", "exhaustAir": "室外排风", "infiltration": "渗风", "exfiltration": "外泄", "shgc": "太阳得热系数", "shadingFactor": "遮阳系数", "openFraction": "开启比例", "rate": "电价", "tariffs": "电价时段", "quotes": "报价", "amount": "金额", "startMinute": "开始时间", "endMinute": "结束时间", "fraction": "启用比例", "relativePath": "包内路径", "sha256": "文件摘要", "value": "数值", "state": "状态", "unit": "单位", "reference": "参考依据", "note": "备注", "lower": "下界", "upper": "上界", "meaning": "含义", "origin": "最小角位置", "name": "名称", "evaluation": "评价", "cost": "费用", "currency": "币种", "uncertainty": "不确定区间"
    ]
}

public enum FieldNavigation {
    public static func ordinal(_ path: String) -> Int? {
        let parts = path.split(separator: "/")
        for collection in ["intervals", "tariffs"] {
            if let index = parts.lastIndex(of: Substring(collection)), parts.indices.contains(index + 1),
               let value = Int(parts[index + 1]) { return value }
        }
        return nil
    }
    public static func field(_ path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if parts.contains("openings") {
            if parts.contains("width") { return "宽度（U）" }
            if parts.contains("height") { return "高度（V）" }
        }
        if parts.contains("obstacles") {
            if parts.contains("width") { return "宽度 X" }
            if parts.contains("depth") { return "深度 Y" }
            if parts.contains("height") { return "高度 Z" }
        }
        if parts.contains("windows"), parts.contains("uValue") { return "窗传热系数" }
        if parts.contains("ventilation"), parts.contains("density") { return "交换空气密度" }
        return parts.reversed().compactMap { titles[$0] }.first
    }
    public static func errorField(_ message: String) -> String? {
        titles.values.sorted { $0.count > $1.count }.first { message.contains($0) }
    }
    public static func objectName(project: ProjectDocument, path: String, entityID: UUID? = nil) -> String {
        if let id = entityID {
            for room in project.geometry.rooms {
                if room.id == id { return room.name }
                if let surface = room.surfaces.first(where: { $0.id == id }) { return room.name + " · " + RoomIssuePresentation.wallTitle(surface.face) }
                if let opening = room.openings.first(where: { $0.id == id }) {
                    let face = room.surfaces.first(where: { $0.id == opening.surfaceID })?.face
                    return room.name + " · " + (face.map(RoomIssuePresentation.wallTitle) ?? "表面") + " · " + (opening.kind == .window ? "窗" : "门")
                }
            }
            if let obstacle = project.geometry.obstacles.first(where: { $0.id == id }) { return obstacle.name }
            for scenario in project.scenarios {
                if scenario.id == id { return scenario.name }
                let input = scenario.inputs
                if let seat = input.usage.seats.first(where: { $0.id == id || $0.samples.contains { $0.id == id } }) { return scenario.name + " · " + seat.name }
                if let occupant = input.usage.occupants.first(where: { $0.id == id }) { return scenario.name + " · " + (input.usage.seats.first { $0.id == occupant.seatID }?.name ?? "失效的座位关联") + " · 人员" }
                if let device = input.hvac.first(where: { $0.id == id || $0.ports.contains { $0.id == id } }) { return scenario.name + " · " + device.name }
                if let control = input.controls.first(where: { $0.id == id }) { return scenario.name + " · " + (input.hvac.first { $0.id == control.deviceID }?.name ?? "失效的空调关联") + " · 温控" }
                if input.usage.equipment.contains(where: { $0.id == id }) { return scenario.name + " · " + InputDisplay.equipment(id) }
            }
        }
        let parts = path.split(separator: "/").map(String.init)
        func index(_ collection: String) -> Int? {
            guard let offset = parts.firstIndex(of: collection), parts.count > offset + 1 else { return nil }
            return Int(parts[offset + 1])
        }
        var inferred: UUID?
        if let ri = index("rooms"), project.geometry.rooms.indices.contains(ri) {
            let room = project.geometry.rooms[ri]
            inferred = room.id
            if let oi = index("openings"), room.openings.indices.contains(oi) { inferred = room.openings[oi].id }
        } else if let oi = index("obstacles"), project.geometry.obstacles.indices.contains(oi) { inferred = project.geometry.obstacles[oi].id }
        else if let si = index("scenarios"), project.scenarios.indices.contains(si) {
            let scenario = project.scenarios[si], input = scenario.inputs
            inferred = scenario.id
            if let seatIndex = index("seats"), input.usage.seats.indices.contains(seatIndex) { inferred = input.usage.seats[seatIndex].id }
            if let deviceIndex = index("hvac"), input.hvac.indices.contains(deviceIndex) { inferred = input.hvac[deviceIndex].id }
            if let equipmentIndex = index("equipment"), input.usage.equipment.indices.contains(equipmentIndex) { inferred = input.usage.equipment[equipmentIndex].id }
            if let occupantIndex = index("occupants"), input.usage.occupants.indices.contains(occupantIndex) { inferred = input.usage.occupants[occupantIndex].id }
        }
        if entityID == nil, let inferred {
            let name = objectName(project: project, path: path, entityID: inferred)
            return name + (field(path).map { " · " + $0 } ?? "")
        }
        return ValidationPresentation.fieldPath(path)
    }
    private static let titles: [String: String] = [
        "width": "宽度（X）", "depth": "进深（Y）", "height": "高度（Z）", "northAngle": "真北方位角",
        "offsetU": "U 偏移", "offsetV": "V 偏移", "position": "横向距离 X（m）", "origin": "横向距离 X（m）",
        "x": "横向距离 X（m）", "y": "纵向距离 Y（m）", "z": "离地高度 Z（m）",
        "direction": "水平角（°，+X 向 +Y）", "area": "有效面积", "volumeFlow": "体积流量", "speed": "风速", "density": "空气密度",
        "coolingCapacity": "制冷量", "electricalPower": "电功率", "cop": "COP", "supplyTemperature": "送风温度",
        "setpoint": "设定温度", "sensorPosition": "离地高度 Z（m）", "activity": "活动水平", "clothing": "衣着热阻",
        "sensible": "总显热", "latent": "潜热", "convectiveFraction": "对流比例", "uValue": "传热系数",
        "temperature": "表面温度", "heatFlux": "表面热流（有符号）", "amount": "报价金额",
        "outdoorTemperature": "室外温度", "indoorHumidity": "室内相对湿度", "outdoorHumidity": "室外相对湿度",
        "shgc": "太阳得热系数 SHGC", "shadingFactor": "遮阳系数", "openFraction": "开启比例", "rate": "电价",
        "representativeDate": "代表日", "timeZone": "时区", "currency": "币种代码，例如 CNY / USD（未知时留空）",
        "startMinute": "开始（HH:mm）", "endMinute": "结束（HH:mm）", "fraction": "启用 / 占用比例"
    ]
}
