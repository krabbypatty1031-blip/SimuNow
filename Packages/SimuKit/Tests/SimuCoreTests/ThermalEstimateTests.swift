import Foundation
import Testing
import SimuCore
import SimuSimulation
import SimuWorkspace

private let n4Source = SourceRecord(kind:.user,note:"Synthetic analytical fixture, not a measured room")
// Fixed test-only identities keep disk parent binding reproducible in Debug and Release.
private func n4Project() throws -> ProjectDocument {
    func id(_ n:Int)->UUID { UUID(uuidString:String(format:"00000004-0000-4000-8000-%012d",n))! }
    func length(_ x:Double)->Length { .known(value:x,source:n4Source) }
    let room=Room(id:id(1),name:"N4 synthetic 6×4×3",shape:try .init(RectangularRoom(dimensions:.init(width:length(6),depth:length(4),height:length(3)))),northAngle:.unknown(reason:"Synthetic"),surfaces:SurfaceFace.allCases.enumerated().map{.init(id:id(2+$0.offset),face:$0.element)})
    var scenarios:[Scenario]=[]
    for (i,yaw) in [0.0,30.0,-30.0].enumerated() {
        let split=SingleSplit(coolingCapacity:.unknown(reason:"No thermal basis"),electricalPower:.unknown(reason:"No electrical basis"),cop:.unknown(reason:"Unused"))
        let port=AirPort(id:id(21),role:.supply,position:.init(x:0.05,y:2,z:1.5),direction:.init(x:cos(yaw * .pi/180),y:sin(yaw * .pi/180),z:0),area:.unknown(reason:"Unused"),volumeFlow:.unknown(reason:"Unused"),speed:.unknown(reason:"Unused"),density:.unknown(reason:"Unused"))
        let device=HVACDevice(id:id(20),roomID:room.id,name:"N4 synthetic split",position:port.position,definition:try .init(split),ports:[port],supplyTemperature:.unknown(reason:"Unused"))
        var scenario=Scenario.unfinished(id:id(10+i),name:"N4 synthetic \(yaw)°")
        scenario.inputs.hvac=[device]
        scenario.inputs.usage.seats=[.init(id:id(30),roomID:room.id,name:"N4 target",position:.init(x:2,y:2,z:1.5),samples:[.init(id:id(40),position:.init(x:2,y:2,z:1.5))])]
        scenarios.append(scenario)
    }
    return .init(id:id(1000),name:"N4 synthetic tests",spaceType:.office,geometry:.init(rooms:[room]),scenarios:scenarios)
}
private func n4Power(watts:Double=1000,basis:ElectricalPowerBasis = .declaredScenario,bounds:UncertaintyBounds?=nil,start:Int=0,end:Int=120) -> PowerEstimateConfiguration {
    .init(requestedWindows:[.init(startMinute:start,endMinute:end)],intervals:[.init(startMinute:start,endMinute:end,power:.known(value:watts,source:n4Source,uncertainty:bounds),basis:basis)],ratedContinuousConfirmed:basis == .ratedContinuous)
}
private func n4Heat(values:[String:Double]=[:],bounds:[String:UncertaintyBounds]=[:],excluded:[String]=[],capacity:ThermalPower?=nil,totalCapacity:ThermalPower?=nil,shr:Ratio?=nil,selected:[String]?=nil,relationship:String="unknownDependenceEnvelope",sources:[HeatInternalSource]?=nil) -> SteadyHeatBalanceConfiguration {
    func q<Q>(_ name:String,_ defaultValue:Double)->PhysicalParameter<Q> { .known(value:values[name] ?? defaultValue,source:n4Source,uncertainty:bounds[name]) }
    let fields=selected ?? bounds.keys.sorted()
    return .init(conditionMinute:600,conductance:q("conductance",100),indoorTemperature:q("indoorTemperature",20),outdoorTemperature:q("outdoorTemperature",30),outdoorAir:q("outdoorAir",0),infiltration:q("infiltration",0),density:q("density",1.2),specificHeat:q("specificHeat",1000),internalSensibleHeat:q("internalSensibleHeat",0),solarSensibleHeat:q("solarSensibleHeat",0),excludedTerms:excluded,sensibleCoolingCapacity:capacity,
                 coverage:.init(conductanceScope:"Synthetic explicit UA aggregate",internalSensibleScope:"Synthetic declared aggregate includes people/equipment exactly once",airPropertyConditions:"Synthetic constants applicable to declared temperature case",indoorConditionConfirmed:true,source:n4Source),internalSources:sources,exclusions:excluded.map{.init(term:$0,reason:"Synthetic explicitly excluded term")},totalCoolingCapacity:totalCapacity,sensibleHeatRatio:shr,
                 sensitivity:fields.isEmpty ? nil:.init(fields:fields,relationship:relationship,source:n4Source))
}
private func n4Evidence(project:ProjectDocument?=nil,power:PowerEstimateConfiguration?=nil,heat:SteadyHeatBalanceConfiguration?=nil,scenarioIndex:Int=0) throws -> FixedEstimateEvidence {
    let project=try project ?? n4Project(),kind:AnalysisKind=heat==nil ? .powerEstimate:.steadyHeatBalance
    let configuration=AnalysisConfiguration(payload:heat.map{.steadyHeatBalance($0)} ?? .powerEstimate(power ?? n4Power()))
    let request=try AnalysisInputResolver().request(project:project,scenarioID:project.scenarios[scenarioIndex].id,method:.init(kind:kind),configuration:configuration)
    let payload:LocalAnalysisPayload=try heat.map{.steadyHeatBalance(try SteadyHeatBalance.calculate($0))} ?? .powerEstimate(PowerIntegrator.integrate(power ?? n4Power(),deviceIDs:project.scenarios[scenarioIndex].inputs.hvac.map(\.id)))
    let result=LocalAnalysisResult(identity:request.identity,method:request.method,checks:.init(state:.passed),assumptions:[],elapsedSeconds:0,payload:payload)
    return .init(request:request,result:result,currentInputHash:request.identity.inputHash)
}
private func n4Cost(_ e:FixedEstimateEvidence,rate:Double=0.1,currency:String?="EUR",tariffs:[CostTariffInterval]?=nil) throws -> CostEvaluationRecord {
    guard case .powerEstimate(let p)=e.result.payload else { throw ProjectDataError.contract("test requires power") }
    return try CostEvaluator.evaluate(request:e.request,result:e.result,configuration:.init(requestedWindows:p.requestedWindows,currency:currency,tariffs:tariffs ?? [.init(startMinute:0,endMinute:1440,rate:.known(value:rate,source:n4Source))]))
}
@Test func n4PowerAnalyticalSegmentsAndCrossMidnight() throws {
    #expect(try PowerIntegrator.integrate(n4Power()).totalEnergyKWh == 2)
    let split=PowerEstimateConfiguration(requestedWindows:[.init(startMinute:0,endMinute:120)],intervals:[.init(startMinute:0,endMinute:60,power:.known(value:500,source:n4Source),basis:.declaredScenario),.init(startMinute:60,endMinute:120,power:.known(value:1000,source:n4Source),basis:.declaredScenario)])
    #expect(try PowerIntegrator.integrate(split).totalEnergyKWh == 1.5)
    let windows=try PowerIntegrator.splitAcrossMidnight(startMinute:1320,endMinute:480)
    let config=PowerEstimateConfiguration(requestedWindows:windows,intervals:windows.map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute,power:.known(value:1000,source:n4Source),basis:.declaredScenario)})
    #expect(try PowerIntegrator.integrate(config).totalEnergyKWh == 10)
}
@Test func n4PowerUnknownGapAndExplicitZero() throws {
    let unknown=PowerEstimateConfiguration(requestedWindows:[.init(startMinute:0,endMinute:120)],intervals:[.init(startMinute:0,endMinute:60,power:.known(value:1000,source:n4Source),basis:.declaredScenario),.init(startMinute:60,endMinute:120,power:.unknown(reason:"No reading"),basis:.declaredScenario)])
    let draft=try PowerIntegrator.draft(unknown)
    #expect(draft.payload.totalEnergyKWh == nil && draft.payload.knownSubtotalKWh == 1 && draft.coveredMinutes == 60)
    #expect(throws:(any Error).self) { try PowerIntegrator.integrate(unknown) }
    let gap=PowerEstimateConfiguration(requestedWindows:unknown.requestedWindows,intervals:Array(unknown.intervals.prefix(1)))
    #expect(try PowerIntegrator.draft(gap).missingReasons.contains{$0.code=="power_coverage_gap"})
    #expect(try PowerIntegrator.integrate(n4Power(watts:0)).totalEnergyKWh == 0)
    let outside=PowerEstimateConfiguration(requestedWindows:[.init(startMinute:0,endMinute:60)],intervals:unknown.intervals)
    #expect(try PowerIntegrator.integrate(outside).totalEnergyKWh == 1)
}
@Test func n4PowerRejectsMalformedAndUnsupportedBasisEvidence() throws {
    for watts in [-1.0,Double.infinity,Double.nan] { #expect(throws:(any Error).self){try PowerIntegrator.integrate(n4Power(watts:watts))} }
    let overlap=PowerEstimateConfiguration(requestedWindows:[.init(startMinute:0,endMinute:120)],intervals:n4Power().intervals+n4Power(start:60,end:90).intervals)
    #expect(throws:(any Error).self){try PowerIntegrator.integrate(overlap)}
    let rated=n4Power(basis:.ratedContinuous)
    #expect(try PowerIntegrator.integrate(rated).totalEnergyKWh == 2)
    let unconfirmed=PowerEstimateConfiguration(requestedWindows:rated.requestedWindows,intervals:rated.intervals)
    #expect(throws:(any Error).self){try PowerIntegrator.integrate(unconfirmed)}
    #expect(throws:(any Error).self){try PowerIntegrator.integrate(n4Power(basis:.measuredAverage))}
    let schedule=DailySchedule(intervals:[.init(startMinute:0,endMinute:120,fraction:.known(value:0.5,source:n4Source))])
    #expect(throws:(any Error).self){try PowerIntegrator.intervalsFromSwitches(schedule,power:.known(value:1000,source:n4Source),basis:.ratedContinuous,explicitlyAccepted:true)}
}
@Test func n4PowerAggregateCoverageAndMethodHash() throws {
    var project=try n4Project(),original=try n4Evidence(project:project)
    project.scenarios[0].inputs.hvac[0].ports[0].direction = .init(x:0,y:1,z:0)
    #expect(try n4Evidence(project:project).request.identity.inputHash == original.request.identity.inputHash)
    let changed=try n4Evidence(power:n4Power(basis:.ratedContinuous))
    #expect(changed.request.identity.inputHash != original.request.identity.inputHash)
    var second=project.scenarios[0].inputs.hvac[0];second.id=UUID();second.ports=[];project.scenarios[0].inputs.hvac.append(second)
    let ids=project.scenarios[0].inputs.hvac.map(\.id)
    #expect(!ThermalEstimateValidation.powerMissing(n4Power(),deviceIDs:ids).isEmpty)
    let c=PowerEstimateConfiguration(requestedWindows:n4Power().requestedWindows,intervals:n4Power().intervals,aggregateDeviceIDs:ids,aggregateCoverageNote:"Explicit sum of both electrical inputs")
    #expect(try PowerIntegrator.integrate(c,deviceIDs:ids).totalEnergyKWh==2)
    original=try n4Evidence(power:n4Power(bounds:.init(lower:500,upper:1500,meaning:"Declared scenario endpoints")))
    guard case .powerEstimate(let p)=original.result.payload else { return }
    #expect(p.lowerEnergyKWh==1 && p.upperEnergyKWh==3)
}
@Test func n4CostDecimalBoundaryUnionAndMissing() throws {
    let e=try n4Evidence(),tariffs=[CostTariffInterval(startMinute:0,endMinute:60,rate:.known(value:0.1,source:n4Source)),.init(startMinute:60,endMinute:1440,rate:.known(value:0.2,source:n4Source))]
    let cost=try n4Cost(e,tariffs:tariffs)
    #expect(cost.payload.totalCostDecimal=="0.3" && cost.payload.segments.count==2)
    #expect(try n4Cost(e,currency:nil).payload.totalCostDecimal==nil)
    let gap=try n4Cost(e,tariffs:[tariffs[0]])
    #expect(gap.payload.totalCostDecimal==nil && gap.payload.segments.count==1)
    #expect(try n4Cost(e,rate:0).payload.totalCostDecimal=="0")
    #expect(throws:(any Error).self){try n4Cost(e,tariffs:tariffs+[tariffs[0]])}
    #expect(throws:(any Error).self){try n4Cost(e,rate:-0.1)}
    #expect(try n4Cost(e,rate:0.2).evaluationHash != cost.evaluationHash)
    #expect(try n4Cost(e,currency:"USD").evaluationHash != cost.evaluationHash)
}
@Test func n4CostManySmallFragmentsNoDisplayRounding() throws {
    let e=try n4Evidence(power:n4Power(watts:1,start:0,end:120))
    let tariffs=(0..<120).map{CostTariffInterval(startMinute:$0,endMinute:$0+1,rate:.known(value:0.1,source:n4Source))}
    let p=try n4Cost(e,tariffs:tariffs).payload
    let exact=Decimal(1)/Decimal(60000)*Decimal(120)*Decimal(string:"0.1")!
    let actual=Decimal(string:p.totalCostDecimal!)!
    #expect(abs(NSDecimalNumber(decimal:actual-exact).doubleValue)<1e-35)
    #expect(p.segments.count==120 && p.totalCostDecimal != "0")
}
@Test func n4HeatAnalyticalLedgerAndNegativeSignedBalance() throws {
    #expect(try SteadyHeatBalance.calculate(n4Heat()).coolingSensibleWatts==1000)
    #expect(try SteadyHeatBalance.calculate(n4Heat(values:["outdoorAir":0.1])).coolingSensibleWatts==2200)
    let cold=try SteadyHeatBalance.calculate(n4Heat(values:["outdoorTemperature":10]))
    #expect(cold.totalSignedWatts == -1000 && cold.coolingSensibleWatts==0)
    #expect(cold.terms.first?.signedWatts == -1000)
}
@Test func n4HeatInternalSourcesCountTotalOnceAndRangesValidate() throws {
    let source=HeatInternalSource(entityID:UUID(),description:"Person total sensible; radiant/convection not duplicated",sensible:.known(value:100,source:n4Source),effectiveFraction:.known(value:0.5,source:n4Source))
    #expect(try SteadyHeatBalance.calculate(n4Heat(values:["internalSensibleHeat":50],sources:[source])).coolingSensibleWatts==1050)
    #expect(throws:(any Error).self){try SteadyHeatBalance.calculate(n4Heat(values:["internalSensibleHeat":150],sources:[source]))}
    for f in ["density","specificHeat"] { #expect(throws:(any Error).self){try SteadyHeatBalance.calculate(n4Heat(bounds:[f:.init(lower:0,upper:2000,meaning:"Invalid support endpoint")]))} }
}
@Test func n4HeatExcludedSubsetAndCapacityEvidence() throws {
    let capacity:ThermalPower = .known(value:2000,source:n4Source)
    #expect(try SteadyHeatBalance.calculate(n4Heat(capacity:capacity)).capacityScreen == .sufficientForDeclaredSensibleCase)
    #expect(try SteadyHeatBalance.calculate(n4Heat(excluded:["solarSensibleHeat"],capacity:capacity)).capacityScreen == .cannotEvaluate)
    #expect(try SteadyHeatBalance.calculate(n4Heat(totalCapacity:capacity)).capacityScreen == .cannotEvaluate)
    #expect(try SteadyHeatBalance.calculate(n4Heat(totalCapacity:capacity,shr:.known(value:0.8,source:n4Source))).adoptedSensibleCapacityWatts==1600)
    let range:ThermalPower = .known(value:1000,source:n4Source,uncertainty:.init(lower:500,upper:1500,meaning:"Capacity endpoint range"))
    #expect(try SteadyHeatBalance.calculate(n4Heat(values:["conductance":90],capacity:range)).capacityScreen == .cannotEvaluate)
}
@Test func n4HeatTwoInputsFiveScenariosNoProbabilityAndNoIgnoredRange() throws {
    let ranges=["conductance":UncertaintyBounds(lower:80,upper:120,meaning:"Declared UA range"),"outdoorTemperature":.init(lower:28,upper:32,meaning:"Declared outdoor scenario range")]
    let result=try SteadyHeatBalance.calculate(n4Heat(bounds:ranges))
    #expect(result.scenarios?.count==5 && result.lowerCoolingSensibleWatts==640 && result.upperCoolingSensibleWatts==1440)
    #expect(throws:(any Error).self){try SteadyHeatBalance.calculate(n4Heat(bounds:ranges,selected:[]))}
    #expect(throws:(any Error).self){try SteadyHeatBalance.calculate(n4Heat(bounds:ranges,relationship:"knownCorrelated"))}
    var excessive=ranges;excessive["indoorTemperature"] = .init(lower:19,upper:21,meaning:"Third interval")
    #expect(throws:(any Error).self){try SteadyHeatBalance.calculate(n4Heat(bounds:excessive))}
}
@Test func n4ComparisonFixedFreshnessWindowsZeroAndRanges() throws {
    let baseline=try n4Evidence(),candidate=try n4Evidence(power:n4Power(),scenarioIndex:1)
    let same=try EstimateComparator.compare(baseline:baseline,candidate:candidate,decisionVariables:["direction"])
    #expect(same.metrics?.first?.absoluteDifference==0 && same.metrics?.first?.percentDifference==0)
    let zero=try n4Evidence(power:n4Power(watts:0)),zeroComparison=try EstimateComparator.compare(baseline:zero,candidate:candidate,decisionVariables:["powerIntervals"])
    #expect(zeroComparison.metrics?.first?.percentDifference==nil)
    let stale=FixedEstimateEvidence(request:candidate.request,result:candidate.result,currentInputHash:nil)
    #expect(try EstimateComparator.compare(baseline:baseline,candidate:stale,decisionVariables:["powerIntervals"]).incomparableReasons.contains{$0.code=="stale_run"})
    let range=try n4Evidence(power:n4Power(watts:1100,bounds:.init(lower:800,upper:1400,meaning:"Declared endpoints")),scenarioIndex:1)
    let overlap=try EstimateComparator.compare(baseline:baseline,candidate:range,decisionVariables:["powerIntervals"])
    #expect(overlap.metrics?.first?.ranking == "overlapNoStableRanking" && overlap.metrics?.first?.percentDifference==nil)
    let heat=try n4Evidence(heat:n4Heat(),scenarioIndex:1)
    #expect(try EstimateComparator.compare(baseline:baseline,candidate:heat,decisionVariables:[]).incomparableReasons.contains{$0.code=="method_mismatch"})
    let frozen=same;var project=try n4Project();project.scenarios[1].name="Edited later";#expect(same==frozen)
}
@Test func n4PublicSourceScenarioAndIndependentWireExport() throws {
    let source=SourceRecord(kind:.manufacturer,reference:"https://library.mitsubishielectric.co.uk/pdf/download_full/4788",note:"February 2026 p2 MUZ-AY25VG2 SYSTEM POWER INPUT cooling nominal 0.60 kW; explicit reference 08:00–10:00 continuous, not measured")
    let power=PowerEstimateConfiguration(requestedWindows:[.init(startMinute:480,endMinute:600)],intervals:[.init(startMinute:480,endMinute:600,power:.known(value:600,source:source),basis:.ratedContinuous)],ratedContinuousConfirmed:true)
    let e=try n4Evidence(power:power),rateSource=SourceRecord(kind:.preset,reference:"https://particulier.edf.fr/content/dam/2-Actifs/Documents/Offres/Grille_prix_Tarif_Bleu.pdf",note:"Effective 2026-08-01 Option Base 6 kVA 20.01 euro cents TTC/kWh; subscription/equipment/installation excluded; France residential tariff only")
    let cost=try n4Cost(e,tariffs:[.init(startMinute:480,endMinute:600,rate:.known(value:0.2001,source:rateSource))])
    #expect(cost.payload.totalCostDecimal=="0.24012")
    let heat=try n4Evidence(heat:n4Heat())
    let comparison=try EstimateComparator.compare(baseline:e,candidate:n4Evidence(power:power,scenarioIndex:1),decisionVariables:["direction"])
    let codec=NativeAnalysisCodec()
    #expect(try codec.decodeCostEvaluation(codec.encodeCostEvaluation(cost)) == cost)
    #expect(try codec.decodeComparisonSnapshot(codec.encodeComparisonSnapshot(comparison)) == comparison)
    if let path=ProcessInfo.processInfo.environment["SIMUNOW_NATIVE_CONTRACT_DIR"] {
        let folder=URL(fileURLWithPath:path)
        try codec.encodeRequest(e.request).write(to:folder.appendingPathComponent("n4-power-request.json"))
        try codec.encodeResult(e.result).write(to:folder.appendingPathComponent("n4-power-result.json"))
        try codec.encodeRequest(heat.request).write(to:folder.appendingPathComponent("n4-heat-request.json"))
        try codec.encodeResult(heat.result).write(to:folder.appendingPathComponent("n4-heat-result.json"))
        try codec.encodeCostEvaluation(cost).write(to:folder.appendingPathComponent("n4-cost-evaluation.json"))
        try codec.encodeComparisonSnapshot(comparison).write(to:folder.appendingPathComponent("n4-comparison-snapshot.json"))
    }
}
@Test func n4CostAppendKeepsParentBytesAndDiskRoundTrip() async throws {
    let e=try n4Evidence(),parent=try NativeArtifactCodec().make(request:e.request,result:e.result),cost=try n4Cost(e),artifact=try NativeCostEvaluationCodec.make(cost,parent:parent)
    let original=try SimuNowDocument(project:n4Project()),withRun=try original.appendingNativeAnalysis(parent,expectedProjectID:original.project.id)
    let saved=try withRun.appendingCostEvaluation(artifact,expectedProjectID:original.project.id)
    let rootPath="runs/\(e.result.identity.runID.uuidString.lowercased())/native-analysis/"
    for name in ["input.json","result.json"] { #expect(ProjectPackageEntry.directory(saved.preservedEntries).entry(at:rootPath+name)==ProjectPackageEntry.directory(withRun.preservedEntries).entry(at:rootPath+name)) }
    #expect(try saved.appendingCostEvaluation(artifact,expectedProjectID:original.project.id).preservedEntries==saved.preservedEntries)
    let url=FileManager.default.temporaryDirectory.appendingPathComponent("N4-synthetic-\(UUID()).simunow",isDirectory:true)
    defer { try? FileManager.default.removeItem(at:url) }
    let io=ProjectPackageIO();try await io.writePackage(saved,to:url);let reopened=try await io.readPackage(from:url)
    let loaded=try NativeArtifactCodec().load(runID:e.result.identity.runID,entries:reopened.preservedEntries,projectID:reopened.project.id)
    #expect(try NativeCostEvaluationCodec.load(hash:cost.evaluationHash,parent:loaded,entries:reopened.preservedEntries)==cost)
    #expect(throws:(any Error).self){try withRun.appendingCostEvaluation(artifact,expectedProjectID:UUID())}
    let second=try n4Cost(e,rate:0.2),ticket=try NativeCostEvaluationCodec.make(second,parent:loaded,entries:reopened.preservedEntries)
    #expect(throws:(any Error).self){try withRun.appendingCostEvaluation(ticket,expectedProjectID:withRun.project.id)} // Parent evaluation index was removed.
    let withSecond=try reopened.appendingCostEvaluation(ticket,expectedProjectID:reopened.project.id)
    #expect(ProjectPackageEntry.directory(withSecond.preservedEntries).entry(at:rootPath+"input.json")==ProjectPackageEntry.directory(saved.preservedEntries).entry(at:rootPath+"input.json"))
    // A ticket prepared before a different evaluation arrived must fail atomically;
    // the newer manifest and both fixed records remain untouched.
    let third=try NativeCostEvaluationCodec.make(n4Cost(e,rate:0.3),parent:parent)
    #expect(throws:(any Error).self){try withSecond.appendingCostEvaluation(third,expectedProjectID:withSecond.project.id)}
    #expect(try NativeCostEvaluationCodec.load(hash:second.evaluationHash,parent:NativeArtifactCodec().load(runID:e.result.identity.runID,entries:withSecond.preservedEntries,projectID:withSecond.project.id),entries:withSecond.preservedEntries)==second)
}

@Test func n4TariffRangesAndUndeclaredPowerChanges() throws {
    let e=try n4Evidence(power:n4Power(bounds:.init(lower:500,upper:1500,meaning:"Power endpoints")))
    let rates=[CostTariffInterval(startMinute:0,endMinute:120,rate:.known(value:0.2,source:n4Source,uncertainty:.init(lower:0.1,upper:0.3,meaning:"Tariff endpoints")))]
    let c=try n4Cost(e,tariffs:rates)
    #expect(c.payload.lowerCostDecimal=="0.1" && c.payload.upperCostDecimal=="0.9")
    let candidate=try n4Evidence(power:n4Power(watts:500),scenarioIndex:1)
    let snapshot=try EstimateComparator.compare(baseline:e,candidate:candidate,decisionVariables:[])
    #expect(snapshot.incomparableReasons.contains{$0.code=="undeclared_power_change"})
    #expect(snapshot.metrics?.first?.ranking=="cannotRank")
}
@Test func n4ComparedBasisIgnoresUnadoptedAndEquivalentSplitting() throws {
    let b=try n4Evidence(),config=PowerEstimateConfiguration(requestedWindows:[.init(startMinute:0,endMinute:120)],intervals:[.init(startMinute:0,endMinute:60,power:.known(value:1000,source:n4Source),basis:.declaredScenario),.init(startMinute:60,endMinute:120,power:.known(value:1000,source:n4Source),basis:.declaredScenario),.init(startMinute:120,endMinute:1440,power:.unknown(reason:"Outside requested window"),basis:.ratedContinuous)])
    let c=try n4Evidence(power:config,scenarioIndex:1)
    let result=try EstimateComparator.compare(baseline:b,candidate:c,decisionVariables:[])
    #expect(result.incomparableReasons.isEmpty && result.metrics?.first?.absoluteDifference==0)
}
@Test func n4InternalSourceIntervalsRejectedRatherThanIgnored() throws {
    let source=HeatInternalSource(entityID:UUID(),description:"Source with bounds",sensible:.known(value:100,source:n4Source,uncertainty:.init(lower:50,upper:150,meaning:"Not silently ignored")),effectiveFraction:.known(value:1,source:n4Source))
    #expect(throws:(any Error).self){try SteadyHeatBalance.calculate(n4Heat(values:["internalSensibleHeat":100],sources:[source]))}
}
@Test func n4DraftRetainsSourcesRejectsNaNAndUsesSameUndo() async throws {
    let project=try n4Project(),id=project.scenarios[0].id,source=SourceRecord(kind:.preset,reference:"synthetic.N4.range",note:"Source note retained")
    var configuration=AnalysisConfigurationStore(projectID:project.id)
    let heat=n4Heat(bounds:["conductance":.init(lower:80,upper:120,meaning:"UA range")])
    let initial=SteadyHeatBalanceConfiguration(conditionMinute:heat.conditionMinute,conductance:heat.conductance,indoorTemperature:heat.indoorTemperature,outdoorTemperature:heat.outdoorTemperature,outdoorAir:heat.outdoorAir,infiltration:heat.infiltration,density:heat.density,specificHeat:heat.specificHeat,internalSensibleHeat:heat.internalSensibleHeat,solarSensibleHeat:heat.solarSensibleHeat,coverage:heat.coverage,sensitivity:.init(fields:["conductance"],relationship:"unknownDependenceEnvelope",source:source))
    configuration.set(.init(payload:.steadyHeatBalance(initial)),scenarioID:id)
    let heatDraft=HeatBalanceDraft(project:project,scenarioID:id,store:configuration)
    guard case .steadyHeatBalance(let kept)=try heatDraft.configuration().payload else {return}
    #expect(kept==initial) // Includes absent optional capacity/SHR, exclusion representation and original source bytes.
    var draft=PowerEstimateDraft(project:project,scenarioID:id,store:nil)
    draft.intervals[0].parameter = .init(ElectricalPower.known(value:1000,source:n4Source));draft.intervals[0].basis = .declaredScenario
    draft.intervals[0].parameter.valueText="NaN"
    #expect(throws:(any Error).self){try draft.configuration()}
    draft.intervals[0].parameter.valueText="1000"
    let adopted=try draft.applying(currentProject:project,currentScenarioID:id,currentStore:nil)
    #expect(throws:(any Error).self){try draft.applying(currentProject:project,currentScenarioID:project.scenarios[1].id,currentStore:nil)}
    try await MainActor.run {
        let store=WorkspaceStore();store.load(project,baselineScenarioID:id)
        try store.updateAnalysisConfiguration(adopted)
        try store.undo();#expect(store.analysisConfiguration==nil)
        try store.redo();#expect(store.analysisConfiguration==adopted)
    }
}
@Test @MainActor func n4CoordinatorRepeatedCalculationUsesFreshRunIDs() async throws {
    let project=try n4Project(),id=project.scenarios[0].id,client=LocalAnalysisClient.production(),coordinator=ThermalEstimateCoordinator(client:client)
    var config=AnalysisConfigurationStore(projectID:project.id);config.set(.init(payload:.powerEstimate(n4Power())),scenarioID:id)
    coordinator.update(.init(project:project,scenarioID:id,configuration:config),registry:.builtIn)
    for _ in 0..<200 where coordinator.validating { try await Task.sleep(for:.milliseconds(10)) }
    #expect(coordinator.prepared[.powerEstimate] != nil)
    coordinator.run(.powerEstimate,persist:{_ in})
    for _ in 0..<200 where coordinator.power.stage?.isTerminal != true { try await Task.sleep(for:.milliseconds(10)) }
    let first=coordinator.power.activeIdentity?.runID
    #expect(coordinator.power.stage == .completed)
    coordinator.run(.powerEstimate,persist:{_ in})
    for _ in 0..<200 where coordinator.power.stage?.isTerminal != true { try await Task.sleep(for:.milliseconds(10)) }
    #expect(first != coordinator.power.activeIdentity?.runID && coordinator.power.stage == .completed)
    coordinator.stop()
}
@Test func n4NativeResultBoundaryRejectsPartialPassedAndWrongLedger() throws {
    let e=try n4Evidence(),codec=NativeAnalysisCodec()
    let partial=LocalAnalysisResult(identity:e.result.identity,method:e.result.method,checks:.init(state:.passed),assumptions:[],elapsedSeconds:0,payload:.powerEstimate(.init(requestedWindows:[.init(startMinute:0,endMinute:120)],segments:[],totalEnergyKWh:nil,knownSubtotalKWh:0)))
    #expect(throws:(any Error).self){try codec.encodeResult(partial)}
    let h=try n4Evidence(heat:n4Heat())
    let wrong=LocalAnalysisResult(identity:h.result.identity,method:h.result.method,checks:.init(state:.passed),assumptions:[],elapsedSeconds:0,payload:.steadyHeatBalance(.init(terms:[],totalSignedWatts:1000,coolingSensibleWatts:1000,excludedTerms:[],completeness:.completeDeclaredCase)))
    #expect(throws:(any Error).self){try codec.encodeResult(wrong)}
    let valid=try SteadyHeatBalance.calculate(n4Heat())
    let mislabeled=LocalAnalysisResult(identity:h.result.identity,method:h.result.method,checks:.init(state:.passed),assumptions:[],elapsedSeconds:0,payload:.steadyHeatBalance(.init(terms:valid.terms,totalSignedWatts:valid.totalSignedWatts,coolingSensibleWatts:valid.coolingSensibleWatts,excludedTerms:["undefinedTerm"],completeness:.declaredSubset)))
    #expect(throws:(any Error).self){try codec.encodeResult(mislabeled)}
}
@Test func n4ForeignProjectManifestCannotRebindRun() throws {
    let e=try n4Evidence(),a=try NativeArtifactCodec().make(request:e.request,result:e.result),other=UUID()
    let manifest=AnalysisArtifactManifest(runID:a.manifest.runID,scenarioID:a.manifest.scenarioID,projectID:other,files:a.manifest.files)
    let files:[String:ProjectPackageEntry]=["input.json":.file(a.inputData),"result.json":.file(a.resultData),"manifest.json":.file(try NativeAnalysisCodec().encodeManifest(manifest))]
    #expect(throws:(any Error).self){try NativeArtifactCodec().decode(files,expectedRunID:a.manifest.runID,expectedProjectID:other)}
}

@Test func n4DecimalUnderflowCannotBecomeFreeEnergy() throws {
    #expect(throws:(any Error).self){try CostEvaluator.decimal(Double.leastNonzeroMagnitude)}
    for tiny in [1e-128,1e-100] {
        let power=try n4Evidence(power:n4Power(watts:tiny))
        #expect(power.result.payload.kind == .powerEstimate)
        #expect(throws:(any Error).self){try n4Cost(power,rate:0.002)}
        #expect(throws:(any Error).self){try n4Cost(n4Evidence(),rate:tiny)}
        let boundedPower=try n4Evidence(power:n4Power(bounds:.init(lower:tiny,upper:1000,meaning:"Synthetic tiny endpoint must not become a giant cost")))
        #expect(throws:(any Error).self){try n4Cost(boundedPower)}
        let tariff=CostTariffInterval(startMinute:0,endMinute:1440,rate:.known(value:0.1,source:n4Source,uncertainty:.init(lower:tiny,upper:0.2,meaning:"Synthetic rate endpoint")))
        #expect(throws:(any Error).self){try n4Cost(n4Evidence(),tariffs:[tariff])}
    }
    #expect(try CostEvaluator.decimal(0) == 0)
    let tinySupported=try n4Cost(n4Evidence(power:n4Power(watts:1e-12)),rate:1e-12)
    #expect(Decimal(string:tinySupported.payload.totalCostDecimal!)! > 0)
}

@Test func n4CurrencyMismatchKeepsEnergyIndependentlyComparable() throws {
    let b=try n4Evidence(),c=try n4Evidence(scenarioIndex:1)
    let a=FixedEstimateEvidence(request:b.request,result:b.result,currentInputHash:b.currentInputHash,cost:try n4Cost(b))
    let d=FixedEstimateEvidence(request:c.request,result:c.result,currentInputHash:c.currentInputHash,cost:try n4Cost(c,currency:"USD"))
    let value=try EstimateComparator.compare(baseline:a,candidate:d,decisionVariables:["powerIntervals"])
    #expect(value.comparableItems.contains("energy"))
    #expect(value.metrics?.first{$0.metric=="energy"}?.absoluteDifference==0)
    #expect(value.metrics?.first{$0.metric=="referenceCost"}?.ranking=="cannotRank")
}
@Test func n4OnlyRenamingDoesNotInvalidateQualitativeComparisonBackground() async throws {
    var project=try n4Project()
    let config=AnalysisConfiguration(payload:.airflowPreview(.init(pathCount:1,maximumSegments:8)),acceptedAssumptions:[.genericCone])
    func evidence(_ project:ProjectDocument,_ index:Int) async throws -> FixedEstimateEvidence {
        let request=try AnalysisInputResolver().request(project:project,scenarioID:project.scenarios[index].id,method:.init(kind:.airflowPreview),configuration:config)
        let execution=try await AirflowPreviewExecutor().execute(request){_ in}
        let result=LocalAnalysisResult(identity:request.identity,method:request.method,checks:execution.checks,assumptions:request.resolvedInput.adoptedAssumptions,elapsedSeconds:0,payload:execution.payload)
        return .init(request:request,result:result,currentInputHash:request.identity.inputHash)
    }
    let baseline=try await evidence(project,0)
    project.geometry.rooms[0].name="Renamed room"
    project.scenarios[1].inputs.usage.seats[0].name="Renamed target"
    let candidate=try await evidence(project,1)
    #expect(try EstimateComparator.compare(baseline:baseline,candidate:candidate,decisionVariables:["direction"]).incomparableReasons.isEmpty)
}
@Test @MainActor func n4CostSaveFailureRetainsComputedSessionRecord() async throws {
    let evidence=try n4Evidence(),parent=try NativeArtifactCodec().make(request:evidence.request,result:evidence.result)
    let client=LocalAnalysisClient.production(),coordinator=ThermalEstimateCoordinator(client:client)
    let config=CostEvaluationConfiguration(requestedWindows:[.init(startMinute:0,endMinute:120)],currency:"EUR",tariffs:[.init(startMinute:0,endMinute:120,rate:.known(value:0.1,source:n4Source))])
    // Actual immutable document transaction rejects a missing fixed parent, not a fake failure.
    let document=try SimuNowDocument(project:n4Project())
    coordinator.evaluateCost(configuration:config,parent:parent,persist:{artifact in _=try document.appendingCostEvaluation(artifact,expectedProjectID:document.project.id)})
    for _ in 0..<400 where coordinator.evaluatingCost { try await Task.sleep(for:.milliseconds(10)) }
    #expect(coordinator.cost?.payload.totalCostDecimal=="0.2")
    if case .failed = coordinator.costPersistence {} else { Issue.record("Computed fee must retain independent failed save state") }
    #expect(document.preservedEntries.isEmpty)
    coordinator.stop()
}

private func n4RejectsSelfConsistentForgedEvidence(_ evidence:FixedEstimateEvidence,payload:LocalAnalysisPayload) throws {
    let result=LocalAnalysisResult(identity:evidence.result.identity,method:evidence.result.method,checks:.init(state:.passed),assumptions:evidence.result.assumptions,elapsedSeconds:0,payload:payload)
    let data=try NativeAnalysisCodec().encodeResult(result) // Shape, ledger sum and envelope remain valid.
    #expect(throws:(any Error).self){try ThermalEstimateEvidenceValidation.validate(request:evidence.request,result:result)}
    let forged=FixedEstimateEvidence(request:evidence.request,result:result,currentInputHash:evidence.currentInputHash)
    #expect(throws:(any Error).self){try EstimateComparator.compare(baseline:evidence,candidate:forged,decisionVariables:["powerIntervals","conductance"])}
    #expect(throws:(any Error).self){try NativeArtifactCodec().make(request:evidence.request,result:result)}
    let original=try NativeArtifactCodec().make(request:evidence.request,result:evidence.result)
    let files=original.manifest.files.map{file in file.relativePath == "result.json" ? AnalysisArtifactFile(relativePath:file.relativePath,byteCount:data.count,sha256:AnalysisHasher.sha256(data)):file}
    let manifest=AnalysisArtifactManifest(runID:original.manifest.runID,scenarioID:original.manifest.scenarioID,projectID:original.manifest.projectID,files:files)
    let entries:[String:ProjectPackageEntry]=["input.json":.file(original.inputData),"result.json":.file(data),"manifest.json":.file(try NativeAnalysisCodec().encodeManifest(manifest))]
    #expect(throws:(any Error).self){try NativeArtifactCodec().decode(entries,expectedRunID:manifest.runID,expectedProjectID:manifest.projectID)} // A forged valid SHA must not suffice.
}
@Test func n4ForgedPowerScaleAndOmittedInputBoundsCannotEnterEvidence() throws {
    let evidence=try n4Evidence(power:n4Power(bounds:.init(lower:500,upper:1500,meaning:"Frozen power bounds")))
    guard case .powerEstimate(let p)=evidence.result.payload else{return}
    let segments=p.segments.map{PowerEstimateSegment(startMinute:$0.startMinute,endMinute:$0.endMinute,powerWatts:$0.powerWatts/2,energyKWh:$0.energyKWh/2,basis:$0.basis)}
    try n4RejectsSelfConsistentForgedEvidence(evidence,payload:.powerEstimate(.init(timeBasis:p.timeBasis,requestedWindows:p.requestedWindows,segments:segments,totalEnergyKWh:p.totalEnergyKWh.map{$0/2},knownSubtotalKWh:p.knownSubtotalKWh/2,lowerEnergyKWh:p.lowerEnergyKWh.map{$0/2},upperEnergyKWh:p.upperEnergyKWh.map{$0/2})))
    try n4RejectsSelfConsistentForgedEvidence(evidence,payload:.powerEstimate(.init(timeBasis:p.timeBasis,requestedWindows:p.requestedWindows,segments:p.segments,totalEnergyKWh:p.totalEnergyKWh,knownSubtotalKWh:p.knownSubtotalKWh)))
}
@Test func n4ForgedHeatLedgerCapacityAndOmittedEndpointsCannotEnterEvidence() throws {
    let evidence=try n4Evidence(heat:n4Heat())
    guard case .steadyHeatBalance(let p)=evidence.result.payload else{return}
    let terms=p.terms.map{HeatBalanceTerm(id:$0.id,signedWatts:$0.signedWatts/2,description:$0.description)}
    let scenarios=p.scenarios?.map{HeatSensitivityScenario(id:$0.id,adoptedValues:$0.adoptedValues,totalSignedWatts:$0.totalSignedWatts/2,coolingSensibleWatts:$0.coolingSensibleWatts/2)}
    try n4RejectsSelfConsistentForgedEvidence(evidence,payload:.steadyHeatBalance(.init(terms:terms,totalSignedWatts:p.totalSignedWatts.map{$0/2},coolingSensibleWatts:p.coolingSensibleWatts.map{$0/2},excludedTerms:p.excludedTerms,capacityScreen:p.capacityScreen,completeness:p.completeness,lowerCoolingSensibleWatts:p.lowerCoolingSensibleWatts.map{$0/2},upperCoolingSensibleWatts:p.upperCoolingSensibleWatts.map{$0/2},scenarios:scenarios,notes:p.notes)))
    let capacity=try n4Evidence(heat:n4Heat(capacity:.known(value:500,source:n4Source)))
    guard case .steadyHeatBalance(let actual)=capacity.result.payload else{return}
    try n4RejectsSelfConsistentForgedEvidence(capacity,payload:.steadyHeatBalance(.init(terms:actual.terms,totalSignedWatts:actual.totalSignedWatts,coolingSensibleWatts:actual.coolingSensibleWatts,excludedTerms:actual.excludedTerms,capacityScreen:.sufficientForDeclaredSensibleCase,completeness:actual.completeness,lowerCoolingSensibleWatts:actual.lowerCoolingSensibleWatts,upperCoolingSensibleWatts:actual.upperCoolingSensibleWatts,scenarios:actual.scenarios,adoptedSensibleCapacityWatts:actual.adoptedSensibleCapacityWatts,notes:actual.notes)))
    let bounded=try n4Evidence(heat:n4Heat(bounds:["conductance":.init(lower:80,upper:120,meaning:"Frozen UA bounds")]))
    guard case .steadyHeatBalance(let bp)=bounded.result.payload else{return}
    try n4RejectsSelfConsistentForgedEvidence(bounded,payload:.steadyHeatBalance(.init(terms:bp.terms,totalSignedWatts:bp.totalSignedWatts,coolingSensibleWatts:bp.coolingSensibleWatts,excludedTerms:bp.excludedTerms,capacityScreen:bp.capacityScreen,completeness:bp.completeness,adoptedSensibleCapacityWatts:bp.adoptedSensibleCapacityWatts)))
}
