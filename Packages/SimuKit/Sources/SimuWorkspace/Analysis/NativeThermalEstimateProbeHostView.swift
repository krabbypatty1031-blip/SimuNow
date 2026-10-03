#if DEBUG
import SwiftUI
import UniformTypeIdentifiers
import SimuCore
import SimuSimulation

public enum N4ProbeMode:String,CaseIterable,Identifiable { case saveFailure="附件路径冲突保存失败",sourced="公开来源情景",ranges="有来源范围情景",missing="功率/太阳未知",subset="明确排除太阳子集",unknownSHR="总能力已知SHR未知",coolingOnly="只有制冷量无电功率";public var id:String{rawValue} }
public enum N4SyntheticFixture {
    public static let powerSource=SourceRecord(kind:.manufacturer,reference:"https://library.mitsubishielectric.co.uk/pdf/download_full/4788",note:"February 2026 p2 MUZ-AY25VG2 SYSTEM POWER INPUT cooling nominal 0.60 kW; adopted reference 08:00–10:00 rated continuous, not a measurement")
    public static let rateSource=SourceRecord(kind:.preset,reference:"https://particulier.edf.fr/content/dam/2-Actifs/Documents/Offres/Grille_prix_Tarif_Bleu.pdf",note:"Effective 2026-08-01; France residential EDF Tarif Bleu Option Base 6kVA: 20.01 euro cents TTC/kWh; subscription/equipment/installation excluded; no extra tax added")
    private static let synthetic=SourceRecord(kind:.user,note:"Synthetic analytical heat case; constants are test inputs, not production defaults or room measurements")
    public static func document(mode:N4ProbeMode = .sourced)throws->SimuNowDocument {
        var project=try N3SyntheticFixture.make();project.name="N4 透明估算验证"
        var configs=AnalysisConfigurationStore(projectID:project.id)
        for index in project.scenarios.indices {
            let id=project.scenarios[index].id
            let power:ElectricalPower
            if mode == .missing || mode == .coolingOnly { power = .unknown(reason:"No electrical reading; cooling capacity cannot replace it") }
            else if mode == .ranges { power = .known(value:600,source:.init(kind:.user,note:"Explicit synthetic scenario 400…800W endpoints based on 600W source nominal; range is not manufacturer calibration"),uncertainty:.init(lower:400,upper:800,meaning:"Declared endpoint scenarios, no probability")) }
            else {power = .known(value:600,source:powerSource)}
            let split=SingleSplit(coolingCapacity:.known(value:2500,source:powerSource),electricalPower:power,cop:.unknown(reason:"Not used in this method"))
            project.scenarios[index].inputs.hvac[0].definition=try .init(split)
            project.scenarios[index].evaluation.cost = .init(currency:"EUR",tariffs:[.init(startMinute:480,endMinute:600,rate:.known(value:0.2001,source:rateSource))])
            if mode != .coolingOnly {
                let powerConfig=PowerEstimateConfiguration(requestedWindows:[.init(startMinute:480,endMinute:600)],intervals:[.init(startMinute:480,endMinute:600,power:power,basis:mode == .ranges ? .declaredScenario:.ratedContinuous)],ratedContinuousConfirmed:true)
                configs.set(.init(payload:.powerEstimate(powerConfig)),scenarioID:id)
            }
            func q<Q>(_ value:Double,_ bounds:UncertaintyBounds?=nil)->PhysicalParameter<Q>{.known(value:value,source:synthetic,uncertainty:bounds)}
            let solar:ThermalPower=mode == .missing || mode == .subset ? .unknown(reason:"Solar not measured"):q(0)
            let excluded=mode == .subset ? ["solarSensibleHeat"]:[]
            let heat=SteadyHeatBalanceConfiguration(conditionMinute:540,conductance:q(100,mode == .ranges ? .init(lower:80,upper:120,meaning:"Declared synthetic UA endpoints"):nil),indoorTemperature:q(20),outdoorTemperature:q(30,mode == .ranges ? .init(lower:28,upper:32,meaning:"Declared synthetic outdoor condition endpoints"):nil),outdoorAir:q(0),infiltration:q(0),density:q(1.2),specificHeat:q(1000),internalSensibleHeat:q(0),solarSensibleHeat:solar,excludedTerms:excluded,sensibleCoolingCapacity:mode == .unknownSHR ? nil:q(1500),coverage:.init(conductanceScope:"Synthetic explicit 100 W/K aggregate; all room envelope terms within this test case",internalSensibleScope:"Explicit aggregate 0W test case; no real occupancy inference",airPropertyConditions:"Synthetic 20…32°C case; 1.2kg/m³ and 1000J/(kg.K) are adopted test inputs",indoorConditionConfirmed:true,source:synthetic),exclusions:excluded.map{.init(term:$0,reason:"User explicitly excludes unknown solar; declared subset cannot pass full capacity screening")},totalCoolingCapacity:mode == .unknownSHR ? q(2500):nil,sensibleHeatRatio:mode == .unknownSHR ? .unknown(reason:"No sensible heat ratio source; cannot assume 1"):nil,sensitivity:mode == .ranges ? .init(fields:["conductance","outdoorTemperature"],relationship:"unknownDependenceEnvelope",source:synthetic):nil)
            configs.set(.init(payload:.steadyHeatBalance(heat)),scenarioID:id)
        }
        let entries:[String:ProjectPackageEntry] = mode == .saveFailure ? ["runs":.file(Data("Deliberate synthetic path collision; original attachment must be preserved".utf8))]:[:]
        return try SimuNowDocument(project:project,metadata:.init(baselineScenarioID:project.scenarios[0].id),preservedEntries:entries).updatingAnalysisConfiguration(configs)
    }
}
@MainActor public struct NativeThermalEstimateProbeHostView:View {
    @State private var document:SimuNowDocument
    @State private var mode:N4ProbeMode = .sourced
    @State private var exporting=false
    @State private var importing=false
    @State private var error:String?
    private let client: LocalAnalysisClient
    public init(localAnalysisClient: LocalAnalysisClient){client=localAnalysisClient;_document=State(initialValue:(try? N4SyntheticFixture.document()) ?? .unfinished())}
    public var body:some View { VStack(spacing:4){
        Text("N4 synthetic 几何/显热；功率/电价有公开来源 · 真生产Swift算法，无预制结果").font(.caption)
        ViewThatFits(in:.horizontal){HStack{controls};VStack{controls}}
        if let error {Text(error).font(.caption).foregroundStyle(.orange)}
        WorkspaceDocumentView(document:$document,localAnalysisClient:client)
    }.fileExporter(isPresented:$exporting,document:document,contentType:.simuNowProject,defaultFilename:"N4-synthetic"){if case .failure(let error)=$0{self.error=error.localizedDescription}}
    .fileImporter(isPresented:$importing,allowedContentTypes:[.simuNowProject]){result in if case .success(let url)=result{Task{do{document=try await ProjectPackageIO().readPackage(from:url)}catch{self.error=error.localizedDescription}}}else if case .failure(let error)=result{self.error=error.localizedDescription}}
    #if os(macOS)
    .frame(minWidth:1100,minHeight:800)
    #endif
    }
    @ViewBuilder private var controls:some View {
        Picker("输入反例",selection:$mode){ForEach(N4ProbeMode.allCases){Text($0.rawValue).tag($0)}}.onChange(of:mode){_,mode in do{document=try N4SyntheticFixture.document(mode:mode)}catch{self.error=error.localizedDescription}}
        Button("导出项目包"){exporting=true};Button("重新打开项目包"){importing=true}
    }
}
#endif
