#!/usr/bin/env python3
"""Independent native contract schemas; embed generated snapshot defs and check drift."""
import argparse, copy, json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'Packages/SimuKit/Sources/SimuCore'
snapshot = json.loads((ROOT / 'Protocols/Schemas/scenario-input-snapshot.schema.json').read_text())
defs = dict(snapshot['$defs'])
defs['ScenarioInputSnapshot'] = {k:v for k,v in snapshot.items() if k not in ('$defs','$id','$schema','title')}
def ref(name): return {'$ref': '#/$defs/'+name}
def obj(props, required=None): return {'type':'object','properties':props,'required': list(props) if required is None else required,'additionalProperties':False}
def enum(values): return {'type':'string','enum':values}
primitive = {'String': {'type':'string'}, 'Double': {'type':'number'}, 'Int': {'type':'integer'}, 'UInt32': {'type':'integer','minimum':0,'maximum':4294967295}, 'Bool': {'type':'boolean'}, 'UUID':{'type':'string','format':'uuid'}}
quantities = {'ElectricalPower':defs['AnalysisPowerInterval']['power'] if 'AnalysisPowerInterval' in defs else defs['AirPort']['properties']['area']}
# Units retain the existing source/uncertainty and known/unknown union.
units = {'ElectricalPower':'W','ThermalPower':'W','Temperature':'degC','VolumeFlow':'m3/s','Density':'kg/m3','HeatConductance':'W/K','SpecificHeat':'J/(kg.K)'}
for name, unit in units.items():
    known = obj({'state':{'const':'known'},'value':{'type':'number'},'unit':{'const':unit},'source':ref('SourceRecord'),'uncertainty':ref('UncertaintyBounds')}, ['state','value','unit','source'])
    defs['Native'+name] = {'anyOf':[known, ref('Unknown')]}
    quantities[name] = ref('Native'+name)
def ts(t):
    if t.endswith('?'): return {'anyOf':[ts(t[:-1]),{'type':'null'}]}
    if t.startswith('[') and t.endswith(']'): return {'type':'array','items':ts(t[1:-1])}
    return copy.deepcopy(primitive.get(t, quantities.get(t, ref(t))))
texts = '\n'.join(p.read_text() for p in (CORE/'Analysis').glob('*.swift'))
for name, protocols, body in re.findall(r'public struct (\w+):([^\{]+)\{(.*?)(?=\npublic (?:struct|enum|typealias)|\Z)', texts, re.S):
    if 'Codable' not in protocols: continue
    props,required = {},[]
    for field,t in re.findall(r'^    public (?:let|var) (\w+): ([\w\[\]?]+)\s*$',body,re.M):
        props[field] = ts(t)
        if not t.endswith('?'): required.append(field)
    if props: defs[name] = obj(props,required)
for name, vals in {
    'AnalysisKind':['airflowPreview','powerEstimate','steadyHeatBalance'],
    'AnalysisResultBasis':['rulePreview','simplifiedEstimate'],
    'AnalysisTimeBasis':['fixed24HourReference'],
    'ElectricalPowerBasis':['measuredAverage','declaredScenario','ratedContinuous'],
    'AnalysisCapability':['roomView','airflowPreview','powerEstimate','steadyHeatBalance'],
    'AnalysisIssueSeverity':['warning','blocker'],
    'AnalysisChecksState':['passed','failed','notEvaluated'],
    'PreviewPathTermination':['hit','escaped','weak','lengthLimit','stepLimit'],
    'PreviewRelationState':['intersectsAssumedPath','occluded','outsideAssumedPath','notEvaluated'],
    'SensibleCapacityScreen':['sufficientForDeclaredSensibleCase','insufficientForDeclaredSensibleCase','cannotEvaluate'],
    'LocalAnalysisStage':['accepted','validating','running','progress','checking','completed','failed','cancelled'],
}.items(): defs[name] = enum(vals)
for name,suffix in [('AnalysisConfigurationPayload','Configuration'),('LocalAnalysisPayload','Payload')]:
    names = [('airflowPreview','AirflowPreview'),('powerEstimate','PowerEstimate'),('steadyHeatBalance','SteadyHeatBalance')]
    defs[name] = {'anyOf':[obj({'kind':{'const':kind},'value':ref(prefix+suffix)}) for kind,prefix in names]}
