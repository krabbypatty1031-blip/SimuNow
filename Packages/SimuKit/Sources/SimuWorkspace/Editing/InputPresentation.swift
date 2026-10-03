import Foundation
import SimuCore

/// Display names only. Raw paths/codes remain available in the diagnostic disclosure.
enum InputPresentation {
    static func spaceTitle(_ type: SpaceType) -> String {
        switch type {
        case .office: "办公室"
        case .classroom: "教室"
        case .home: "家中房间"
        case .publicSpace: "公共空间"
        }
    }

    static func unitTitle(_ unit: String) -> String {
        switch unit {
        case "degC": "°C"
        case "deg": "°"
        case "m2": "m²"
        case "m3/s": "m³/s"
        case "kg/m3": "kg/m³"
        case "1": ""
        default: unit
        }
    }
    static func sourceTitle(_ source: ParameterSource) -> String {
        switch source {
        case .measured: "实测"
        case .manufacturer: "设备说明书"
        case .preset: "模板预设"
        case .scan: "扫描"
        case .user: "自己填写"
        case .assumed: "暂用假设"
        }
    }

    static func metricTitle(_ name: String) -> String {
        switch name {
        case "averageRoomTemperature": "房间平均温度"
        case "coolingLoadPeak": "最高制冷需求"
        case "dailyCoolingEnergy": "一天制冷需求（热量）"
        case "estimatedElectricEnergy": "一天预计用电"
        case "capacityAdequate": "空调制冷能力是否够用"
        case "dailyCost": "一天预计费用"
        default: name
        }
    }

    static func fieldTitle(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        let names = [
            "northAngle": "房间朝向", "width": "宽度", "depth": "进深", "height": "高度",
            "offsetU": "沿墙的位置", "offsetV": "离地高度", "setpoint": "空调设定温度",
            "supplyTemperature": "出风温度", "coolingCapacity": "制冷能力", "electricalPower": "额定用电功率",
            "cop": "能效比 COP", "area": "风口面积", "volumeFlow": "风量", "speed": "风速",
            "density": "空气密度", "direction": "出风方向", "temperature": "墙面边界温度",
            "heatFlux": "墙面热流", "uValue": "传热系数", "shgc": "窗户太阳得热系数",
            "shadingFactor": "遮阳系数", "outdoorAir": "新风量", "exhaustAir": "排风量",
            "infiltration": "渗入风量", "exfiltration": "渗出风量", "openFraction": "门窗打开比例",
            "indoorHumidity": "室内湿度", "outdoorHumidity": "室外湿度", "outdoorTemperature": "室外温度",
            "representativeDate": "计算日期", "timeZone": "所在时区", "weather": "天气文件",
            "relativePath": "天气文件位置", "sha256": "天气文件校验码", "sensible": "散热量",
            "latent": "水汽带来的热量", "convectiveFraction": "传给空气的热量比例",
            "activity": "活动强度", "clothing": "衣着厚度", "fraction": "使用比例",
            "schedule": "使用时间", "intervals": "使用时间", "samples": "座位检查点",
            "hvac": "空调", "controls": "空调设置", "ventilation": "通风设置", "surfaces": "墙面设置",
            "windows": "窗户设置", "openings": "门窗", "rooms": "房间", "scenarios": "方案",
            "rate": "电价", "amount": "报价", "currency": "币种"
        ]
        let field = parts.reversed().first(where: { names[$0] != nil }).flatMap { names[$0] } ?? "项目设置"
        let context: String
        if parts.contains("occupants") { context = "人员" }
        else if parts.contains("equipment") { context = "电器" }
        else if parts.contains("hvac") { context = "空调" }
        else if parts.contains("envelope") { context = "墙与窗" }
        else if parts.contains("ventilation") { context = "通风" }
        else { context = "" }
        return context.isEmpty || field == context ? field : "\(context) · \(field)"
    }

    static func faceTitle(_ face: SurfaceFace) -> String {
        switch face {
        case .xMin: "左墙"
        case .xMax: "右墙"
        case .yMin: "近侧墙"
        case .yMax: "远侧墙"
        case .floor: "地板"
        case .ceiling: "天花板"
        }
    }

    static func placeTitle(_ target: SettingTarget) -> String {
        switch target.selection {
        case .room: "房间设置"
        case .opening: "门窗设置"
        case .obstacle: "家具设置"
        case .device: "空调设置"
        case .port: "风口设置"
        case .seat: "座位设置"
        case .occupant: "人员设置"
        case .equipment: "电器设置"
        case .control: "温度与开机时间"
        case .environment: "天气与温湿度"
        case .cost: "电价与报价"
        }
    }

    static func action(for issue: ValidationIssue) -> String {
        switch issue.code {
        case "missing_parameter", "required_input": "请补充这项信息。"
        case "source_reference", "source_note", "source_required", "unknown_reason": "请填写数值出处或未填写的原因。"
        case "parameter_range": "数值超出允许范围，请核对数值和单位。"
        case "opening_bounds": "门窗超出墙面，请调整位置或尺寸。"
        case "opening_overlap": "门窗重叠，请调整位置。"
        case "obstacle_bounds", "point_bounds": "对象在房间外，请移回房间内。"
        case "furniture_overlap", "obstacle_overlap": "家具重叠，请调整位置。"
        case "point_in_solid": "检查点在家具中，请调整位置。"
        case "flow_area_speed": "风量应等于风口面积乘以风速，请核对这三个数值。"
        case "recirculation_balance": "送风和回风不平衡，请核对风量与空气密度。"
        case "outdoor_exchange_balance": "进入和排出的室外空气不平衡，请核对通风设置。"
        case "device_count": "当前计算支持一台空调，请核对设备数量。"
        case "boundary_unresolved": "墙面条件还没有计算结果，目前无法继续。"
        case "direction_unit": "方向数值不符合要求，请查看高级出风设置。"
        case "schedule_coverage": "使用时间需要覆盖一整天，停用时把比例设为 0。"
        case "representative_date": "请填写有效日期，例如 2026-10-03。"
        case "time_zone": "请填写有效时区，例如 Asia/Hong_Kong。"
        case "relative_path", "content_hash": "请核对天气文件的位置与校验码。"
        case "currency", "currency_required": "请填写三位币种代码，例如 HKD。"
        default: "这项设置需要核对；具体原因可展开查看。"
        }
    }
}
