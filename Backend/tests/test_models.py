import json, unittest
from dataclasses import FrozenInstanceError
from copy import deepcopy
from uuid import UUID
from jsonschema import Draft202012Validator, FormatChecker
from fixture_factory import project, structural_cases, semantic_cases, identity
from simunow_worker.models.codec import ProjectCodec, ProjectMigrator, ScenarioSnapshotBuilder, wire_tree
from simunow_worker.models.domain import ProjectDocument, ScenarioInputSnapshot
from simunow_worker.models.primitives import WireModel, FloatValue
from simunow_worker.models.registry import ModelRegistry, Registration, Bounds, default_registry, axis_aligned_queries, GeometryQueries
from simunow_worker.models.schema import generated_schema
from simunow_worker.models.validation import ValidationIssue, ProjectValidator, GeometryRule, InputRequirements
from simunow_worker.models.json_value import parse, render, Number

class ModelsTests(unittest.TestCase):
    def setUp(self): self.registry=default_registry(); self.codec=ProjectCodec(self.registry)
    def decode(self,p): return self.codec.decode(json.dumps(p))
    def test_golden_projects(self):
        schema=Draft202012Validator(generated_schema(ProjectDocument),format_checker=FormatChecker())
        for space in ('office','classroom'):
            p=self.decode(project(space)); schema.validate(json.loads(self.codec.encode(p)))
            self.assertEqual(p,self.codec.decode(self.codec.encode(p)))
            self.assertEqual(ProjectValidator().validate(p,self.registry).issues,())
    def test_structural_rejections(self):
        for name,p in structural_cases().items():
            with self.subTest(name=name),self.assertRaises(Exception): self.decode(p)
    def test_schema_rejects_invalid_contracts(self):
        validator=Draft202012Validator(generated_schema(ProjectDocument),format_checker=FormatChecker())
        for name,p in structural_cases().items():
            with self.subTest(name=name): self.assertTrue(list(validator.iter_errors(p)))
    def test_unfinished_values_and_registry_are_immutable(self):
        from simunow_worker.models.construction import unfinished_project, unfinished_scenario
        p=unfinished_project('Empty'); self.assertEqual(p.geometry.rooms,())
        s=unfinished_scenario('Empty scenario'); self.assertEqual(s.inputs.environment.indoor_humidity.state,'unknown')
        self.assertTrue(ProjectValidator().validate(p,self.registry).passes('projectIntegrity'))
        with self.assertRaises(FrozenInstanceError): self.registry._entries={}
    def test_parser_rejections(self):
        for text in ('{"x":1,"x":2}','{"x":NaN}','{"x":Infinity}','[1,]','"bad\\q"','{} trailing'):
            with self.subTest(text=text),self.assertRaises(Exception): parse(text)
    def test_semantic_errors(self):
        for name,p in semantic_cases().items():
            with self.subTest(name=name):
                report=ProjectValidator().validate(self.decode(p),self.registry)
                self.assertFalse(report.passes('inputPreparation'))
                self.assertTrue(report.issues)
    def test_migration(self):
        draft={'schemaVersion':1,'id':identity(1),'name':'Draft','spaceType':'office','lengthUnit':'m','coordinateSystem':'rightHandedZUp'}
        text=json.dumps(draft); p,notes=ProjectMigrator.migrate(text)
        self.assertEqual(p.id,UUID(identity(1))); self.assertEqual(p.geometry.rooms,()); self.assertEqual(p.scenarios,()); self.assertTrue(notes)
        self.assertTrue(ProjectValidator().validate(p,self.registry).passes('projectIntegrity'))
        self.assertFalse(ProjectValidator().validate(p,self.registry).passes('inputPreparation'))
        self.assertEqual(text,json.dumps(draft))
    def test_nested_snapshot_immutability(self):
        p=self.decode(project()); s=ScenarioSnapshotBuilder.capture(p,p.scenarios[0].id)
        with self.assertRaises(Exception): s.inputs.hvac[0].supply_temperature.value=99
        with self.assertRaises(TypeError): s.inputs.hvac[0].ports[0]=None
        with self.assertRaises(FrozenInstanceError): s.inputs.hvac[0].definition.payload.text='{}'
        edited=p.model_copy(update={'geometry':p.geometry.model_copy(update={'rooms':()})})
        self.assertEqual(len(s.geometry.rooms),1); self.assertEqual(edited.geometry.rooms,())
        self.assertEqual(s,self.codec.decode_snapshot(self.codec.encode_snapshot(s)))
        Draft202012Validator(generated_schema(ScenarioInputSnapshot)).validate(json.loads(self.codec.encode_snapshot(s)))
    def test_unknown_precision_and_version(self):
        raw=project(); raw['scenarios'][0]['inputs']['hvac'][0]['definition']={'kind':'future.device','payloadVersion':99,'payload':{}}
        text=json.dumps(raw).replace('"payload": {}','"payload": {"n":1234567890123456789012345678901234567890,"v":1.23456789012345678901234567890123456789,"a":[null,true]}')
        p=self.codec.decode(text); encoded=self.codec.encode(p)
        self.assertIn('1234567890123456789012345678901234567890',encoded)
        self.assertIn('1.23456789012345678901234567890123456789',encoded)
        self.assertEqual(p,self.codec.decode(encoded))
        report=ProjectValidator().validate(p,self.registry)
        self.assertTrue(report.passes('projectIntegrity')); self.assertFalse(report.passes('inputPreparation'))
    def test_unknown_cost_is_not_zero_or_physics_block(self):
        raw=project(); raw['scenarios'][0]['evaluation']['cost']['quotes']=[{'id':identity(80),'amount':{'state':'unknown','reason':'No quote'}}]
        p=self.decode(raw); self.assertEqual(p.scenarios[0].evaluation.cost.quotes[0].amount.state,'unknown')
        self.assertTrue(ProjectValidator().validate(p,self.registry).passes('inputPreparation'))
    def test_null_normalization(self):
        raw=project(); raw['scenarios'][0]['inputs']['environment']['weather']=None
        p=self.decode(raw); self.assertNotIn('"weather":null',self.codec.encode(p))
    def test_schedule_requirements(self):
        p=self.decode(project()); path='/scenarios/0/inputs/controls/0/schedule/intervals'
        rule=InputRequirements(('/scenarios/0/inputs/environment/weather',),(path,))
        self.assertEqual(rule.validate(p,self.registry),[])
        raw=project(); raw['scenarios'][0]['inputs']['controls'][0]['schedule']['intervals'][0]['startMinute']=100
        self.assertEqual(rule.validate(self.decode(raw),self.registry)[0].code,'schedule_coverage')
    def test_extension_and_rule_without_core_changes(self):
        class Fan(WireModel): label: str
        def rule(payload,path): return [ValidationIssue('test_rule',path+'/label',blocks=('inputPreparation',))] if payload.label=='blocked' else []
        extra=Registration('hvac','test.hvac.fan',1,Fan,rules=(rule,))
        registry=ModelRegistry(self.registry.registrations+(extra,)); codec=ProjectCodec(registry)
        with self.assertRaises(ValueError): ModelRegistry((extra,extra))
        raw=project(); raw['scenarios'][0]['inputs']['hvac'][0]['definition']={'kind':extra.kind,'payloadVersion':1,'payload':{'label':'blocked'}}
        p=codec.decode(json.dumps(raw)); self.assertEqual(p,codec.decode(codec.encode(p)))
        self.assertEqual(len(ProjectValidator().validate(p,registry).issues),1)
        schema=Draft202012Validator(generated_schema(ProjectDocument,registry)); schema.validate(json.loads(codec.encode(p)))
        snapshot=ScenarioSnapshotBuilder.capture(p,p.scenarios[0].id)
        self.assertEqual(snapshot,codec.decode_snapshot(codec.encode_snapshot(snapshot)))
        class ExtraRule:
            def validate(self,project,registry): return [ValidationIssue('extra_rule','/name')]
        self.assertEqual(ProjectValidator((ExtraRule(),)).validate(p,registry).issues[0].code,'extra_rule')
    def test_geometry_registration(self):
        class WideRoom(WireModel): width: FloatValue
        bounds=lambda p: Bounds((0.,0.,0.),(p.width,4.,3.))
        extra=Registration('room','test.geometry.wide',1,WideRoom,bounds,geometry=axis_aligned_queries(bounds))
        registry=ModelRegistry(self.registry.registrations+(extra,))
        raw=project(); raw['geometry']['rooms'][0]['shape']={'kind':extra.kind,'payloadVersion':1,'payload':{'width':10}}
        p=ProjectCodec(registry).decode(json.dumps(raw)); self.assertEqual(registry.query_bounds('room',p.geometry.rooms[0].shape).size[0],10)
        self.assertEqual(GeometryRule().validate(p,registry),[])
        limited=GeometryQueries(lambda model,point,tolerance: point[0]<5,extra.geometry.surface_extent,extra.geometry.intersects)
        registration=Registration('room',extra.kind,1,WideRoom,bounds,geometry=limited)
        custom=ModelRegistry(self.registry.registrations+(registration,))
        raw['scenarios'][0]['inputs']['usage']['seats'][0]['samples'][0]['position']['x']=5.5
        p=ProjectCodec(custom).decode(json.dumps(raw))
        self.assertTrue(any(i.code=='point_bounds' for i in GeometryRule().validate(p,custom)))

if __name__=='__main__': unittest.main()
