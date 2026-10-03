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
/// Instance methods follow `language`; static wrappers use English (the default).
public struct UserFacingCopy: Sendable, Equatable {
    public var language: AppLanguage

    public static let english = UserFacingCopy(language: .english)
    public static let chinese = UserFacingCopy(language: .chinese)

    public init(language: AppLanguage = .english) {
        self.language = language
    }

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

    func t(_ en: String, zh: String) -> String {
        switch language {
        case .english: en
        case .chinese: zh
        }
    }

    public var listSeparator: String {
        t(", ", zh: "、")
    }

    // MARK: - Walls, sources, fields

    public func wallTitle(_ wall: WallFace) -> String {
        switch wall {
        case .xMin: t("Left wall", zh: "左墙")
        case .xMax: t("Right wall", zh: "右墙")
        case .yMin: t("Near wall", zh: "近侧墙")
        case .yMax: t("Far wall", zh: "远侧墙")
        }
    }

    public static func wallTitle(_ wall: WallFace) -> String {
        english.wallTitle(wall)
    }

    public func sourceTitle(_ source: ParameterSource) -> String {
        switch source {
        case .scan: t("Scan", zh: "扫描")
        case .measured: t("Measured", zh: "实测")
        case .manufacturer: t("Equipment datasheet", zh: "设备说明书")
        case .user: t("Entered by you", zh: "自己填写")
        case .preset: t("Template preset", zh: "模板预设")
        case .assumed: t("Working assumption", zh: "暂用假设")
        }
    }

    public static func sourceTitle(_ source: ParameterSource) -> String {
        english.sourceTitle(source)
    }

    public func fieldTitle(_ path: String) -> String {
        let parts = path.split(separator: ".").map(String.init)
        let last = parts.last ?? path
        if last.hasPrefix("omitted") {
            return omittedAssumptionTitle(path)
        }
        let inComfort = parts.contains("comfort")
        let inHVAC = parts.contains("hvac")
        switch last {
        case "setpointC": return inHVAC ? t("Setpoint temperature", zh: "空调设定温度") : t("Setpoint", zh: "设定温度")
        case "supplyTemperatureC": return t("Supply-air temperature", zh: "出风温度")
        case "supply": return t("Supply outlet", zh: "出风口")
        case "returnTerminal": return t("Return inlet", zh: "回风口")
        case "supplySpeedMs": return t("Supply-air speed", zh: "出风速度")
        case "supplyAirflowM3s": return t("Supply airflow", zh: "出风量")
        case "outdoorAirM3s": return t("Outdoor air", zh: "室外新风")
        case "cop": return t("Efficiency ratio", zh: "能效比")
        case "occupantCount": return t("Occupants", zh: "人数")
        case "occupantSensibleW": return t("Heat per person", zh: "每人散热量")
        case "lightingW": return t("Lighting heat", zh: "灯光散热")
        case "equipmentW": return t("Equipment heat", zh: "电器散热")
        case "schedule": return t("Occupied hours", zh: "使用时间")
        case "sizeX": return t("Length", zh: "长度")
        case "sizeY": return t("Width", zh: "宽度")
        case "sizeZ": return t("Height", zh: "高度")
        case "northYawDegrees": return t("Which wall faces north", zh: "哪面墙朝北")
        case "s0": return t("Start along the wall", zh: "沿墙起点")
        case "s1": return t("End along the wall", zh: "沿墙终点")
        case "z0": return t("Height above floor", zh: "离地高度")
        case "z1": return t("Top height", zh: "上沿高度")
        case "heatFluxWm2": return t("Window heat gain", zh: "窗户得热")
        case "mrtC": return t("Surrounding surface temperature", zh: "周围表面温度")
        case "rhPct": return t("Humidity", zh: "湿度")
        case "clo": return t("Clothing", zh: "衣着")
        case "met": return t("Activity", zh: "活动强度")
        default:
            if inComfort { return comfortKeyTitle(last) }
            return t("Project setting", zh: "项目设置")
        }
    }

    public static func fieldTitle(_ path: String) -> String {
        english.fieldTitle(path)
    }

    public func comfortKeyTitle(_ key: String) -> String {
        switch key {
        case "mrtC": t("Surrounding surface temperature", zh: "周围表面温度")
        case "rhPct": t("Humidity", zh: "湿度")
        case "clo": t("Clothing", zh: "衣着")
        case "met": t("Activity", zh: "活动强度")
        default: t("Comfort setting", zh: "舒适设定")
        }
    }

    public static func comfortKeyTitle(_ key: String) -> String {
        english.comfortKeyTitle(key)
    }

