import Foundation
import Testing
import SimuCore
import SimuWorkspace

@Test func parameterDraftKeepsIncompleteTextOutsideModel() throws {
    var draft = PhysicalParameterDraft(Length.known(value: 3, source: .init(kind: .user)))
    for text in ["", "-", "1e", "NaN", "Infinity", "1,234"] {
        draft.enterValue(text)
        #expect(draft.valueText == text)
        #expect(throws: ParameterDraftError.self) { let _: Length = try draft.parameter(range: .positive) }
    }
    draft.enterValue("4.25")
    let parameter: Length = try draft.parameter(range: .positive)
    #expect(parameter.value == 4.25)
    #expect(PhysicalParameterDraft(Length.unknown(reason: "等待量测")).isKnown == false)
}

@Test func parameterDraftPreservesUnchangedProvenanceAndBounds() throws {
    let parameter = Length.known(value: 3,
        source: .init(kind: .measured, reference: "2026-10-03 激光尺记录", note: "南墙复核"),
        uncertainty: .init(lower: 2.9, upper: 3.1, meaning: "仪器容差"))
    var draft = PhysicalParameterDraft(parameter)
    #expect(try draft.parameter(as: LengthTag.self, range: .positive) == parameter)
    draft.enterValue("3.00")
    #expect(try draft.parameter(as: LengthTag.self, range: .positive) == parameter)
    draft.enterValue("4")
    #expect(draft.sourceKind == .user && draft.reference.isEmpty && draft.note.isEmpty)
    #expect(!draft.hasUncertainty)
    #expect(try draft.parameter(as: LengthTag.self).value == 4)
}

@Test func parameterDraftRequiresSourceAndUncertaintyMeaning() throws {
    var draft = PhysicalParameterDraft(Length.known(value: 3, source: .init(kind: .measured)))
    #expect(throws: ParameterDraftError.sourceReference) { let _: Length = try draft.parameter() }
    draft.reference = "test measurement record"
    draft.sourceKind = .assumed
    #expect(throws: ParameterDraftError.assumptionNote) { let _: Length = try draft.parameter() }
    draft.note = "人工测试假设"
    draft.hasUncertainty = true; draft.lowerText = "4"; draft.upperText = "5"; draft.uncertaintyMeaning = "误差范围"
    #expect(throws: ParameterDraftError.uncertainty) { let _: Length = try draft.parameter() }
    draft.lowerText = "2"; draft.uncertaintyMeaning = " "
    #expect(throws: ParameterDraftError.uncertainty) { let _: Length = try draft.parameter() }
    draft.uncertaintyMeaning = "误差范围"
    let parameter: Length = try draft.parameter()
    let decoded = try JSONDecoder().decode(Length.self, from: JSONEncoder().encode(parameter))
    #expect(decoded == parameter)
}

@Test func parameterDraftRangesAndExplicitUnknownAreIndependent() throws {
    var angle = PhysicalParameterDraft(Angle.known(value: 360, source: .init(kind: .user)))
    #expect(throws: ParameterDraftError.self) { let _: Angle = try angle.parameter(range: .northBearing) }
    angle.enterValue("0")
    #expect(try angle.parameter(as: AngleTag.self, range: .northBearing).value == 0)
    var ratio = PhysicalParameterDraft(Ratio.known(value: 1.1, source: .init(kind: .user)))
    #expect(throws: ParameterDraftError.self) { let _: Ratio = try ratio.parameter(range: .fraction) }
    ratio.isKnown = false; ratio.unknownReason = "仪器不可用"
    #expect(try ratio.parameter(as: RatioTag.self, range: .fraction) == .unknown(reason: "仪器不可用"))
    ratio.unknownReason = " "
    #expect(throws: ParameterDraftError.unknownReason) { let _: Ratio = try ratio.parameter() }
}

@Test func parameterSummaryIncludesRegisteredPayloadsAndUnknownExtensions() throws {
    var draft = RoomDraft()
    draft.width = PhysicalParameterDraft(Length.known(value: 6, source: .init(kind: .assumed, note: "人工测试尺寸")))
    var project = try RoomEditing.createProject(name: "summary", spaceType: .office, room: draft.room())
    let summary = try ParameterAssumptions.collect(from: project)
    #expect(summary.contains { $0.kind == .assumption && $0.path.hasSuffix("/shape/payload/dimensions/width") && $0.detail.contains("人工测试尺寸") })
    #expect(summary.contains { $0.kind == .unknown && $0.path.hasSuffix("/northAngle") })
    let record = ExtensionRecord(kind: "future.room", payloadVersion: 9, payload: .object(["opaque": .string("preserved")]))
    project.geometry.rooms[0].shape = record
    #expect(try ParameterAssumptions.collect(from: project).contains { $0.kind == .unsupported })
    #expect(project.geometry.rooms[0].shape == record)
}
