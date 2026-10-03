import Foundation

/// Field-level editor error. `path` is a dotted model path, never a local filesystem path.
public struct FieldIssue: Equatable, Identifiable, Sendable {
    public var path: String
    public var message: String

    public var id: String { path }

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// One assumed/preset quantity or geometry note, for the hypothesis list.
public struct ListedAssumption: Equatable, Identifiable, Sendable {
    public var path: String
    public var source: ParameterSource?
    public var reference: String?
    public var uncertainty: Double?
    public var unit: String?
    public var note: String?

    public var id: String { path }

    /// Missing literature is unknown, not zero. Uncertainty is labeled in the quantity's unit.
    public var provenanceText: String {
        var text = note ?? reference ?? "未知 / 无出处"
        if let uncertainty, let unit {
            text += " · 不确定度 \(UserFacingCopy.displayQuantity(uncertainty, unit: unit))"
        }
        return text
    }
}

extension ProjectDraft {
    /// Reject non-positive sizes without inventing a default room.
    @discardableResult
    public mutating func applyRoomSize(
        x: Double,
        y: Double,
        z: Double,
        source: ParameterSource
    ) -> [FieldIssue] {
        var issues: [FieldIssue] = []
        if x <= 0 {
            issues.append(FieldIssue(path: "geometry.sizeX", message: "长度必须为正，单位 m"))
        }
        if y <= 0 {
            issues.append(FieldIssue(path: "geometry.sizeY", message: "宽度必须为正，单位 m"))
        }
        if z <= 0 {
            issues.append(FieldIssue(path: "geometry.sizeZ", message: "高度必须为正，单位 m"))
        }
        guard issues.isEmpty else { return issues }

        let metres = { (value: Double) in PhysicalQuantity(value: value, unit: "m", source: source) }
        if var geometry {
            geometry.sizeX = metres(x)
            geometry.sizeY = metres(y)
            geometry.sizeZ = metres(z)
            self.geometry = geometry
            return allFieldIssues()
        }
        self.geometry = RoomGeometry(sizeX: metres(x), sizeY: metres(y), sizeZ: metres(z))
        return []
    }

    /// Stores the opening as typed. Out-of-wall values are reported, not clamped.
    @discardableResult
    public mutating func upsertOpening(_ opening: Opening) -> [FieldIssue] {
        guard var geometry else {
            return [FieldIssue(path: "geometry", message: "请先填写房间尺寸")]
        }
        if let index = geometry.openings.firstIndex(where: { $0.id == opening.id }) {
            geometry.openings[index] = opening
        } else {
            geometry.openings.append(opening)
        }
        self.geometry = geometry
        return allFieldIssues()
    }

    /// Numeric editor entry: wall-local s/z and ParameterSource are written together.
    @discardableResult
    public mutating func applyOpening(
        id: String,
        kind: OpeningKind,
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) -> [FieldIssue] {
        upsertOpening(
            Opening(
                id: id,
                kind: kind,
                wall: wall,
                s0: Self.metres(s0, source: source),
                s1: Self.metres(s1, source: source),
                z0: Self.metres(z0, source: source),
                z1: Self.metres(z1, source: source)
            )
        )
    }

    public mutating func removeOpening(id: String) {
        geometry?.openings.removeAll { $0.id == id }
    }

    /// Writes yaw only. Existing wall-local s0/s1 stay put.
    @discardableResult
    public mutating func applyNorthYawDegrees(_ value: Double, source: ParameterSource) -> [FieldIssue] {
        guard var geometry else {
            return [FieldIssue(path: "geometry", message: "请先填写房间尺寸")]
        }
        geometry.northYawDegrees = PhysicalQuantity(value: value, unit: "deg", source: source)
        self.geometry = geometry
        return []
    }

    public func openingIssues() -> [FieldIssue] {
        guard let geometry else { return [] }
        return geometry.openings.compactMap { opening in
            guard !geometry.contains(opening) else { return nil }
            return FieldIssue(
                path: "geometry.openings.\(opening.id)",
                message: "开口超出所属墙面或高度范围"
            )
        }
    }