def c(name, field, **rule): defs[name]['properties'][field].update(rule)
for name,field in [('AnalysisConfiguration','configVersion'),('AnalysisConfigurationStore','storeVersion'),('LocalAnalysisRequest','requestVersion'),('LocalAnalysisResult','resultVersion'),('LocalAnalysisEvent','eventVersion'),('AnalysisArtifactManifest','artifactVersion'),('AnalysisArtifactManifest','requestVersion'),('AnalysisArtifactManifest','resultVersion')]: c(name,field,const=1)
c('AnalysisMethod','methodVersion',const=1)
c('AnalysisArtifactManifest','owner',const='com.simunow.native-analysis')
c('AirflowPreviewPayload','strengthUnit',const='1')
c('LocalAnalysisRequest','hashFormat',const='simunow.native.canonical.v1')
defs['RunIdentity'] = obj({'runID':copy.deepcopy(primitive['UUID']),'scenarioID':copy.deepcopy(primitive['UUID']),'inputHash':copy.deepcopy(primitive['String'])})
for name,field in [('RunIdentity','inputHash'),('LocalAnalysisRequest','snapshotHash'),('LocalAnalysisRequest','computationHash'),('AnalysisArtifactFile','sha256')]: c(name,field,pattern='^[a-f0-9]{64}$')
for name,field in [('AnalysisMissingReason','code'),('AnalysisMissingReason','reason'),('AnalysisAssumption','id'),('AnalysisAssumption','meaning')]: c(name,field,minLength=1)
for name,field in [('AnalysisAssumption','version'),('AirflowPreviewConfiguration','profileVersion'),('AirflowPreviewPayload','profileVersion')]: c(name,field,minimum=1)
for field,lo,hi in [('maximumPaths',1,64),('maximumSegments',1,128),('maximumObstacles',0,128),('maximumTargets',0,512)]: c('AnalysisResourceLimits',field,minimum=lo,maximum=hi)
for name in ['AnalysisTimeWindow','AnalysisPowerInterval','PowerEstimateSegment']:
    c(name,'startMinute',minimum=0,maximum=1439); c(name,'endMinute',minimum=1,maximum=1440)
c('AirflowPreviewConfiguration','baseRadiusMeters',exclusiveMinimum=0)
c('AirflowPreviewConfiguration','halfAngleDegrees',minimum=1,maximum=45)
c('AirflowPreviewConfiguration','pathCount',minimum=1,maximum=64)
c('AirflowPreviewConfiguration','maximumSegments',minimum=1,maximum=128)
c('AirflowPreviewConfiguration','minimumStrength',minimum=0,maximum=1)
c('SteadyHeatBalanceConfiguration','conditionMinute',minimum=0,maximum=1439)
c('LocalAnalysisResult','elapsedSeconds',minimum=0)
c('LocalAnalysisEvent','sequence',minimum=0,maximum=23)
c('PreviewPathPoint','strength',minimum=0,maximum=1)
c('PreviewPath','points',maxItems=129)
c('AirflowPreviewPayload','paths',maxItems=64)
c('AirflowPreviewPayload','relations',maxItems=512)
c('AnalysisArtifactFile','relativePath',pattern='^(input\\.json|result\\.json|evaluations/[a-f0-9]{64}\\.json)$')
c('AnalysisArtifactFile','byteCount',minimum=0)
# Cross-field kind pairing, without unsupported oneOf/external references.
for target,payloadpath in [('LocalAnalysisRequest',['resolvedInput','configuration','payload']),('LocalAnalysisResult',['payload'])]:
    branches=[]
    for kind in ['airflowPreview','powerEstimate','steadyHeatBalance']:
        condition={'properties':{'method':{'properties':{'kind':{'const':kind}}}}}
        leaf={'properties':{'kind':{'const':kind}}}
        for key in reversed(payloadpath): leaf={'properties':{key:leaf}}
        if target == 'LocalAnalysisResult': leaf['properties']['basis']={'const':'rulePreview' if kind=='airflowPreview' else 'simplifiedEstimate'}
        branches.append({'if':condition,'then':leaf})
    defs[target]['allOf']=branches
outputs={'local-analysis-request':'LocalAnalysisRequest','local-analysis-event':'LocalAnalysisEvent','local-analysis-result':'LocalAnalysisResult','analysis-artifact-manifest':'AnalysisArtifactManifest','analysis-configuration':'AnalysisConfigurationStore'}
def verify_refs(node):
    if isinstance(node,dict):
        if '$ref' in node and node['$ref'].startswith('#/$defs/') and node['$ref'][8:] not in defs: raise SystemExit('Undefined native schema ref: '+node['$ref'])
        for child in node.values(): verify_refs(child)
    elif isinstance(node,list):
        for child in node: verify_refs(child)
verify_refs(defs)
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
for filename,target in outputs.items():
    schema={'$schema':'https://json-schema.org/draft/2020-12/schema','$id':'https://simunow.local/schemas/'+filename+'.schema.json','title':target,'$defs':defs,'$ref':'#/$defs/'+target}
    data=json.dumps(schema,ensure_ascii=False,sort_keys=True,indent=2)+'\n'
    for folder in [ROOT/'Protocols/Schemas',CORE/'Resources']:
        path=folder/(filename+'.schema.json')
        if args.check:
            if not path.exists() or path.read_text()!=data: raise SystemExit('Native schema drift: '+str(path))
        else: path.write_text(data)
print('Native schemas: '+('no drift' if args.check else 'generated'))
