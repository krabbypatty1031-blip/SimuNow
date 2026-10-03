import Foundation

/// Where a seat sits relative to openings. Used only for display names, not heat.
public enum SeatPlace: Sendable, Equatable {
    case nearWindow
    case nearDoor
    case other

    /// Window wins when both are close. Uses wall-normal distance plus how far
    /// the seat sits past the opening span, so a seat facing a window counts
    /// even if it is not at the patch centre.
    public static func classify(seat: Seat, geometry: RoomGeometry) -> SeatPlace {
        let threshold = 0.35 * min(geometry.sizeX.value, geometry.sizeY.value)
        var nearestWindow = Double.infinity
        var nearestDoor = Double.infinity
        for opening in geometry.openings {
            let distance = openingDistance(from: seat.position, to: opening, in: geometry)
            switch opening.kind {
            case .window: nearestWindow = min(nearestWindow, distance)
            case .door: nearestDoor = min(nearestDoor, distance)
            }
        }
        if nearestWindow <= threshold { return .nearWindow }
        if nearestDoor <= threshold { return .nearDoor }
        return .other
    }

    /// Combined wall-normal and along-wall miss. Zero along-wall miss means
    /// the seat is in front of the opening.
    private static func openingDistance(from seat: Position3D, to opening: Opening, in geometry: RoomGeometry) -> Double {
        let s: Double
        let normal: Double
        switch opening.wall {
        case .xMin:
            s = seat.y
            normal = seat.x
        case .xMax:
            s = seat.y
            normal = geometry.sizeX.value - seat.x
        case .yMin:
            s = seat.x
            normal = seat.y
        case .yMax:
            s = seat.x
            normal = geometry.sizeY.value - seat.y
        }
        let along: Double
        if s < opening.s0.value {
            along = opening.s0.value - s
        } else if s > opening.s1.value {
            along = s - opening.s1.value
        } else {
            along = 0
        }
        return (normal * normal + along * along).squareRoot()
    }
}

/// User-visible labels. Wire keys, hashes and solver names stay in the model.
public enum UserFacingCopy: Sendable {
    /// Tokens that must never appear in a default (unfolded) label.
    public static let forbiddenDefaultTokens = [
        "L1", "L2", "z0", "z1", "s0", "s1",
        "q_cool_w", "p_elec_w", "inputHash",
        "PMV", "PPD", "mrtC", "JSONL", "stale",
        "EnergyPlus", "OpenFOAM", "xMin", "xMax", "yMin", "yMax",
        "buoyantBoussinesqSimpleFoam", "worker"
    ]

    public static func containsForbiddenDefaultToken(_ text: String) -> Bool {
        forbiddenDefaultTokens.contains { text.contains($0) }
    }

    public static func wallTitle(_ wall: WallFace) -> String {
        switch wall {
        case .xMin: "左墙"
        case .xMax: "右墙"
        case .yMin: "近侧墙"
        case .yMax: "远侧墙"
        }
    }

    public static func sourceTitle(_ source: ParameterSource) -> String {
        switch source {
        case .scan: "扫描"
        case .measured: "实测"
        case .manufacturer: "设备说明书"
        case .user: "自己填写"
        case .preset: "模板预设"
        case .assumed: "暂用假设"
        }
    }

    public static func fieldTitle(_ path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        let last = parts.last ?? path
        if last.hasPrefix("omitted") {
            return omittedAssumptionTitle(path)
        }
        let inComfort = parts.contains("comfort")
        let inHVAC = parts.contains("hvac")
        switch last {
        case "setpointC": return inHVAC ? "空调设定温度" : "设定温度"
        case "supplyTemperatureC": return "出风温度"
        case "supply": return "出风口"
        case "returnTerminal": return "回风口"
        case "supplySpeedMs": return "出风速度"
        case "supplyAirflowM3s": return "出风量"
        case "outdoorAirM3s": return "室外新风"
        case "cop": return "能效比"
        case "occupantCount": return "人数"
        case "occupantSensibleW": return "每人散热量"
        case "lightingW": return "灯光散热"
        case "equipmentW": return "电器散热"
        case "schedule": return "使用时间"
        case "sizeX": return "长度"
        case "sizeY": return "宽度"
        case "sizeZ": return "高度"
        case "northYawDegrees": return "哪面墙朝北"
        case "s0": return "沿墙起点"
        case "s1": return "沿墙终点"
        case "z0": return "离地高度"
        case "z1": return "上沿高度"
        case "heatFluxWm2": return "窗户得热"
        case "mrtC": return "周围表面温度"
        case "rhPct": return "湿度"
        case "clo": return "衣着"
        case "met": return "活动强度"
        default:
            if inComfort { return comfortKeyTitle(last) }
            return "项目设置"
        }
    }

    public static func comfortKeyTitle(_ key: String) -> String {
        switch key {
        case "mrtC": "周围表面温度"
        case "rhPct": "湿度"
        case "clo": "衣着"
        case "met": "活动强度"
        default: "舒适设定"
        }
    }

