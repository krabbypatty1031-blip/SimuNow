import Foundation

public struct AnalysisReadinessEvaluator: Sendable {
    public let registry: ModelRegistry
    public init(registry: ModelRegistry = .builtIn) { self.registry = registry }
    public func evaluate(
        project: ProjectDocument, scenarioID: UUID?, capability: AnalysisCapability,
        configuration: AnalysisConfiguration? = nil, additionalIssues: [ValidationIssue] = []
    ) -> AnalysisReadiness {
        var blockers: [AnalysisIssue] = []
        var warnings: [AnalysisIssue] = []
        var unsupported: [UUID] = []
        var integrity: [ValidationIssue] = []
        func issue(
            _ code: String, _ path: String, _ message: String, entity: UUID? = nil, warning: Bool = false
        ) {
            let v = AnalysisIssue(
                code: code, severity: warning ? .warning : .blocker, scope: capability,
                entityID: entity, fieldPath: path, message: message, repairAction: warning ? nil : "查看并修复该字段")
            if warning { warnings.append(v) } else { blockers.append(v) }
        }
        do {
            // ProjectValidator already performs the complete structural boundary.
            integrity = try ProjectValidator().validate(project, registry: registry).issues + additionalIssues
            for v in integrity where v.blocks.contains(.projectIntegrity) {
                issue(v.code, v.path, v.message, entity: v.entityID, warning: capability == .roomView)
            }
        } catch {
            issue("project_contract", "", "项目结构不支持：\(error)")
            return .init(capability: capability, blockers: blockers)
        }
        var validRooms = 0
        if capability == .roomView || capability == .airflowPreview {
            for (i, room) in project.geometry.rooms.enumerated() {
                guard
                    let geometry = try? registry.resolve(category: "room", record: room.shape)
                        as? any GeometryPayload,
                    let bounds = geometry.geometryBounds(),
                    [bounds.size.x, bounds.size.y, bounds.size.z].allSatisfy({ $0.isFinite && $0 > 0 })
                else {
                    issue(
                        "room_geometry_unavailable", "/geometry/rooms/\(i)/shape", "房间几何未知，不能推测尺寸。",
                        entity: room.id, warning: capability == .roomView)
                    unsupported.append(room.id)
                    continue
                }
                validRooms += 1
            }
            if capability == .roomView && validRooms == 0 {
                issue("view_geometry_required", "/geometry/rooms", "暂无可显示的有效房间几何；请在二维编辑器补充。")
            }
            if project.geometry.rooms.isEmpty { issue("room_required", "/geometry/rooms", "先创建一个有明确尺寸的房间。") }
        }
        if capability == .roomView {
            for (i, obstacle) in project.geometry.obstacles.enumerated() {
                if (try? registry.resolve(category: "obstacle", record: obstacle.shape)?.geometryBounds())
                    == nil
                {
                    issue(
                        "obstacle_not_displayed", "/geometry/obstacles/\(i)/shape", "此物体几何未知，可在对象列表修复。",
                        entity: obstacle.id, warning: true)
                    unsupported.append(obstacle.id)
                }
            }
            return .init(
                capability: capability, blockers: blockers, warnings: warnings,
                unsupportedEntities: unsupported)
        }
        guard let scenarioID, let si = project.scenarios.firstIndex(where: { $0.id == scenarioID }) else {
            issue("scenario_required", "/scenarios", "选择一个仍然存在的方案。")
            return .init(capability: capability, blockers: blockers, warnings: warnings)
        }
        let scenario = project.scenarios[si]
        let base = "/scenarios/\(si)/inputs"
        guard let configuration else {
            issue("configuration_required", "/analysis/configuration", "先明确选择本方法的配置与假设。")
            return .init(capability: capability, blockers: blockers, warnings: warnings)
        }
        let expected = AnalysisKind(rawValue: capability.rawValue)
        if expected != configuration.payload.kind {
            issue("configuration_method", "/analysis/configuration", "配置属于其他分析方法。")
        }
        do { try NativeAnalysisCodec(registry: registry).validateConfiguration(configuration) } catch {
            issue("configuration_invalid", "/analysis/configuration", "配置无效：\(error)")
        }
        if let id = configuration.roomID, !project.geometry.rooms.contains(where: { $0.id == id }) {
            issue("room_reference", "/analysis/configuration/roomID", "配置的房间已不存在。", entity: id)
        }
        if let id = configuration.deviceID, !scenario.inputs.hvac.contains(where: { $0.id == id }) {
            issue("device_reference", "/analysis/configuration/deviceID", "配置的设备已不存在。", entity: id)
        }
        switch configuration.payload {
        case .airflowPreview(let config):
            if config.profileID != "simunow.preview.genericCone" || config.profileVersion != 1 {
                issue("preview_profile_unsupported", "/analysis/configuration/profile", "此规则档案或版本尚未支持。")
            }
            if config.source.kind != .assumed
                || config.source.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            {
                issue("preview_profile_basis", "/analysis/configuration/source", "扩散档案必须明确标为有说明的展示假设。")
            }
            if scenario.inputs.ventilation.contains(where: {
                $0.openings.contains(where: { ($0.openFraction.value ?? 0) > 0 })
            }) {
                issue(
                    "preview_openings_not_simulated", base + "/ventilation/openings",
                    "存在开启门窗：本次预览域仍封闭，跨开口气流未模拟。", warning: true)
            }
            if scenario.inputs.hvac.contains(where: { $0.ports.contains(where: { $0.role == .return }) }) {
                issue("preview_return_not_simulated", base + "/hvac", "回风口仅显示位置，回风循环和吸引未模拟。", warning: true)
            }
            if let room = project.geometry.rooms.first,
                let shape = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
                let bounds = shape.geometryBounds(), let length = config.lengthMeters
            {
                let diagonal = sqrt(
                    bounds.size.x * bounds.size.x + bounds.size.y * bounds.size.y + bounds.size.z
                        * bounds.size.z)
                if length > diagonal {
                    issue("preview_length_range", "/analysis/configuration/lengthMeters", "展示范围不能大于房间对角线。")
                }
            }
            if project.geometry.rooms.count != 1 {
                issue("preview_room_count", "/geometry/rooms", "首版规则预览仅支持一个矩形房间。")
            }
            if let room = project.geometry.rooms.first,
                (try? room.shape.resolved(as: RectangularRoom.self, registry: registry)) == nil
            {
                issue("preview_room_unsupported", "/geometry/rooms/0/shape", "规则预览需要矩形房间。", entity: room.id)
            }
            if scenario.inputs.hvac.count != 1 {
                issue("preview_device_count", base + "/hvac", "规则预览需要且仅支持一台空调。")
            }
            if let device = scenario.inputs.hvac.first {
                if (try? device.definition.resolved(as: SingleSplit.self, registry: registry)) == nil {
                    issue(
                        "preview_device_unsupported", base + "/hvac/0/definition", "暂不支持此设备的气流规则。",
                        entity: device.id)
                }
                let supplies = device.ports.enumerated().filter { $0.element.role == .supply }
                if supplies.count != 1 {
                    issue("preview_supply_required", base + "/hvac/0/ports", "明确一个送风口与方向。", entity: device.id)
                }
                if let supply = supplies.first {
                    let p = supply.element
                    let direction = p.direction
                    let norm = sqrt(
                        direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
                    if !norm.isFinite || abs(norm - 1) > 1e-6 {
                        issue(
                            "direction_unit", base + "/hvac/0/ports/\(supply.offset)/direction",
                            "方向必须为有限单位向量。", entity: p.id)
                    }
                    if let room = project.geometry.rooms.first,
                        let model = try? room.shape.resolved(as: RectangularRoom.self, registry: registry),
                        let bounds = model.geometryBounds()
                    {
                        if !bounds.contains(p.position) {
                            issue(
                                "supply_outside", base + "/hvac/0/ports/\(supply.offset)/position",
                                "送风口必须在房间域内。", entity: p.id)
                        }
                        let xyz = [p.position.x, p.position.y, p.position.z]
                        let d = [direction.x, direction.y, direction.z]
                        let size = [bounds.size.x, bounds.size.y, bounds.size.z]
                        for axis in 0..<3
                        where (abs(xyz[axis]) <= 1e-6 && d[axis] <= 0)
                            || (abs(xyz[axis] - size[axis]) <= 1e-6 && d[axis] >= 0)
                        {
                            issue(
                                "supply_not_inward", base + "/hvac/0/ports/\(supply.offset)/direction",
                                "墙面风口方向必须进入房间。", entity: p.id)
                        }
                    }
                }
            }
            for (i, obstacle) in project.geometry.obstacles.enumerated() {
                guard let box = try? obstacle.shape.resolved(as: BoxObstacle.self, registry: registry),
                    let bounds = box.geometryBounds()
                else {
                    issue(
                        "preview_obstacle_unsupported", "/geometry/obstacles/\(i)/shape",
                        "此物体可能遮挡路径，但几何无法用于预览。", entity: obstacle.id)
                    unsupported.append(obstacle.id)
                    continue
                }
                if let supply = scenario.inputs.hvac.first?.ports.first(where: { $0.role == .supply }),
                    bounds.contains(supply.position, tolerance: 0)
                {
                    issue(
                        "supply_inside_obstacle", base + "/hvac/0/ports", "送风口位于家具内部或边界，请修正位置。",
                        entity: obstacle.id)
                }
            }
            if project.geometry.obstacles.count > configuration.resources.maximumObstacles {
                issue("preview_obstacle_limit", "/geometry/obstacles", "家具数量超出当前资源上限。")
            }
            let targetCount = scenario.inputs.usage.seats.reduce(0) { $0 + max(1, $1.samples.count) }
            if targetCount > configuration.resources.maximumTargets {
                issue("preview_target_limit", base + "/usage/seats", "关注点数量超出当前资源上限。")
            }
            if !configuration.acceptedAssumptions.contains(where: {
                $0.id == config.profileID && $0.version == config.profileVersion
            }) {
                issue(
                    "preview_assumption_unaccepted", "/analysis/configuration/acceptedAssumptions",
                    "明确接受通用几何预览档案；它不表示现实风速。")
            }
            // Reuse the validated complete-project report; select the current
            // scenario's input issues without encoding and validating it again.
            for v in integrity
            where !v.blocks.contains(.projectIntegrity)
                && v.blocks.contains(.inputPreparation)
                && (!v.path.hasPrefix("/scenarios/") || v.path.hasPrefix("/scenarios/\(si)/"))
            {
                issue(
                    "not_used." + v.code, v.path,
                    "本次仅预览方向与遮挡，不采用此物理项：\(v.message)", entity: v.entityID, warning: true)
            }
        case .powerEstimate(let config):
            if config.requestedWindows.isEmpty {
                issue("power_window_required", "/analysis/configuration/requestedWindows", "明确要估算的时段。")
            }
            if config.intervals.isEmpty {
                issue("power_basis_required", "/analysis/configuration/intervals", "明确用电功率与功率口径；制冷量不能代替电功率。")
            }
            for (i, p) in config.intervals.enumerated() where p.power.value == nil {
                issue(
                    "power_missing", "/analysis/configuration/intervals/\(i)/power", "功率未知，结果只能给出已知部分的小计。",
                    warning: true)
            }
        case .steadyHeatBalance(let config):
            let values: [(String, Double?)] = [
                ("conductance", config.conductance.value),
                ("indoorTemperature", config.indoorTemperature.value),
                ("outdoorTemperature", config.outdoorTemperature.value),
                ("outdoorAir", config.outdoorAir.value), ("infiltration", config.infiltration.value),
                ("density", config.density.value), ("specificHeat", config.specificHeat.value),
                ("internalSensibleHeat", config.internalSensibleHeat.value),
                ("solarSensibleHeat", config.solarSensibleHeat.value),
            ]
            for (field, value) in values where value == nil {
                issue("heat_input_missing", "/analysis/configuration/\(field)", "显热情景缺少 \(field)，不能将未知补为零。")
            }
            if let density = config.density.value, density <= 0 {
                issue("heat_density", "/analysis/configuration/density", "密度必须大于零。")
            }
            if let heat = config.specificHeat.value, heat <= 0 {
                issue("heat_specific_heat", "/analysis/configuration/specificHeat", "比热必须大于零。")
            }
        }
        return .init(
            capability: capability, blockers: blockers, warnings: warnings, unsupportedEntities: unsupported)
    }
}
