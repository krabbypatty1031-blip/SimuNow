"""Checked-in Draft 2020-12 contracts, built from wire models + registrations."""
import json
from copy import deepcopy
from pathlib import Path
from .domain import ProjectDocument, ScenarioInputSnapshot
from .registry import default_registry


def generated_schema(model, registry=None):
    registry = registry or default_registry()
    schema = model.model_json_schema(by_alias=True)
    schema['$schema'] = 'https://json-schema.org/draft/2020-12/schema'
    schema['$id'] = 'urn:simunow:p2:' + model.__name__ + ':2'
    definitions = schema.setdefault('$defs', {})
    def merge(name,definition):
        if name in definitions and definitions[name] != definition:
            raise ValueError('schema_definition_collision: '+name)
        definitions[name] = definition
    conditions = []
    for registration in registry.registrations:
        payload = registration.model.model_json_schema(by_alias=True)
        for name,definition in payload.pop('$defs', {}).items(): merge(name,definition)
        merge(registration.model.__name__,payload)
        conditions.append({
            'if': {'properties': {'kind': {'const': registration.kind},
                                  'payloadVersion': {'const': registration.version}},
                   'required': ['kind','payloadVersion']},
            'then': {'properties': {'payload': {'$ref': '#/$defs/' + registration.model.__name__}}},
        })
    definitions['ExtensionRecord']['allOf'] = conditions
    definitions['ExtensionRecord']['properties']['kind']['pattern'] = '^[a-zA-Z][a-zA-Z0-9_.-]+$'
    definitions['ExtensionRecord']['properties']['payloadVersion']['minimum'] = 1
    for model_name,field,category in [('Room','shape','room'),('Obstacle','shape','obstacle'),('HVACDevice','definition','hvac')]:
        record_schema = deepcopy(definitions['ExtensionRecord'])
        for registration,condition in zip(registry.registrations,record_schema['allOf']):
            if registration.category != category: condition['then'] = False
        name = category.title() + 'Record'
        definitions[name] = record_schema
        definitions[model_name]['properties'][field] = {'$ref':'#/$defs/'+name}
    return schema


def schema_text(model):
    return json.dumps(generated_schema(model), ensure_ascii=False, indent=2, sort_keys=True) + '\n'


def write_or_check(root, check=False):
    for model,name in [(ProjectDocument,'project-document.schema.json'),
                       (ScenarioInputSnapshot,'scenario-input-snapshot.schema.json')]:
        content = schema_text(model)
        for directory in [root/'Protocols/Schemas',root/'Packages/SimuKit/Sources/SimuCore/Resources']:
            path = directory/name
            if check:
                if not path.exists() or path.read_text() != content:
                    raise ValueError('schema_drift: ' + str(path.relative_to(root)))
            else: path.write_text(content)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    write_or_check(Path(__file__).resolve().parents[4], args.check)