    public func listedAssumptions() -> [ListedAssumption] {
        var items: [ListedAssumption] = []
        if let geometry {
            for (index, note) in geometry.assumptions.enumerated() {
                items.append(ListedAssumption(path: "geometry.assumptions[\(index)]", note: note))
            }
            items.append(contentsOf: Self.records(for: geometry.sizeX, path: "geometry.sizeX"))
            items.append(contentsOf: Self.records(for: geometry.sizeY, path: "geometry.sizeY"))
            items.append(contentsOf: Self.records(for: geometry.sizeZ, path: "geometry.sizeZ"))
            items.append(contentsOf: Self.records(for: geometry.northYawDegrees, path: "geometry.northYawDegrees"))
            for opening in geometry.openings {
                let root = "geometry.openings.\(opening.id)"
                items.append(contentsOf: Self.records(for: opening.s0, path: "\(root).s0"))
                items.append(contentsOf: Self.records(for: opening.s1, path: "\(root).s1"))
                items.append(contentsOf: Self.records(for: opening.z0, path: "\(root).z0"))
                items.append(contentsOf: Self.records(for: opening.z1, path: "\(root).z1"))
                if let flux = opening.heatFluxWm2 {
                    items.append(contentsOf: Self.records(for: flux, path: "\(root).heatFluxWm2"))
                }
            }
        }
        if let occupancy {
            items.append(contentsOf: Self.records(for: occupancy.occupantCount, path: "occupancy.occupantCount"))
            items.append(contentsOf: Self.records(for: occupancy.occupantSensibleW, path: "occupancy.occupantSensibleW"))
            items.append(contentsOf: Self.records(for: occupancy.lightingW, path: "occupancy.lightingW"))
            items.append(contentsOf: Self.records(for: occupancy.equipmentW, path: "occupancy.equipmentW"))
            if let comfort = occupancy.comfort {
                items.append(contentsOf: Self.records(for: comfort.mrtC, path: "occupancy.comfort.mrtC"))
                items.append(contentsOf: Self.records(for: comfort.rhPct, path: "occupancy.comfort.rhPct"))
                items.append(contentsOf: Self.records(for: comfort.clo, path: "occupancy.comfort.clo"))
                items.append(contentsOf: Self.records(for: comfort.met, path: "occupancy.comfort.met"))
            }
        }
        if let hvac {
            items.append(contentsOf: Self.records(for: hvac.setpointC, path: "hvac.setpointC"))
            items.append(contentsOf: Self.records(for: hvac.supplyTemperatureC, path: "hvac.supplyTemperatureC"))
            items.append(contentsOf: Self.records(for: hvac.supplySpeedMs, path: "hvac.supplySpeedMs"))
            items.append(contentsOf: Self.records(for: hvac.supplyAirflowM3s, path: "hvac.supplyAirflowM3s"))
            items.append(contentsOf: Self.records(for: hvac.outdoorAirM3s, path: "hvac.outdoorAirM3s"))
            items.append(contentsOf: Self.records(for: hvac.cop, path: "hvac.cop"))
        }
        return items
    }

    @discardableResult
    public mutating func upsertObstacle(_ box: ObstacleBox) -> [FieldIssue] {
        guard var geometry else {
            return [FieldIssue(path: "geometry", message: "请先填写房间尺寸")]
        }
        if let index = geometry.obstacles.firstIndex(where: { $0.id == box.id }) {
            geometry.obstacles[index] = box
        } else {
            geometry.obstacles.append(box)
        }
        geometry.assumptions.removeAll { $0 == "omitted: furniture_boxes" }
        self.geometry = geometry
        return allFieldIssues()
    }

    @discardableResult
    public mutating func applyObstacle(id: String, origin: Position3D, size: Position3D) -> [FieldIssue] {
        upsertObstacle(ObstacleBox(id: id, origin: origin, size: size))
    }

    public mutating func removeObstacle(id: String) {
        geometry?.obstacles.removeAll { $0.id == id }
    }

