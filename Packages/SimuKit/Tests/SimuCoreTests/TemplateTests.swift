import CryptoKit
import Foundation
import Testing
@testable import SimuCore
@testable import SimuWorkspace

@Test func templatesPassIntegrityWithHongKongOctoberDefaults() throws {
    for project in [ProjectTemplates.office(), ProjectTemplates.classroom()] {
        let registry = ModelRegistry.builtIn
        let codec = ProjectCodec(registry: registry)
        #expect(try codec.decode(codec.encode(project)) == project)
        let report = try ProjectValidator().validate(project, registry: registry)
        #expect(report.passes(.projectIntegrity), "Integrity issues: \(report.issues)")
        #expect(report.passes(.inputPreparation), "Preparation issues: \(report.issues.map { "\($0.code) \($0.path)" })")
        let environment = project.scenarios[0].inputs.environment
        #expect(environment.representativeDate == HongKongOctoberClimate.representativeDate)
        #expect(environment.timeZone == HongKongOctoberClimate.timeZoneIdentifier)
        #expect(environment.outdoorTemperature.value == HongKongOctoberClimate.outdoorTemperatureC)
        #expect(environment.outdoorHumidity.value == HongKongOctoberClimate.relativeHumidity)
        #expect(environment.indoorHumidity.value == HongKongOctoberClimate.relativeHumidity)
        if case .known(_, let indoorSource, _) = environment.indoorHumidity {
            #expect(indoorSource.note?.contains("没有室内实测") == true)
        } else {
            Issue.record("indoor humidity must be a sourced preset")
        }
        #expect(environment.weather?.relativePath == HongKongOctoberClimate.weatherRelativePath)
        #expect(environment.weather?.sha256 == HongKongOctoberClimate.weatherSHA256)
        #expect(project.geometry.rooms[0].northAngle.value == HongKongOctoberClimate.northAngleDegrees)
        let exterior = project.scenarios[0].inputs.envelope.surfaces.filter { $0.exposure == Exposure.outdoors }
        #expect(exterior.count == 1)
        #expect(exterior[0].boundary.temperature?.value == HongKongOctoberClimate.outdoorTemperatureC)
        let snapshot = try ScenarioSnapshotBuilder.capture(project, scenarioID: project.scenarios[0].id)
        #expect(try codec.decodeSnapshot(codec.encodeSnapshot(snapshot)) == snapshot)
        let node = try JSONTreeCoding.encode(project)
        var unknowns = 0, knowns = 0, badUnknowns: [String] = [], badKnowns: [String] = []
        treeWalk(node) { path, n in
            if n["state"]?.string == "unknown" { unknowns += 1; if (n["reason"]?.string ?? "").isEmpty { badUnknowns.append(path) } }
            if n["state"]?.string == "known" { knowns += 1; if n["source"]?["kind"]?.string == nil { badKnowns.append(path) } }
        }
        #expect(badUnknowns.isEmpty, "Unknown without reason: \(badUnknowns)")
        #expect(badKnowns.isEmpty, "Known without source: \(badKnowns)")
        #expect(unknowns == 0 && knowns > 0)
    }
}

@Test func hongKongOctoberCitationMatchesRecordedHash() throws {
    let data = try HongKongOctoberClimate.citationData()
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    #expect(hex == HongKongOctoberClimate.weatherSHA256)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("25.7"))
    #expect(text.contains("0.73"))
    #expect(text.contains(HongKongOctoberClimate.citation))
    #expect(text.contains("not an hourly EnergyPlus weather file"))
}

@Test func wizardAppliesHongKongOctoberClimateAndStillNeedsHVAC() throws {
    let project = RoomWizardDraft().build()
    let environment = project.scenarios[0].inputs.environment
    #expect(environment.outdoorTemperature.value == HongKongOctoberClimate.outdoorTemperatureC)
    #expect(environment.outdoorHumidity.value == HongKongOctoberClimate.relativeHumidity)
    #expect(environment.representativeDate == HongKongOctoberClimate.representativeDate)
    #expect(environment.timeZone == HongKongOctoberClimate.timeZoneIdentifier)
    #expect(environment.weather?.sha256 == HongKongOctoberClimate.weatherSHA256)
    #expect(project.geometry.rooms[0].northAngle.value == 0)
    let exterior = project.scenarios[0].inputs.envelope.surfaces.filter { $0.exposure == Exposure.outdoors }
    #expect(exterior.allSatisfy { $0.boundary.temperature?.value == HongKongOctoberClimate.outdoorTemperatureC })
    var oriented = RoomWizardDraft()
    oriented.northKnown = true
    oriented.northText = "90"
    #expect(oriented.build().geometry.rooms[0].northAngle.value == 90)
    let report = try ProjectValidator().validate(project, registry: .builtIn)
    #expect(!report.passes(.inputPreparation))
    #expect(report.issues.contains { $0.code == "device_count" })
    #expect(!report.issues.contains { $0.path.hasSuffix("/outdoorTemperature") })
    #expect(!report.issues.contains { $0.path.hasSuffix("/weather") })
}

@Test func sidebarNamesOpeningsByWall() {
    let office = ProjectTemplates.office().geometry.rooms[0]
    #expect(office.openings.map { InputPresentation.openingListTitle($0, in: office) } == ["远侧墙的窗", "左墙的门"])
    let classroom = ProjectTemplates.classroom().geometry.rooms[0]
    #expect(classroom.openings.map { InputPresentation.openingListTitle($0, in: classroom) } == ["远侧墙的窗 1", "远侧墙的窗 2", "左墙的门"])
}

@Test func templateMassBalanceAndFlowConsistencyHold() throws {
    for project in [ProjectTemplates.office(), ProjectTemplates.classroom()] {
        let report = try ProjectValidator().validate(project, registry: .builtIn)
        let codes = report.issues.map(\.code)
        #expect(!codes.contains("recirculation_balance"))
        #expect(!codes.contains("flow_area_speed"))
        #expect(!codes.contains("direction_unit"))
        #expect(!codes.contains("schedule_coverage"))
        #expect(!codes.contains("point_in_solid"))
        #expect(!codes.contains("point_bounds"))
    }
}
