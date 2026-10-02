#!/usr/bin/env python3
"""Validate real Swift wire output with independent Draft 2020-12 validation."""
import copy, json, sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
root=Path(__file__).resolve().parents[1]
folder=Path(sys.argv[1])
files=sorted(folder.glob('*.json'))
if len(files)!=15: raise SystemExit(f'Expected 15 actual Swift records, found {len(files)}')
map_={'request':'local-analysis-request','result':'local-analysis-result','event':'local-analysis-event','manifest':'analysis-artifact-manifest','configuration':'analysis-configuration'}
validators={}
for tag,name in map_.items():
    schema=json.loads((root/'Protocols/Schemas'/f'{name}.schema.json').read_text())
    Draft202012Validator.check_schema(schema)
    validators[tag]=Draft202012Validator(schema,format_checker=FormatChecker())
for path in files:
    tag=path.stem.rsplit('-',1)[1]
    validators[tag].validate(json.loads(path.read_text()))
# Mutation checks independent from Codable: version, pairing, unit, required, unknown, UUID.
request=json.loads((folder/'airflowPreview-request.json').read_text())
mutations=[]
a=copy.deepcopy(request);a['requestVersion']=2;mutations.append(a)
a=copy.deepcopy(request);a['method']['kind']='powerEstimate';mutations.append(a)
a=copy.deepcopy(request);a['identity']['runID']='not-a-uuid';mutations.append(a)
a=copy.deepcopy(request);a['futureField']=True;mutations.append(a)
a=copy.deepcopy(request);del a['snapshotHash'];mutations.append(a)
for node in mutations:
    if validators['request'].is_valid(node): raise SystemExit('Independent schema accepted invalid request')
config=json.loads((folder/'powerEstimate-configuration.json').read_text())
config['entries'][0]['configuration']['payload']['value']['intervals'][0]['power']['unit']='m/s'
if validators['configuration'].is_valid(config): raise SystemExit('Electrical power wrong unit accepted')
# Shared-schema nodes must not contaminate unrelated primitive fields.
schema=validators['request'].schema
assert schema['$defs']['AnalysisIssue']['properties']['message']=={'type':'string'}
assert schema['$defs']['AnalysisArtifactManifest']['properties']['owner']['const']=='com.simunow.native-analysis'
assert 'const' not in schema['$defs']['PreviewPath']['properties']['id']
print('Native contracts: 15 real Swift records + 6 rejection mutations + independent field assertions passed.')