    @discardableResult
    public mutating func upsertSeat(_ seat: Seat) -> [FieldIssue] {
        var occupancy = occupancy ?? OccupancyModel(
            occupantCount: PhysicalQuantity(value: 0, unit: "1", source: .user),
            occupantSensibleW: PhysicalQuantity(value: 0, unit: "W", source: .user),
            lightingW: PhysicalQuantity(value: 0, unit: "W", source: .user),
            equipmentW: PhysicalQuantity(value: 0, unit: "W", source: .user),
            seats: []
        )
        let isNew = !occupancy.seats.contains { $0.id == seat.id }
        occupancy.seats.removeAll { $0.id == seat.id }
        occupancy.seats.append(seat)
        // A new seat is a new person. Moving an existing seat keeps the count.
        if isNew {
            occupancy.occupantCount = PhysicalQuantity(
                value: Double(occupancy.seats.count),
                unit: "1",
                source: seat.source
            )
        }
        self.occupancy = occupancy
        return allFieldIssues()
    }

    @discardableResult
    public mutating func applySeat(id: String, position: Position3D, source: ParameterSource) -> [FieldIssue] {
        upsertSeat(Seat(id: id, position: position, source: source))
    }

    /// Headcount and seat count stay equal. Extra seats are placed in the room; extras are dropped from the end.
    @discardableResult
    public mutating func applyOccupantCount(_ value: Double, source: ParameterSource) -> [FieldIssue] {
        guard value >= 1, value == value.rounded() else {
            return [FieldIssue(path: "occupancy.occupantCount", message: "人数必须为正整数")]
        }
        guard var occupancy else {
            return [FieldIssue(path: "occupancy", message: "请先从模板创建人员分区")]
        }
        let target = Int(value)
        var seats = occupancy.seats
        if seats.count > target {
            seats = Array(seats.prefix(target))
        }
        while seats.count < target {
            let id = ProjectDraft.nextPrefixedID(prefix: "S", existing: seats.map(\.id))
            seats.append(Seat(id: id, position: Self.nextSeatPosition(in: geometry, existing: seats), source: source))
        }
        occupancy.seats = seats
        occupancy.occupantCount = PhysicalQuantity(value: Double(target), unit: "1", source: source)
        self.occupancy = occupancy
        return allFieldIssues()
    }

    /// One representative-day window for people and HVAC. Not an 8760 file.
    @discardableResult
    public mutating func applyOccupiedHours(start: String, end: String, source: ParameterSource) -> [FieldIssue] {
        guard OccupiedHours.isValidClock(start), OccupiedHours.isValidClock(end) else {
            return [FieldIssue(path: "occupancy.schedule", message: "占用时段须为 HH:MM")]
        }
        guard let startMinutes = OccupiedHours.minutes(from: start),
              let endMinutes = OccupiedHours.minutes(from: end),
              endMinutes > startMinutes else {
            return [FieldIssue(path: "occupancy.schedule", message: "结束须晚于开始")]
        }
        guard var occupancy else {
            return [FieldIssue(path: "occupancy", message: "请先从模板创建人员分区")]
        }
        let reference = occupancy.schedule?.reference ?? "representative-day occupied hours, not annual"
        occupancy.schedule = OccupiedHours(start: start, end: end, source: source, reference: reference)
        self.occupancy = occupancy
        if var hvac {
            let hvacReference = hvac.schedule?.reference ?? "representative-day system-on hours, not annual"
            hvac.schedule = OccupiedHours(start: start, end: end, source: source, reference: hvacReference)
            self.hvac = hvac
        }
        return allFieldIssues()
    }

    @discardableResult
    public mutating func removeSeat(id: String) -> [FieldIssue] {
        guard var occupancy else { return allFieldIssues() }
        guard occupancy.seats.contains(where: { $0.id == id }) else { return allFieldIssues() }
        if occupancy.seats.count <= 1 {
            return [FieldIssue(path: "occupancy.seats.\(id)", message: "至少保留一个座位")] + allFieldIssues()
        }
        occupancy.seats.removeAll { $0.id == id }
        occupancy.occupantCount = PhysicalQuantity(
            value: Double(occupancy.seats.count),
            unit: "1",
            source: .user
        )
        self.occupancy = occupancy
        return allFieldIssues()
    }