    public func metricTitle(_ name: String) -> String {
        switch name {
        case "q_cool_w": t("Cooling demand", zh: "制冷需求")
        case "p_elec_w": t("AC electric power", zh: "空调用电功率")
        case "annual_kwh": t("Yearly electricity", zh: "全年用电")
        case "seat_t_c_min": t("Coolest seat", zh: "座位最凉")
        case "seat_t_c_max": t("Warmest seat", zh: "座位最热")
        case "seat_u_mag_max": t("Highest seat air speed", zh: "座位最大风速")
        case "seat_pmv_min": t("Too cool (sensation)", zh: "冷热是否合适（偏低）")
        case "seat_pmv_max": t("Too warm (sensation)", zh: "冷热是否合适（偏高）")
        case "seat_ppd_max": t("Share who may feel uncomfortable", zh: "可能觉得不舒服的比例")
        case "seat_pass_ratio": t("Seats within range", zh: "合适的座位")
        default: t("Result", zh: "结果")
        }
    }

    public static func metricTitle(_ name: String) -> String {
        english.metricTitle(name)
    }

    public func runStateTitle(_ state: RunState) -> String {
        switch state {
        case .queued: t("Queued", zh: "排队中")
        case .validating: t("Checking inputs", zh: "正在核对")
        case .meshing: t("Preparing the room", zh: "正在准备房间")
        case .solving: t("Estimating", zh: "正在估算")
        case .postprocessing: t("Preparing results", zh: "正在整理结果")
        case .checking: t("Checking", zh: "正在检查")
        case .succeeded: t("Finished", zh: "已完成")
        case .failed: t("Did not finish", zh: "没有完成")
        case .cancelled: t("Cancelled", zh: "已取消")
        }
    }

    public static func runStateTitle(_ state: RunState) -> String {
        english.runStateTitle(state)
    }

    public func qualityTitle(_ quality: QualityState) -> String {
        switch quality {
        case .notEvaluated: t("Not checked yet", zh: "尚未检查")
        case .passed: t("Passed checks", zh: "已通过检查")
        case .failed: t("Did not pass checks", zh: "未通过检查")
        }
    }

    public static func qualityTitle(_ quality: QualityState) -> String {
        english.qualityTitle(quality)
    }

    public func freshnessTitle(_ freshness: ResultFreshness?) -> String {
        switch freshness {
        case .current: t("Matches this room", zh: "按当前房间")
        case .stale: t("The room changed. Estimate again.", zh: "房间改过了，请重新估算")
        case nil: t("No result yet", zh: "还没有结果")
        }
    }

    /// Short value for card cells whose label already says "Quality check",
    /// so a row never reads the long "Passed checks" phrase twice.
    public func qualityShortTitle(_ quality: QualityState) -> String {
        switch quality {
        case .notEvaluated: t("Not checked yet", zh: "尚未检查")
        case .passed: t("Passed", zh: "已通过")
        case .failed: t("Did not pass", zh: "未通过")
        }
    }

    public static func qualityShortTitle(_ quality: QualityState) -> String {
        english.qualityShortTitle(quality)
    }

    public static func freshnessTitle(_ freshness: ResultFreshness?) -> String {
        english.freshnessTitle(freshness)
    }

    public func annotatedStale(_ text: String) -> String {
        t("\(text) (\(freshnessTitle(.stale)))", zh: "\(text)（\(freshnessTitle(.stale))）")
    }

    public func eventTitle(_ type: String) -> String {
        switch type {
        case "accepted": t("Accepted", zh: "已接受")
        case "progress": t("In progress", zh: "进行中")
        case "completed": t("Done", zh: "完成")
        case "failed": t("Did not finish", zh: "没有完成")
        case "quality": t("Check", zh: "检查")
        default: t("Progress", zh: "进度")
        }
    }

    public static func eventTitle(_ type: String) -> String {
        english.eventTitle(type)
    }

    /// Solver monitors stay generic so the unfolded UI never names a binary.
    public func monitorTitle(_ monitor: String?) -> String {
        guard let monitor, !monitor.isEmpty else { return "" }
        let lower = monitor.lowercased()
        if lower.contains("energyplus") { return t("Energy use", zh: "能耗计算") }
        if lower.contains("foam") || lower.contains("mesh") { return t("Airflow field", zh: "气流场计算") }
        if lower.contains("quality") { return t("Result check", zh: "结果检查") }
        return t("Calculation", zh: "计算")
    }

    public static func monitorTitle(_ monitor: String?) -> String {
        english.monitorTitle(monitor)
    }

    public func openingKindTitle(_ kind: OpeningKind) -> String {
        kind == .window ? t("window", zh: "窗") : t("door", zh: "门")
    }

    public func openingTitle(kind: OpeningKind, wall: WallFace, indexOnWall: Int, countOnWall: Int) -> String {
        let place = wallTitle(wall)
        let noun = openingKindTitle(kind)
        if countOnWall > 1 {
            return t("\(place) \(noun) \(indexOnWall + 1)", zh: "\(place)的\(noun) \(indexOnWall + 1)")
        }
        return t("\(place) \(noun)", zh: "\(place)的\(noun)")
    }

