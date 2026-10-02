import Foundation

public struct PhysicsRule: ProjectValidationRule {
    public init() {}
    public func validate(_ project: ProjectDocument, registry: ModelRegistry) throws -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func issue(_ code: String,_ path: String, integrity: Bool = false) {
            issues.append(.init(code:code,path:path,blocks:integrity ? [.projectIntegrity,.inputPreparation] : [.inputPreparation],message:"Correct or complete the input before preparation."))
        }
        let tolerance = GeometryRule.tolerance
        if project.geometry.rooms.count != 1 { issue("room_count","/geometry/rooms") }
        if project.scenarios.isEmpty { issue("scenario_required","/scenarios") }
        for (i,s) in project.scenarios.enumerated() {
            let base = "/scenarios/\(i)/inputs", input = s.inputs
            if input.hvac.count != 1 { issue("device_count",base + "/hvac") }
            for (j,d) in input.hvac.enumerated() {
                let path = base + "/hvac/\(j)"
                if Set(d.ports.map(\.role)) != Set([PortRole.supply,.return]) { issue("port_topology",path + "/ports") }
                if d.ports.contains(where: { $0.volumeFlow.value == nil || $0.density.value == nil }) { issue("mass_balance_uncheckable",path + "/ports") }
                else {
                    let supply = d.ports.filter { $0.role == .supply }.reduce(0.0) { $0 + $1.volumeFlow.value! * $1.density.value! }
                    let ret = d.ports.filter { $0.role == .return }.reduce(0.0) { $0 + $1.volumeFlow.value! * $1.density.value! }
                    if abs(supply-ret) > tolerance * max(supply,ret,1e-12) { issue("recirculation_balance",path + "/ports") }
                }
                for (k,p) in d.ports.enumerated() {
                    let pp = path + "/ports/\(k)"
                    let norm = sqrt(p.direction.x*p.direction.x+p.direction.y*p.direction.y+p.direction.z*p.direction.z)
                    if abs(norm-1) > tolerance { issue("direction_unit",pp + "/direction",integrity:true) }
                    if let a = p.area.value, let f = p.volumeFlow.value, let v = p.speed.value,
                       abs(a*v-f) > tolerance * max(f,1e-12) { issue("flow_area_speed",pp,integrity:true) }
                }
            }
            if Set(input.envelope.surfaces.map(\.surfaceID)) != Set(project.geometry.rooms.flatMap(\.surfaces).map(\.id)) { issue("envelope_incomplete",base + "/envelope/surfaces") }
            if Set(input.controls.map(\.deviceID)) != Set(input.hvac.map(\.id)) { issue("control_incomplete",base + "/controls") }
            if Set(input.ventilation.map(\.roomID)) != Set(project.geometry.rooms.map(\.id)) { issue("ventilation_incomplete",base + "/ventilation") }
            for (j,c) in input.envelope.surfaces.enumerated() {
                let b = c.boundary
                if (b.mode == .temperature && (b.temperature == nil || b.heatFlux != nil)) || (b.mode == .heatFlux && (b.heatFlux == nil || b.temperature != nil)) || (b.mode == .fromL1 && (b.temperature != nil || b.heatFlux != nil)) { issue("boundary_exclusive",base + "/envelope/surfaces/\(j)/boundary",integrity:true) }
                if b.mode == .fromL1 { issue("boundary_unresolved",base + "/envelope/surfaces/\(j)/boundary") }
            }
            for (j,v) in input.ventilation.enumerated() {
                if let a = v.outdoorAir.value, let b = v.exhaustAir.value, let c = v.infiltration.value, let d = v.exfiltration.value, let rho = v.density.value,
                   abs(a+c-b-d)*rho > tolerance*max(a+c,b+d,1e-12)*rho { issue("outdoor_exchange_balance",base + "/ventilation/\(j)") }
            }
            let environment = input.environment, ep = base + "/environment"
            if environment.representativeDate == nil { issue("required_input",ep + "/representativeDate") }
            if environment.timeZone == nil { issue("required_input",ep + "/timeZone") }
            if environment.weather == nil { issue("required_input",ep + "/weather") }
            if let date = environment.representativeDate {
                var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
                let parts = date.split(separator:"-").compactMap { Int($0) }
                var valid = date.range(of:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) != nil && parts.count == 3
                if valid {
                    let components = DateComponents(year:parts[0],month:parts[1],day:parts[2])
                    if let value = calendar.date(from:components) { let result = calendar.dateComponents([.year,.month,.day],from:value); valid = result.year == parts[0] && result.month == parts[1] && result.day == parts[2] && parts[0] >= 1 }
                    else { valid = false }
                }
                if !valid { issue("representative_date",ep + "/representativeDate",integrity:true) }
            }
            if let zone = environment.timeZone, TimeZone(identifier:zone) == nil { issue("time_zone",ep + "/timeZone",integrity:true) }
            if let weather = environment.weather {
                let path = weather.relativePath
                if path.isEmpty || path.hasPrefix("/") || path.contains("\\") || path.contains(":") || path.split(separator:"/",omittingEmptySubsequences:false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { issue("relative_path",ep + "/weather/relativePath",integrity:true) }
                if weather.sha256.range(of:"^[a-fA-F0-9]{64}$",options:.regularExpression) == nil { issue("content_hash",ep + "/weather/sha256",integrity:true) }
            }
            if Set(input.envelope.windows.map(\.openingID)) != Set(project.geometry.rooms.flatMap(\.openings).filter { $0.kind == .window }.map(\.id)) { issue("windows_incomplete",base + "/envelope/windows") }
            var schedulePaths: [String] = []
            for (prefix,count) in [("usage/occupants",input.usage.occupants.count),("usage/equipment",input.usage.equipment.count),("controls",input.controls.count)] {
                schedulePaths += (0..<count).map { base + "/" + prefix + "/\($0)/schedule/intervals" }
            }
            issues.append(contentsOf:try InputRequirements(fullDaySchedulePaths:schedulePaths).validate(project,registry:registry))
            for (j,seat) in input.usage.seats.enumerated() where seat.samples.isEmpty { issue("sample_required",base + "/usage/seats/\(j)/samples") }
            for (j,v) in input.ventilation.enumerated() {
                let openings = Set(project.geometry.rooms.filter { $0.id == v.roomID }.flatMap(\.openings).map(\.id))
                if Set(v.openings.map(\.openingID)) != openings { issue("opening_states_incomplete",base + "/ventilation/\(j)/openings") }
                if Set(v.openings.map(\.openingID)).count != v.openings.count { issue("duplicate_assignment",base + "/ventilation/\(j)/openings",integrity:true) }
            }
            if s.evaluation.cost.currency == nil && (s.evaluation.cost.tariffs.contains { $0.rate.value != nil } || s.evaluation.cost.quotes.contains { $0.amount.value != nil }) { issue("currency_required","/scenarios/\(i)/evaluation/cost/currency",integrity:true) }
            if let currency = s.evaluation.cost.currency, currency.range(of:"^[A-Z]{3}$",options:.regularExpression) == nil { issue("currency","/scenarios/\(i)/evaluation/cost/currency",integrity:true) }
        }
        return issues
    }
}
