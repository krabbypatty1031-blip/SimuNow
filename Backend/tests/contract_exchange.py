"""Real Python/Swift exchange. Artifacts live outside the repository."""
import json, sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
from fixture_factory import project, semantic_cases, structural_cases
from simunow_worker.models.codec import ProjectCodec, ScenarioSnapshotBuilder
from simunow_worker.models.domain import ProjectDocument, ScenarioInputSnapshot
from simunow_worker.models.registry import default_registry
from simunow_worker.models.validation import ProjectValidator
from simunow_worker.models.schema import generated_schema
from simunow_worker.models.json_value import parse
from simunow_worker.models.hashing import snapshot_hash

codec=ProjectCodec(); directory=Path(sys.argv[2]); directory.mkdir(parents=True,exist_ok=True)
if sys.argv[1]=='prepare':
    for space in ('office','classroom'):
        p=codec.decode(json.dumps(project(space)))
        (directory/(space+'.python.json')).write_text(codec.encode(p))
        snapshot=ScenarioSnapshotBuilder.capture(p,p.scenarios[0].id)
        (directory/(space+'.python-snapshot.json')).write_text(codec.encode_snapshot(snapshot))
        (directory/(space+'.snapshot-hash.txt')).write_text(snapshot_hash(snapshot))
    for name,raw in semantic_cases().items():
        p=codec.decode(json.dumps(raw)); (directory/(name+'.case.json')).write_text(codec.encode(p))
        (directory/(name+'.expected.json')).write_text(json.dumps(ProjectValidator().validate(p,default_registry()).keys()))
    for name,raw in structural_cases().items(): (directory/(name+'.invalid.json')).write_text(json.dumps(raw))
    for name,text in [('duplicate-key','{"schemaVersion":2,"schemaVersion":2}'),('nan','{"value":NaN}'),('truncated','{"schemaVersion":2'),('infinity','{"value":Infinity}')]:
        (directory/(name+'.invalid.json')).write_text(text)
elif sys.argv[1]=='return':
    for path in directory.glob('*.swift.json'):
        project=codec.decode(path.read_text())
        (directory/path.name.replace('.swift.','.python-return.')).write_text(codec.encode(project))
        snapshot=ScenarioSnapshotBuilder.capture(project,project.scenarios[0].id)
        (directory/path.name.replace('.swift.','.python-return-snapshot.')).write_text(codec.encode_snapshot(snapshot))
elif sys.argv[1]=='verify':
    outputs=list(directory.glob('*.swift.json'))
    if len(outputs)!=2: raise SystemExit('Missing Swift exchange outputs')
    for path in outputs:
        p=codec.decode(path.read_text()); original=codec.decode(path.with_name(path.name.replace('.swift.','.python.')).read_text())
        assert p==original, path
        Draft202012Validator(generated_schema(ProjectDocument),format_checker=FormatChecker()).validate(json.loads(path.read_text()))
        snapshot_path=path.with_name(path.name.replace('.swift.','.swift-snapshot.'))
        snapshot=codec.decode_snapshot(snapshot_path.read_text())
        assert snapshot==ScenarioSnapshotBuilder.capture(p,p.scenarios[0].id)
        Draft202012Validator(generated_schema(ScenarioInputSnapshot),format_checker=FormatChecker()).validate(json.loads(snapshot_path.read_text()))
    for path in directory.glob('*.swift-case.json'):
        original=codec.decode(path.with_name(path.name.replace('.swift-case.','.case.')).read_text())
        assert codec.decode(path.read_text())==original, path
    if len(list(directory.glob('*.swift-case.json')))!=len(semantic_cases()): raise SystemExit('Missing semantic exchange outputs')
    from schema_registry import validator as schema_validator
    v_input=schema_validator('run-input.schema.json')
    runinputs=list(directory.glob('*.swift-runinput.json'))
    if len(runinputs)!=2: raise SystemExit('Missing Swift run-input outputs')
    for path in runinputs:
        raw=json.loads(path.read_text()); v_input.validate(raw)
        snapshot=codec.decode_snapshot(json.dumps(raw['snapshot']))
        assert snapshot_hash(snapshot)==raw['inputHash'].lower(), path
        assert str(snapshot.scenario_id).upper()==raw['scenarioID'].upper(), path
    print(f'Cross-language exchange passed: {len(outputs)} projects, snapshots, {len(semantic_cases())} error/compatibility cases, {len(runinputs)} run-inputs.')
else: raise SystemExit('prepare or verify required')