    public static func openingTitle(kind: OpeningKind, wall: WallFace, indexOnWall: Int, countOnWall: Int) -> String {
        english.openingTitle(kind: kind, wall: wall, indexOnWall: indexOnWall, countOnWall: countOnWall)
    }

    public func openingTitle(for opening: Opening, in openings: [Opening]) -> String {
        let matches = openings.filter { $0.kind == opening.kind && $0.wall == opening.wall }
        let index = matches.firstIndex(where: { $0.id == opening.id }) ?? 0
        return openingTitle(kind: opening.kind, wall: opening.wall, indexOnWall: index, countOnWall: matches.count)
    }

    public static func openingTitle(for opening: Opening, in openings: [Opening]) -> String {
        english.openingTitle(for: opening, in: openings)
    }

    public func seatTitle(index: Int, near: SeatPlace) -> String {
        let number = index + 1
        switch near {
        case .nearWindow: return t("Window seat \(number)", zh: "靠窗座位 \(number)")
        case .nearDoor: return t("Door seat \(number)", zh: "靠门座位 \(number)")
        case .other: return t("Seat \(number)", zh: "座位 \(number)")
        }
    }

    public static func seatTitle(index: Int, near: SeatPlace) -> String {
        english.seatTitle(index: index, near: near)
    }

    public func seatTitle(seat: Seat, seats: [Seat], geometry: RoomGeometry?) -> String {
        let index = seats.firstIndex(where: { $0.id == seat.id }) ?? 0
        let place = geometry.map { SeatPlace.classify(seat: seat, geometry: $0) } ?? .other
        return seatTitle(index: index, near: place)
    }

    public static func seatTitle(seat: Seat, seats: [Seat], geometry: RoomGeometry?) -> String {
        english.seatTitle(seat: seat, seats: seats, geometry: geometry)
    }

    public func furnitureTitle(index: Int) -> String {
        t("Furniture \(index + 1)", zh: "家具 \(index + 1)")
    }

    public static func furnitureTitle(index: Int) -> String {
        english.furnitureTitle(index: index)
    }

    public func terminalTitle(isSupply: Bool) -> String {
        isSupply ? t("Supply outlet", zh: "出风口") : t("Return inlet", zh: "回风口")
    }

    public static func terminalTitle(isSupply: Bool) -> String {
        english.terminalTitle(isSupply: isSupply)
    }

    public func omittedAssumptionTitle(_ note: String) -> String {
        let key = note.replacingOccurrences(of: "omitted:", with: "").trimmingCharacters(in: .whitespaces)
        switch key {
        case "envelope_u_value":
            return t("Wall insulation is not filled in and will not be treated as 0", zh: "墙的保温尚未填写，不会按 0 计算")
        case "weather_file":
            return t("Weather file is not filled in and will not be treated as 0", zh: "天气文件尚未填写，不会按 0 计算")
        case "furniture_boxes":
            return t("Furniture is not drawn in detail and will not be treated as 0", zh: "家具尚未细画，不会按 0 计算")
        default:
            return t("One item is not filled in and will not be treated as 0", zh: "有一项尚未填写，不会按 0 计算")
        }
    }

    public static func omittedAssumptionTitle(_ note: String) -> String {
        english.omittedAssumptionTitle(note)
    }

    public func gateTitle(_ stored: String) -> String {
        stored
            .replacingOccurrences(of: "温度门", with: t("too warm or too cool", zh: "偏热或偏冷"))
            .replacingOccurrences(of: "风速门", with: t("air too fast", zh: "风偏大"))
            .replacingOccurrences(of: "PMV门", with: t("sensation out of range", zh: "冷热不合适"))
    }

    public static func gateTitle(_ stored: String) -> String {
        english.gateTitle(stored)
    }

    /// User-visible numbers stay at two fraction digits. Stored physics values are unchanged.
    public static func displayNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    public static func displayQuantity(_ value: Double, unit: String) -> String {
        // Display-layer unit spelling only; contract `unit` fields stay as-is.
        // "C" reads as a bare letter next to numbers, so the card shows "°C".
        let displayUnit = unit == "C" ? "°C" : unit
        return "\(displayNumber(value)) \(displayUnit)"
    }

    public static func displayRange(_ min: Double, _ max: Double, unit: String) -> String {
        "\(displayNumber(min)) – \(displayNumber(max)) \(unit)"
    }

    public func destinationTitle(_ destination: String) -> String {
        switch destination {
        case "workspace": t("Lay out the room", zh: "布置房间")
        case "scenarios": t("Compare schemes", zh: "方案对比")
        case "runs": t("Calculation results", zh: "计算结果")
        case "reports": t("Export report", zh: "导出报告")
        default: destination
        }
    }
}
