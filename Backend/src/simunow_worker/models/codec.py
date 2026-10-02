"""The public wire entrypoint. Strict contracts before typed construction."""
from uuid import UUID
import re
from pydantic import BaseModel
from .domain import ProjectDocument, ScenarioInputSnapshot
from .primitives import integer
from .json_value import parse, render, Number, FrozenJSON
from .registry import native, default_registry


def wire_tree(value):
    if isinstance(value, BaseModel):
        return {field.alias or name: wire_tree(getattr(value,name))
                for name,field in type(value).model_fields.items() if getattr(value,name) is not None}
    if isinstance(value, UUID): return str(value).upper()
    if isinstance(value, FrozenJSON): return value.tree()
    if isinstance(value, tuple): return [wire_tree(v) for v in value]
    return value


class ProjectCodec:
    def __init__(self, registry=None): self.registry = registry or default_registry()

    def _validate_payloads(self, geometry, inputs):
        records = [('room',r.shape) for r in geometry.rooms] + [('obstacle',o.shape) for o in geometry.obstacles]
        records += [('hvac',h.definition) for s in inputs for h in s.hvac]
        for category,record in records:
            if record.payload_version < 1 or not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_.-]+",record.kind):
                raise ValueError("invalid extension key")
            if self.registry.lookup(category,record) is None and any(r.kind == record.kind and r.version == record.payload_version for r in self.registry.registrations):
                raise ValueError('wrong extension category')
            self.registry.resolve(category,record)  # Known-invalid never becomes unknown.

    def decode(self, text):
        raw = parse(text)
        version = raw.get('schemaVersion') if isinstance(raw,dict) else None
        if not isinstance(version,Number) or integer(version) != 2:
            raise ValueError('unsupported_version')
        data = native(raw); data["schemaVersion"] = integer(version)
        project = ProjectDocument.model_validate(data)
        self._validate_payloads(project.geometry,tuple(s.inputs for s in project.scenarios))
        return project

    def encode(self, project):
        text = render(wire_tree(project))
        self.decode(text)
        return text

    def decode_snapshot(self, text):
        raw = parse(text); data = native(raw); data["schemaVersion"] = integer(raw["schemaVersion"])
        result = ScenarioInputSnapshot.model_validate(data)
        self._validate_payloads(result.geometry,(result.inputs,))
        return result

    def encode_snapshot(self, snapshot):
        text = render(wire_tree(snapshot)); self.decode_snapshot(text); return text


class ProjectMigrator:
    @staticmethod
    def migrate(text):
        raw = parse(text)
        expected = {'schemaVersion','id','name','spaceType','lengthUnit','coordinateSystem'}
        if not isinstance(raw,dict) or set(raw) != expected or integer(raw['schemaVersion']) != 1 or raw['lengthUnit'] != 'm' or raw['coordinateSystem'] != 'rightHandedZUp':
            raise ValueError('invalid v1 draft')
        project = ProjectDocument.model_validate({**native(raw),'schemaVersion':2,'geometry':{'rooms':(),'obstacles':()},'scenarios':()})
        return project, ('Geometry and scenario inputs remain incomplete; no physical defaults were invented.',)


class ScenarioSnapshotBuilder:
    @staticmethod
    def capture(project, scenario_id):
        if project.schema_version != 2 or project.length_unit != 'm' or project.coordinate_system != 'rightHandedZUp':
            raise ValueError('invalid project metadata')
        scenario = next((s for s in project.scenarios if s.id == scenario_id),None)
        if scenario is None or sum(s.id == scenario_id for s in project.scenarios) != 1: raise ValueError('missing_or_ambiguous_scenario')
        return ScenarioInputSnapshot(schemaVersion=2,projectID=project.id,scenarioID=scenario.id,
                                     lengthUnit=project.length_unit,coordinateSystem=project.coordinate_system,
                                     geometry=project.geometry,inputs=scenario.inputs,evaluation=scenario.evaluation)
