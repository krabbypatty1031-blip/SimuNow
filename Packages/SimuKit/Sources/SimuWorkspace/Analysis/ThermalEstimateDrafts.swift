import Foundation
import SimuCore
import SimuSimulation

public struct EstimateIntervalDraft: Equatable, Sendable, Identifiable {
    public let id=UUID()
    public var startText:String
    public var endText:String
    public var parameter:PhysicalParameterDraft
    public var basis:ElectricalPowerBasis?
    public var measurementPeriod:String
    public init(start:Int=0,end:Int=1440,parameter:PhysicalParameterDraft = .init(),basis:ElectricalPowerBasis?=nil,measurementPeriod:String="") {
        startText=String(start);endText=String(end);self.parameter=parameter;self.basis=basis;self.measurementPeriod=measurementPeriod
    }
    public func windows() throws -> [AnalysisTimeWindow] {
        guard let start=Int(startText),let end=Int(endText) else { throw ParameterDraftError.number }
        return try PowerIntegrator.splitAcrossMidnight(startMinute:start,endMinute:end)
    }
}
public struct PowerEstimateDraft: Identifiable, Sendable {
    public let id=UUID()
    public let project:ProjectDocument
    public let scenarioID:UUID
    public let store:AnalysisConfigurationStore?
    public let original:AnalysisConfiguration?
    public var windows:[EstimateIntervalDraft]
    public var intervals:[EstimateIntervalDraft]
    public var ratedConfirmed:Bool
    public var aggregateCoverageConfirmed:Bool
    public var aggregateNote:String
    public init(project:ProjectDocument,scenarioID:UUID,store:AnalysisConfigurationStore?) {
        self.project=project;self.scenarioID=scenarioID;self.store=store;original=store?.configuration(scenarioID:scenarioID,kind:.powerEstimate)
        let value:PowerEstimateConfiguration?
        if case .powerEstimate(let c)=original?.payload { value=c } else { value=nil }
        windows=value?.requestedWindows.map{.init(start:$0.startMinute,end:$0.endMinute)} ?? [.init()]
        intervals=value?.intervals.map{.init(start:$0.startMinute,end:$0.endMinute,parameter:.init($0.power),basis:$0.basis,measurementPeriod:$0.measurementPeriod ?? "")} ?? [.init()]
        ratedConfirmed=value?.ratedContinuousConfirmed ?? false;aggregateCoverageConfirmed=value?.aggregateDeviceIDs != nil;aggregateNote=value?.aggregateCoverageNote ?? ""
    }
    public mutating func importElectricalPower(registry:ModelRegistry) throws {
        guard let device=project.scenarios.first(where:{$0.id==scenarioID})?.inputs.hvac.first,
              let split=try? device.definition.resolved(as:SingleSplit.self,registry:registry) else { throw ProjectDataError.contract("没有可导入电功率的SingleSplit；制冷量和COP不采用。") }
        guard intervals.count==1 else { throw ProjectDataError.contract("导入草稿只支持一个当前功率片段，请明确选定片段。") }
        intervals[0].parameter = .init(split.electricalPower);intervals[0].basis=nil;ratedConfirmed=false
    }
    public func configuration() throws -> AnalysisConfiguration {
        let requests=try windows.flatMap{try $0.windows()}.sorted{$0.startMinute<$1.startMinute}
        let power=try intervals.flatMap{ item -> [AnalysisPowerInterval] in
            let p:ElectricalPower=try item.parameter.parameter(range:.nonnegative)
            if p.value != nil && item.basis == nil { throw ProjectDataError.contract("已知电功率需要明确basis：实测、指定情景或额定连续。") }
            return try item.windows().map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute,power:p,basis:item.basis ?? .declaredScenario,measurementPeriod:item.measurementPeriod.isEmpty ? nil:item.measurementPeriod)}
        }.sorted{$0.startMinute<$1.startMinute}
        let c=PowerEstimateConfiguration(requestedWindows:requests,intervals:power,ratedContinuousConfirmed:ratedConfirmed,aggregateDeviceIDs:aggregateCoverageConfirmed ? project.scenarios.first{$0.id==scenarioID}?.inputs.hvac.map(\.id):nil,aggregateCoverageNote:aggregateCoverageConfirmed ? aggregateNote:nil)
        let config=AnalysisConfiguration(configVersion:original?.configVersion ?? 1,roomID:original?.roomID,deviceID:original?.deviceID,payload:.powerEstimate(c),acceptedAssumptions:original?.acceptedAssumptions ?? [],resources:original?.resources ?? .standard)
        try NativeAnalysisCodec().validateConfiguration(config);return config
    }
    public func applying(currentProject:ProjectDocument?,currentScenarioID:UUID?,currentStore:AnalysisConfigurationStore?) throws -> AnalysisConfigurationStore {
        guard project==currentProject,scenarioID==currentScenarioID,store==currentStore else { throw PreviewConfigurationEditingError.staleDraft }
        var next=store ?? .init(projectID:project.id);next.set(try configuration(),scenarioID:scenarioID);return next
    }
}
public struct HeatBalanceDraft: Identifiable, Sendable {
    public let id=UUID()
    public let project:ProjectDocument
    public let scenarioID:UUID
    public let store:AnalysisConfigurationStore?
    public let original:AnalysisConfiguration?
    public var parameters:[String:PhysicalParameterDraft]
    public var conditionMinuteText:String
    public var conductanceScope:String
    public var internalScope:String
    public var airConditions:String
    public var scopeReference:String
    public var indoorConfirmed:Bool
    public var exclusions:[String:String]
    public var sensitivityRelationship:String
    public var sensitivityExplanation:String
    public var internalSources:[HeatInternalSource]?
    public init(project:ProjectDocument,scenarioID:UUID,store:AnalysisConfigurationStore?) {
        self.project=project;self.scenarioID=scenarioID;self.store=store;original=store?.configuration(scenarioID:scenarioID,kind:.steadyHeatBalance)
        let value:SteadyHeatBalanceConfiguration?
        if case .steadyHeatBalance(let c)=original?.payload { value=c } else { value=nil }
        var adopted:[String:PhysicalParameterDraft]=[:]
        func d<Q>(_ field:String,_ value:PhysicalParameter<Q>?) { adopted[field]=value.map{PhysicalParameterDraft($0)} ?? .init() }
        d("conductance",value?.conductance);d("indoorTemperature",value?.indoorTemperature);d("outdoorTemperature",value?.outdoorTemperature)
        d("outdoorAir",value?.outdoorAir);d("infiltration",value?.infiltration);d("density",value?.density);d("specificHeat",value?.specificHeat)
        d("internalSensibleHeat",value?.internalSensibleHeat);d("solarSensibleHeat",value?.solarSensibleHeat);d("sensibleCoolingCapacity",value?.sensibleCoolingCapacity)
        d("totalCoolingCapacity",value?.totalCoolingCapacity);d("sensibleHeatRatio",value?.sensibleHeatRatio)
        parameters=adopted
        conditionMinuteText=String(value?.conditionMinute ?? 0);conductanceScope=value?.coverage?.conductanceScope ?? "";internalScope=value?.coverage?.internalSensibleScope ?? ""
        airConditions=value?.coverage?.airPropertyConditions ?? "";scopeReference=value?.coverage?.source.reference ?? value?.coverage?.source.note ?? ""
        indoorConfirmed=value?.coverage?.indoorConditionConfirmed ?? false;exclusions=Dictionary(uniqueKeysWithValues:(value?.exclusions ?? []).map{($0.term,$0.reason)})
        sensitivityRelationship=value?.sensitivity?.relationship ?? "unknownDependenceEnvelope";sensitivityExplanation=value?.sensitivity?.source.note ?? ""
        internalSources=value?.internalSources
    }
    public mutating func importInternalSources() throws {
        guard let minute=Int(conditionMinuteText),(0...1439).contains(minute),let scenario=project.scenarios.first(where:{$0.id==scenarioID}) else { throw ParameterDraftError.number }
        func fraction(_ schedule:DailySchedule) -> Ratio { schedule.intervals.first{$0.startMinute<=minute && minute<$0.endMinute}?.fraction ?? .unknown(reason:"代表分钟无明确人员/设备有效比例") }
        var entries=scenario.inputs.usage.occupants.map{HeatInternalSource(entityID:$0.id,description:"人员总显热（未重复计对流/辐射/潜热）",sensible:$0.heat.sensible,effectiveFraction:fraction($0.schedule))}
        entries += scenario.inputs.usage.equipment.map{HeatInternalSource(entityID:$0.id,description:"设备总显热（未重复计对流/辐射/潜热）",sensible:$0.heat.sensible,effectiveFraction:fraction($0.schedule))}
        internalSources=entries
        if entries.allSatisfy({$0.sensible.value != nil && $0.effectiveFraction.value != nil}) {
            let total=entries.reduce(0.0){$0+$1.sensible.value!*$1.effectiveFraction.value!}
            parameters["internalSensibleHeat"] = .init(ThermalPower.known(value:total,source:.init(kind:.user,note:"Explicitly adopted frozen person/equipment total sensible at minute \(minute); each source once")))
        } else { parameters["internalSensibleHeat"] = .init(unknownReason:"冻结清单含未知显热或有效比例，不能补零") }
        internalScope="已明确采用代表分钟\(minute)全部人员/设备清单；潜热排除"
    }
    public func configuration() throws -> AnalysisConfiguration {
        let previous:SteadyHeatBalanceConfiguration?
        if case .steadyHeatBalance(let value)=original?.payload { previous=value } else { previous=nil }
        func p<Q>(_ field:String,original value:PhysicalParameter<Q>?) throws -> PhysicalParameter<Q> {
            guard let draft=parameters[field] else { throw ParameterDraftError.number }
            if let value,draft == PhysicalParameterDraft(value) { return value }
            return try draft.parameter()
        }
        func optional<Q>(_ field:String,original value:PhysicalParameter<Q>?) throws -> PhysicalParameter<Q>? {
            if value == nil,parameters[field] == PhysicalParameterDraft() { return nil }
            return try p(field,original:value)
        }
        let originalExclusions=Dictionary(uniqueKeysWithValues:(previous?.exclusions ?? []).map{($0.term,$0.reason)})
        let explanations=originalExclusions == exclusions ? previous?.exclusions : exclusions.keys.sorted().map{HeatTermExclusion(term:$0,reason:exclusions[$0]!)}
        let excludedTerms=Set(previous?.excludedTerms ?? []) == Set(exclusions.keys) ? previous?.excludedTerms ?? []:exclusions.keys.sorted()
        guard let minute=Int(conditionMinuteText) else { throw ParameterDraftError.number }
        let fields=(ThermalEstimateValidation.heatTerms+["indoorTemperature","outdoorTemperature","density","specificHeat"]).filter{parameters[$0]?.hasUncertainty==true && exclusions[$0]==nil}
        let c=SteadyHeatBalanceConfiguration(conditionMinute:minute,conductance:try p("conductance",original:previous?.conductance),indoorTemperature:try p("indoorTemperature",original:previous?.indoorTemperature),outdoorTemperature:try p("outdoorTemperature",original:previous?.outdoorTemperature),outdoorAir:try p("outdoorAir",original:previous?.outdoorAir),infiltration:try p("infiltration",original:previous?.infiltration),density:try p("density",original:previous?.density),specificHeat:try p("specificHeat",original:previous?.specificHeat),internalSensibleHeat:try p("internalSensibleHeat",original:previous?.internalSensibleHeat),solarSensibleHeat:try p("solarSensibleHeat",original:previous?.solarSensibleHeat),excludedTerms:excludedTerms,sensibleCoolingCapacity:try optional("sensibleCoolingCapacity",original:previous?.sensibleCoolingCapacity),coverage:.init(conductanceScope:conductanceScope,internalSensibleScope:internalScope,airPropertyConditions:airConditions,indoorConditionConfirmed:indoorConfirmed,source:originalCoverageSource),internalSources:internalSources,exclusions:explanations,totalCoolingCapacity:try optional("totalCoolingCapacity",original:previous?.totalCoolingCapacity),sensibleHeatRatio:try optional("sensibleHeatRatio",original:previous?.sensibleHeatRatio),sensitivity:sensitivityConfiguration(fields:fields))
        let config=AnalysisConfiguration(configVersion:original?.configVersion ?? 1,roomID:original?.roomID,deviceID:original?.deviceID,payload:.steadyHeatBalance(c),acceptedAssumptions:original?.acceptedAssumptions ?? [],resources:original?.resources ?? .standard)
        try NativeAnalysisCodec().validateConfiguration(config);return config
    }
    private func sensitivityConfiguration(fields:[String])->HeatSensitivityConfiguration? {
        guard !fields.isEmpty else { return nil }
        if case .steadyHeatBalance(let c)=original?.payload,let sensitivity=c.sensitivity,
           Set(sensitivity.fields)==Set(fields),sensitivityRelationship==sensitivity.relationship,
           sensitivityExplanation==(sensitivity.source.note ?? "") { return sensitivity }
        return .init(fields:fields,relationship:sensitivityRelationship,source:.init(kind:.user,note:sensitivityExplanation))
    }
    private var originalCoverageSource:SourceRecord {
        if case .steadyHeatBalance(let c)=original?.payload,let coverage=c.coverage,scopeReference==(coverage.source.reference ?? coverage.source.note ?? "") { return coverage.source }
        return .init(kind:.user,note:scopeReference)
    }
    public func applying(currentProject:ProjectDocument?,currentScenarioID:UUID?,currentStore:AnalysisConfigurationStore?) throws -> AnalysisConfigurationStore {
        guard project==currentProject,scenarioID==currentScenarioID,store==currentStore else { throw PreviewConfigurationEditingError.staleDraft }
        var next=store ?? .init(projectID:project.id);next.set(try configuration(),scenarioID:scenarioID);return next
    }
}
public struct TariffDraft: Identifiable, Sendable {
    public let id=UUID()
    public let project:ProjectDocument
    public let scenarioID:UUID
    public let parent:LocalAnalysisRequest
    public var currency:String
    public var tariffs:[EstimateIntervalDraft]
    public var displayDigits:Int
    public init(project:ProjectDocument,scenarioID:UUID,parent:LocalAnalysisRequest) {
        self.project=project;self.scenarioID=scenarioID;self.parent=parent
        let cost=project.scenarios.first{$0.id==scenarioID}?.evaluation.cost
        currency=cost?.currency ?? "";tariffs=cost?.tariffs.map{.init(start:$0.startMinute,end:$0.endMinute,parameter:.init($0.rate))} ?? [];displayDigits=2
    }
    public func configuration() throws -> CostEvaluationConfiguration {
        guard case .powerEstimate(let power)=parent.resolvedInput.configuration.payload else { throw ProjectDataError.contract("费用只评价固定功率run") }
        let rates=try tariffs.flatMap{item -> [CostTariffInterval] in let rate:EnergyRate=try item.parameter.parameter(range:.nonnegative);return try item.windows().map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute,rate:rate)}}.sorted{$0.startMinute<$1.startMinute}
        try ThermalEstimateValidation.validateWindows(rates.map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute)},requireNonempty:false)
        return .init(requestedWindows:power.requestedWindows,currency:currency.isEmpty ? nil:currency.uppercased(),tariffs:rates,displayFractionDigits:displayDigits)
    }
    public func applying(currentProject:ProjectDocument?,currentScenarioID:UUID?) throws -> ProjectDocument {
        guard project==currentProject,scenarioID==currentScenarioID else { throw PreviewConfigurationEditingError.staleDraft }
        let configuration=try configuration();var next=project
        guard let index=next.scenarios.firstIndex(where:{$0.id==scenarioID}) else { throw WorkspaceEditingError.noScenario }
        next.scenarios[index].evaluation.cost.currency=configuration.currency
        next.scenarios[index].evaluation.cost.tariffs=configuration.tariffs.map{.init(startMinute:$0.startMinute,endMinute:$0.endMinute,rate:$0.rate)}
        return next
    }
}
