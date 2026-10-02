import Foundation
import Testing
import SimuCore
import SimuWorkspace

@Test func templatesCreateIndependentIdentitiesAndValidReferences() throws {
    for kind in ProjectTemplateKind.allCases {
        let options = ProjectTemplateOptions.defaults(for: kind)
        let first = try ProjectTemplateFactory.make(kind: kind, options: options)
        let second = try ProjectTemplateFactory.make(kind: kind, options: options)
        #expect(first.project.id != second.project.id)
        #expect(first.baselineScenarioID != second.baselineScenarioID)
        #expect(first.project.geometry.rooms[0].id != second.project.geometry.rooms[0].id)
        #expect(Set(first.project.geometry.rooms[0].surfaces.map(\.id)).isDisjoint(with: second.project.geometry.rooms[0].surfaces.map(\.id)))
        #expect(Set(first.project.scenarios[0].inputs.usage.seats.map(\.id)).isDisjoint(with: second.project.scenarios[0].inputs.usage.seats.map(\.id)))
        #expect(first.project.scenarios[0].inputs.usage.seats.count == options.seatCount)
        #expect(first.project.scenarios[0].id == first.baselineScenarioID)
        let report = try ProjectValidator().validate(first.project, registry: .builtIn)
        #expect(report.passes(.projectIntegrity))
        #expect(!report.passes(.inputPreparation))
        #expect(!report.issues.contains { ["dangling_reference", "duplicate_id", "point_bounds", "point_in_solid", "obstacle_overlap", "direction_unit"].contains($0.code) })
        #expect(try ProjectCodec(registry: .builtIn).decode(ProjectCodec(registry: .builtIn).encode(first.project)) == first.project)
    }
}

@Test func templateOverridesHaveProvenanceAndDoNotModifyDefaults() throws {
    let original = ProjectTemplateOptions.defaults(for: .office)
    var options = original
    options.width = 7.5
    options.seatCount = 3
    options.activeStartMinute = 600
    let result = try ProjectTemplateFactory.make(kind: .office, options: options)
    let shape = try #require(try result.project.geometry.rooms[0].shape.resolved(as: RectangularRoom.self, registry: .builtIn))
    if case .known(let value, let source, _) = shape.dimensions.width {
        #expect(value == 7.5)
        #expect(source.kind == .user)
        #expect(source.reference == "simunow.template.office.v1")
        #expect(source.note?.contains("用户覆盖") == true)
    } else { Issue.record("Overridden width was not known") }
    if case .known(_, let source, _) = shape.dimensions.depth {
        #expect(source.kind == .assumed)
        #expect(source.note?.contains("并非实测") == true)
    } else { Issue.record("Template depth was not known") }
    #expect(result.project.scenarios[0].inputs.usage.seats.count == 3)
    #expect(result.project.scenarios[0].inputs.usage.occupants.count == 3)
    let intervals = result.project.scenarios[0].inputs.usage.occupants[0].schedule.intervals
    #expect(intervals.map(\.startMinute) == [0, 600, 1080])
    #expect(intervals.map(\.endMinute) == [600, 1080, 1440])
    if case .known(_, let source, _) = intervals[1].fraction { #expect(source.kind == .user) }
    #expect(ProjectTemplateOptions.defaults(for: .office) == original)
}

@Test func templatesInventNoPhysicalWeatherCostOrComfortData() throws {
    for kind in ProjectTemplateKind.allCases {
        let result = try ProjectTemplateFactory.make(kind: kind, options: .defaults(for: kind))
        let input = result.project.scenarios[0].inputs
        let split = try #require(try input.hvac[0].definition.resolved(as: SingleSplit.self, registry: .builtIn))
        #expect(split.coolingCapacity.value == nil && split.electricalPower.value == nil && split.cop.value == nil)
        #expect(input.hvac[0].supplyTemperature.value == nil)
        #expect(input.controls[0].setpoint.value == nil)
        #expect(input.hvac[0].ports.allSatisfy { $0.area.value == nil && $0.volumeFlow.value == nil && $0.speed.value == nil && $0.density.value == nil })
        #expect(input.environment.weather == nil && input.environment.timeZone == nil && input.environment.representativeDate == nil)
        #expect(input.environment.indoorHumidity.value == nil)
        #expect(input.usage.occupants.allSatisfy { $0.activity.value == nil && $0.clothing.value == nil && $0.heat.sensible.value == nil && $0.heat.latent.value == nil })
        #expect(input.usage.equipment.allSatisfy { $0.heat.sensible.value == nil && $0.heat.convectiveFraction.value == nil })
        #expect(input.envelope.surfaces.isEmpty) // Surface exposure is unknown; no exterior wall assumption.
        #expect(result.project.scenarios[0].evaluation.cost == CostInputs())
        let report = try ProjectValidator().validate(result.project, registry: .builtIn)
        #expect(!report.issues.contains { $0.code == "source_required" })
    }
}

@Test func oversizedAndInconsistentLayoutsAreRejectedWithoutTruncation() {
    var options = ProjectTemplateOptions.defaults(for: .classroom)
    options.width = 5
    #expect(throws: (any Error).self) { try ProjectTemplateFactory.make(kind: .classroom, options: options) }
    options = .defaults(for: .office)
    options.seatCount = 5
    #expect(throws: (any Error).self) { try ProjectTemplateFactory.make(kind: .office, options: options) }
    options = .defaults(for: .office)
    options.rowSpacing = 0.8
    #expect(throws: (any Error).self) { try ProjectTemplateFactory.make(kind: .office, options: options) }
    options = .defaults(for: .office)
    options.height = .nan
    #expect(throws: (any Error).self) { try ProjectTemplateFactory.make(kind: .office, options: options) }
    options = .defaults(for: .office)
    options.columns = Int.max
    #expect(throws: (any Error).self) { try ProjectTemplateFactory.make(kind: .office, options: options) }
}

@Test func templateOptionalObjectsAndFullDayScheduleRemainConsistent() throws {
    var options = ProjectTemplateOptions.defaults(for: .office)
    options.includeOccupants = false; options.includeEquipment = false
    options.includeHVAC = false; options.includeFurniture = false
    options.includeDoor = false; options.includeWindow = false
    let emptyObjects = try ProjectTemplateFactory.make(kind: .office, options: options).project
    #expect(emptyObjects.geometry.obstacles.isEmpty && emptyObjects.geometry.rooms[0].openings.isEmpty)
    #expect(emptyObjects.scenarios[0].inputs.usage.occupants.isEmpty && emptyObjects.scenarios[0].inputs.usage.equipment.isEmpty)
    #expect(emptyObjects.scenarios[0].inputs.hvac.isEmpty && emptyObjects.scenarios[0].inputs.controls.isEmpty)
    #expect(emptyObjects.scenarios[0].inputs.ventilation[0].openings.isEmpty)
    options.includeOccupants = true
    options.activeStartMinute = 0; options.activeEndMinute = 1440
    let allDay = try ProjectTemplateFactory.make(kind: .office, options: options).project
    let schedule = allDay.scenarios[0].inputs.usage.occupants[0].schedule
    #expect(schedule.intervals.count == 1)
    #expect(schedule.intervals[0].startMinute == 0 && schedule.intervals[0].endMinute == 1440)
    #expect(try ProjectValidator().validate(allDay, registry: .builtIn).passes(.projectIntegrity))
}