    @discardableResult
    public mutating func installDefaultSplitAC() -> [FieldIssue] {
        guard geometry != nil else {
            return [FieldIssue(path: "geometry", message: "请先填写房间尺寸")]
        }
        let metres = { (value: Double) in PhysicalQuantity(value: value, unit: "m", source: ParameterSource.user) }
        let supply = AirTerminal(id: "SUP1", wall: .xMin, s0: metres(2.75), s1: metres(3.25), z0: metres(2.48), z1: metres(2.66))
        let returnTerminal = AirTerminal(id: "RET1", wall: .xMin, s0: metres(2.70), s1: metres(3.30), z0: metres(1.85), z1: metres(2.05))
        hvac = HVACModel(
            setpointC: PhysicalQuantity(value: 26, unit: "C", source: .user),
            supplyTemperatureC: PhysicalQuantity(value: 16, unit: "C", source: .user),
            supplySpeedMs: PhysicalQuantity(value: 1.2, unit: "m/s", source: .user),
            supplyAirflowM3s: PhysicalQuantity(value: 1.2 * supply.patchAreaM2, unit: "m3/s", source: .user),
            supply: supply,
            returnTerminal: returnTerminal,
            outdoorAirM3s: PhysicalQuantity(value: 0.02, unit: "m3/s", source: .assumed),
            cop: PhysicalQuantity(value: 3, unit: "1", source: .assumed)
        )
        return allFieldIssues()
    }

    /// Drops the split AC. Seats and openings stay; the inspector can install again.
    public mutating func removeHVAC() {
        hvac = nil
    }

    @discardableResult
    public mutating func applyHVAC(_ model: HVACModel) -> [FieldIssue] {
        hvac = model
        return allFieldIssues()
    }

    /// Edits the supply patch in place so the terminal id stays stable.
    @discardableResult
    public mutating func applySupplyTerminal(
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) -> [FieldIssue] {
        mutateHVAC { hvac in
            hvac.supply.wall = wall
            hvac.supply.s0 = Self.metres(s0, source: source)
            hvac.supply.s1 = Self.metres(s1, source: source)
            hvac.supply.z0 = Self.metres(z0, source: source)
            hvac.supply.z1 = Self.metres(z1, source: source)
            // Area edits must refresh flow; speed stays the independent input.
            hvac.recomputeSupplyAirflow(source: source)
        }
    }

    @discardableResult
    public mutating func applyReturnTerminal(
        wall: WallFace,
        s0: Double,
        s1: Double,
        z0: Double,
        z1: Double,
        source: ParameterSource
    ) -> [FieldIssue] {
        mutateHVAC { hvac in
            hvac.returnTerminal.wall = wall
            hvac.returnTerminal.s0 = Self.metres(s0, source: source)
            hvac.returnTerminal.s1 = Self.metres(s1, source: source)
            hvac.returnTerminal.z0 = Self.metres(z0, source: source)
            hvac.returnTerminal.z1 = Self.metres(z1, source: source)
        }
    }

    @discardableResult
    public mutating func applyOutdoorAirM3s(_ value: Double, source: ParameterSource) -> [FieldIssue] {
        mutateHVAC { hvac in
            hvac.outdoorAirM3s = PhysicalQuantity(value: value, unit: "m3/s", source: source)
        }
    }

    @discardableResult
    public mutating func applySupplySpeedMs(_ value: Double, source: ParameterSource) -> [FieldIssue] {
        mutateHVAC { hvac in
            hvac.supplySpeedMs = PhysicalQuantity(value: value, unit: "m/s", source: source)
            hvac.recomputeSupplyAirflow(source: source)
        }
    }

    /// Writes declared volume flow as typed so a mismatch can surface as a blocking issue.
    @discardableResult
    public mutating func applySupplyAirflowM3s(_ value: Double, source: ParameterSource) -> [FieldIssue] {
        mutateHVAC { hvac in
            hvac.supplyAirflowM3s = PhysicalQuantity(value: value, unit: "m3/s", source: source)
        }
    }

    @discardableResult
    public mutating func recomputeSupplyAirflowFromSpeedAndArea() -> [FieldIssue] {
        mutateHVAC { hvac in
            hvac.recomputeSupplyAirflow(source: hvac.supplyAirflowM3s.source)
        }
    }

    public func allFieldIssues() -> [FieldIssue] {
        openingIssues() + obstacleIssues() + seatIssues() + hvacIssues()
    }

    public func obstacleIssues() -> [FieldIssue] {
        guard let geometry else { return [] }
        return geometry.obstacles.compactMap { box in
            guard !geometry.contains(box) else { return nil }
            return FieldIssue(path: "geometry.obstacles.\(box.id)", message: "家具盒体穿墙或超出房间")
        }
    }