    public static func metricTitle(_ name: String) -> String {
        switch name {
        case "q_cool_w": "制冷需求"
        case "p_elec_w": "空调用电功率"
        case "annual_kwh": "全年用电"
        case "seat_t_c_min": "座位最凉"
        case "seat_t_c_max": "座位最热"
        case "seat_u_mag_max": "座位最大风速"
        case "seat_pmv_min": "冷热是否合适（偏低）"
        case "seat_pmv_max": "冷热是否合适（偏高）"
        case "seat_ppd_max": "可能觉得不舒服的比例"
        case "seat_pass_ratio": "合适的座位"
        default: "结果"
        }
    }

    public static func runStateTitle(_ state: RunState) -> String {
        switch state {
        case .queued: "排队中"
        case .validating: "正在核对"
        case .meshing: "正在准备房间"
        case .solving: "正在估算"
        case .postprocessing: "正在整理结果"
        case .checking: "正在检查"
        case .succeeded: "已完成"
        case .failed: "没有完成"
        case .cancelled: "已取消"
        }
    }

    public static func qualityTitle(_ quality: QualityState) -> String {
        switch quality {
        case .notEvaluated: "尚未检查"
        case .passed: "已通过检查"
        case .failed: "未通过检查"
        }
    }

    public static func freshnessTitle(_ freshness: ResultFreshness?) -> String {
        switch freshness {
        case .current: "按当前房间"
        case .stale: "房间改过了，请重新估算"
        case nil: "还没有结果"
        }
    }

    public static func eventTitle(_ type: String) -> String {
        switch type {
        case "accepted": "已接受"
        case "progress": "进行中"
        case "completed": "完成"
        case "failed": "没有完成"
        case "quality": "检查"
        default: "进度"
        }
    }

    /// Solver monitors stay generic so the unfolded UI never names a binary.
    public static func monitorTitle(_ monitor: String?) -> String {
        guard let monitor, !monitor.isEmpty else { return "" }
        let lower = monitor.lowercased()
        if lower.contains("energyplus") { return "能耗计算" }
        if lower.contains("foam") || lower.contains("mesh") { return "气流场计算" }
        if lower.contains("quality") { return "结果检查" }
        return "计算"
    }

    public static func openingTitle(kind: OpeningKind, wall: WallFace, indexOnWall: Int, countOnWall: Int) -> String {
        let place = wallTitle(wall)
        let noun = kind == .window ? "窗" : "门"
        if countOnWall > 1 {
            return "\(place)的\(noun) \(indexOnWall + 1)"
        }
        return "\(place)的\(noun)"
    }

    public static func openingTitle(for opening: Opening, in openings: [Opening]) -> String {
        let matches = openings.filter { $0.kind == opening.kind && $0.wall == opening.wall }
        let index = matches.firstIndex(where: { $0.id == opening.id }) ?? 0
        return openingTitle(kind: opening.kind, wall: opening.wall, indexOnWall: index, countOnWall: matches.count)
    }

    public static func seatTitle(index: Int, near: SeatPlace) -> String {
        switch near {
        case .nearWindow: "靠窗座位 \(index + 1)"
        case .nearDoor: "靠门座位 \(index + 1)"
        case .other: "座位 \(index + 1)"
        }
    }

    public static func seatTitle(seat: Seat, seats: [Seat], geometry: RoomGeometry?) -> String {
        let index = seats.firstIndex(where: { $0.id == seat.id }) ?? 0
        let place = geometry.map { SeatPlace.classify(seat: seat, geometry: $0) } ?? .other
        return seatTitle(index: index, near: place)
    }

    public static func furnitureTitle(index: Int) -> String {
        "家具 \(index + 1)"
    }

    public static func terminalTitle(isSupply: Bool) -> String {
        isSupply ? "出风口" : "回风口"
    }

    public static func omittedAssumptionTitle(_ note: String) -> String {
        let key = note.replacingOccurrences(of: "omitted:", with: "").trimmingCharacters(in: .whitespaces)
        switch key {
        case "envelope_u_value":
            return "墙的保温尚未填写，不会按 0 计算"
        case "weather_file":
            return "天气文件尚未填写，不会按 0 计算"
        case "furniture_boxes":
            return "家具尚未细画，不会按 0 计算"
        default:
            return "有一项尚未填写，不会按 0 计算"
        }
    }

    public static func gateTitle(_ stored: String) -> String {
        stored
            .replacingOccurrences(of: "温度门", with: "偏热或偏冷")
            .replacingOccurrences(of: "风速门", with: "风偏大")
            .replacingOccurrences(of: "PMV门", with: "冷热不合适")
    }

    /// User-visible numbers stay at two fraction digits. Stored physics values are unchanged.
    public static func displayNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    public static func displayQuantity(_ value: Double, unit: String) -> String {
        "\(displayNumber(value)) \(unit)"
    }

    public static func displayRange(_ min: Double, _ max: Double, unit: String) -> String {
        "\(displayNumber(min)) – \(displayNumber(max)) \(unit)"
    }

}