    public func seatIssues() -> [FieldIssue] {
        var issues: [FieldIssue] = []
        if let occupancy {
            let people = occupancy.occupantCount.value
            let seats = occupancy.seats.count
            if people != Double(seats) {
                issues.append(FieldIssue(path: "occupancy.occupantCount", message: "人数必须与座位数相同"))
            }
        }
        guard let geometry else {
            issues.append(contentsOf: occupancy?.seats.map { FieldIssue(path: "occupancy.seats.\($0.id)", message: "请先填写房间尺寸") } ?? [])
            return issues
        }
        issues.append(contentsOf: (occupancy?.seats ?? []).compactMap { seat in
            guard geometry.containsSeat(seat) else {
                return FieldIssue(path: "occupancy.seats.\(seat.id)", message: "座位采样点必须在流体域内")
            }
            return nil
        })
        return issues
    }

    /// Place a new seat inside the room, away from existing sample points.
    private static func nextSeatPosition(in geometry: RoomGeometry?, existing: [Seat]) -> Position3D {
        let sizeX = geometry?.sizeX.value ?? 6
        let sizeY = geometry?.sizeY.value ?? 6
        let margin = 1.0
        let step = 1.2
        var x = margin
        var y = margin
        func occupied(_ x: Double, _ y: Double) -> Bool {
            existing.contains { hypot($0.position.x - x, $0.position.y - y) < 0.35 }
        }
        var attempts = 0
        while occupied(x, y) && attempts < 200 {
            x += step
            if x > sizeX - margin {
                x = margin
                y += step
            }
            if y > sizeY - margin {
                x = margin + Double(existing.count % 7) * 0.55
                y = margin + Double((existing.count / 7) % 7) * 0.55
                break
            }
            attempts += 1
        }
        return Position3D(
            x: min(max(x, 0.3), max(sizeX - 0.3, 0.3)),
            y: min(max(y, 0.3), max(sizeY - 0.3, 0.3)),
            z: 1.1
        )
    }

    public func hvacIssues() -> [FieldIssue] {
        guard let hvac else { return [] }
        var issues: [FieldIssue] = []
        if let geometry {
            if !geometry.contains(hvac.supply) {
                issues.append(FieldIssue(path: "hvac.supply", message: "送风口超出所属墙面"))
            }
            if !geometry.contains(hvac.returnTerminal) {
                issues.append(FieldIssue(path: "hvac.returnTerminal", message: "回风口超出所属墙面"))
            }
        }
        if terminalsOccupySamePatch(hvac.supply, hvac.returnTerminal) {
            issues.append(FieldIssue(path: "hvac.returnTerminal", message: "送回风不能合成一个 patch"))
        }
        if !hvac.supplyAirflowMatchesSpeed() {
            issues.append(FieldIssue(path: "hvac.supplyAirflowM3s", message: "送风量与速度×面积不一致（相对误差须 ≤ 5%）"))
        }
        return issues
    }

    private mutating func mutateHVAC(_ body: (inout HVACModel) -> Void) -> [FieldIssue] {
        guard var hvac else {
            return [FieldIssue(path: "hvac", message: "请先安装空调设备")]
        }
        body(&hvac)
        return applyHVAC(hvac)
    }

    private static func metres(_ value: Double, source: ParameterSource) -> PhysicalQuantity {
        PhysicalQuantity(value: value, unit: "m", source: source)
    }

    private func terminalsOccupySamePatch(_ supply: AirTerminal, _ returnTerminal: AirTerminal) -> Bool {
        supply.wall == returnTerminal.wall
            && supply.s0.value == returnTerminal.s0.value
            && supply.s1.value == returnTerminal.s1.value
            && supply.z0.value == returnTerminal.z0.value
            && supply.z1.value == returnTerminal.z1.value
    }

    private static func records(for quantity: PhysicalQuantity, path: String) -> [ListedAssumption] {
        guard quantity.source == .assumed || quantity.source == .preset else { return [] }
        return [
            ListedAssumption(
                path: path,
                source: quantity.source,
                reference: quantity.reference,
                uncertainty: quantity.uncertainty,
                unit: quantity.unit
            )
        ]
    }
}
