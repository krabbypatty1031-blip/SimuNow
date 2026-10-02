"""Composable pure input rules. Input checks never claim solver convergence."""
from dataclasses import dataclass, replace
from datetime import date
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import math, re
from .codec import wire_tree
from .json_value import Number
from .registry import native

TOLERANCE = 1e-6
BOTH = ('projectIntegrity','inputPreparation')

@dataclass(frozen=True)
class ValidationIssue:
    code: str
    path: str
    entity_id: str | None = None
    severity: str = 'error'
    blocks: tuple = BOTH
    message: str = 'Correct the input at this field.'

@dataclass(frozen=True)
class ValidationReport:
    issues: tuple
    def passes(self,target): return not any(target in i.blocks for i in self.issues)
    def keys(self): return sorted((i.code,i.path,i.blocks) for i in self.issues)


def numeric(value):
    if isinstance(value,Number): return float(value.token)
    return float(value) if isinstance(value,(int,float)) and not isinstance(value,bool) else None

def parameter(value):
    return numeric(value.get('value')) if isinstance(value,dict) and value.get('state') == 'known' else None

def walk(value,path=''):
    yield path,value
    if isinstance(value,dict):
        for key,item in value.items():
            if key == 'payload': continue
            yield from walk(item,path+'/'+key.replace('~','~0').replace('/','~1'))
    elif isinstance(value,(list,tuple)):
        for index,item in enumerate(value): yield from walk(item,path+'/'+str(index))


def record_category(path):
    return 'hvac' if path.endswith('/definition') else 'obstacle' if path.startswith('/geometry/obstacles/') else 'room'

class ParameterRule:
    def validate(self,project,registry):
        issues=[]
        def scan(tree,start=''):
            for path,node in walk(tree,start):
                if not isinstance(node,dict): continue
                entity=node.get('id')
                if set(('kind','payloadVersion','payload')).issubset(node):
                    from .domain import ExtensionRecord
                    record=ExtensionRecord.model_validate(native(node))
                    item=registry.lookup(record_category(path),record)
                    if item is None:
                        issues.append(ValidationIssue('unsupported_type',path,blocks=('inputPreparation',)))
                    else:
                        payload=registry.resolve(item.category,record)
                        scan(wire_tree(payload),path+'/payload')
                        for rule in item.rules: issues.extend(rule(payload,path+'/payload'))
                state=node.get('state')
                if state == 'unknown':
                    if not node['reason'].strip(): issues.append(ValidationIssue('unknown_reason',path+'/reason'))
                    if '/evaluation/' not in path: issues.append(ValidationIssue('missing_parameter',path,blocks=('inputPreparation',)))
                elif state == 'known':
                    value=parameter(node); unit=node['unit']; name=path.split('/')[-1]
                    invalid = value is None or not math.isfinite(value)
                    if unit in ('m','m2','W','m3/s','m/s','Pa','met','clo','kg/m3','W/(m2.K)','currency','currency/kWh'):
                        invalid |= value < 0
                    if name in ('width','depth','height','area','density','activity','cop'): invalid |= value <= 0
                    if name in ('fraction','convectiveFraction','shgc','shadingFactor','openFraction','outdoorHumidity','indoorHumidity'):
                        invalid |= not 0 <= value <= 1
                    if unit == 'degC': invalid |= value < -273.15
                    if name == 'northAngle': invalid |= not 0 <= value < 360
                    if invalid: issues.append(ValidationIssue('parameter_range',path))
                    source=node['source']; kind=source['kind']
                    if kind in ('manufacturer','measured','preset') and not source.get('reference','').strip() or kind=='assumed' and not source.get('note','').strip():
                        issues.append(ValidationIssue('source_required',path+'/source',blocks=() if '/evaluation/' in path else ('inputPreparation',)))
                    bounds=node.get('uncertainty')
                    if bounds and (not bounds['meaning'].strip() or not numeric(bounds['lower']) <= value <= numeric(bounds['upper'])):
                        issues.append(ValidationIssue('uncertainty_bounds',path+'/uncertainty'))
                if 'startMinute' in node:
                    a=numeric(node['startMinute']); b=numeric(node['endMinute'])
                    if not 0 <= a < b <= 1440: issues.append(ValidationIssue('schedule_interval',path))
                for key in ('intervals','tariffs'):
                    items=node.get(key)
                    if items is not None:
                        end=0
                        for i,item in enumerate(items):
                            start=numeric(item['startMinute'])
                            if start < end: issues.append(ValidationIssue('schedule_overlap',path+'/'+key+'/'+str(i)))
                            end=numeric(item['endMinute'])
        scan(wire_tree(project)); return issues

class IdentityRule:
    def validate(self,project,registry):
        issues=[]; tree=wire_tree(project)
        def identities(tree,path,seen):
            for pointer,node in walk(tree,path):
                if isinstance(node,dict) and 'id' in node:
                    identity=node['id'].upper()
                    if identity in seen: issues.append(ValidationIssue('duplicate_id',pointer+'/id',identity))
                    seen.add(identity)
        seen={str(project.id).upper()}; identities(tree['geometry'],'/geometry',seen)
        for i,scenario in enumerate(project.scenarios):
            base='/scenarios/'+str(i)
            if str(scenario.id).upper() in seen: issues.append(ValidationIssue('duplicate_id',base+'/id',str(scenario.id).upper()))
            seen.add(str(scenario.id).upper())
        room_ids={r.id for r in project.geometry.rooms}; surface_ids={s.id for r in project.geometry.rooms for s in r.surfaces}
        opening_ids={o.id for r in project.geometry.rooms for o in r.openings}
        window_ids={o.id for r in project.geometry.rooms for o in r.openings if o.kind=='window'}
        for i,obstacle in enumerate(project.geometry.obstacles):
            if obstacle.room_id not in room_ids: issues.append(ValidationIssue('dangling_reference',f'/geometry/obstacles/{i}/roomID',str(obstacle.id).upper()))
        for i,r in enumerate(project.geometry.rooms):
            for j,o in enumerate(r.openings):
                if o.surface_id not in {s.id for s in r.surfaces}: issues.append(ValidationIssue('dangling_reference',f'/geometry/rooms/{i}/openings/{j}/surfaceID',str(o.id).upper()))
        for i,scenario in enumerate(project.scenarios):
            base=f'/scenarios/{i}'; scope=set(seen); identities(tree['scenarios'][i]['inputs'],base+'/inputs',scope); identities(tree['scenarios'][i]['evaluation'],base+'/evaluation',scope)
            inputs=scenario.inputs; seat_ids={s.id for s in inputs.usage.seats}; device_ids={d.id for d in inputs.hvac}
            references=[('usage/seats',inputs.usage.seats,'room_id','roomID',room_ids),
                        ('usage/equipment',inputs.usage.equipment,'room_id','roomID',room_ids),
                        ('usage/occupants',inputs.usage.occupants,'seat_id','seatID',seat_ids),
                        ('hvac',inputs.hvac,'room_id','roomID',room_ids),
                        ('controls',inputs.controls,'device_id','deviceID',device_ids),
                        ('envelope/surfaces',inputs.envelope.surfaces,'surface_id','surfaceID',surface_ids),
                        ('envelope/windows',inputs.envelope.windows,'opening_id','openingID',window_ids),
                        ('ventilation',inputs.ventilation,'room_id','roomID',room_ids)]
            for prefix,items,attr,key,allowed in references:
                refs=[]
                for j,item in enumerate(items):
                    ref=getattr(item,attr)
                    if ref not in allowed: issues.append(ValidationIssue('dangling_reference',base+'/inputs/'+prefix+f'/{j}/'+key))
                    refs.append(ref)
                if prefix in ('usage/occupants','controls','envelope/surfaces','envelope/windows','ventilation') and len(refs)!=len(set(refs)):
                    issues.append(ValidationIssue('duplicate_assignment',base+'/inputs/'+prefix))
            for j,v in enumerate(inputs.ventilation):
                room_openings={o.id for r in project.geometry.rooms if r.id==v.room_id for o in r.openings}
                for k,o in enumerate(v.openings):
                    if o.opening_id not in room_openings: issues.append(ValidationIssue('dangling_reference',base+f'/inputs/ventilation/{j}/openings/{k}/openingID'))
        return issues


def contains(bounds,p,tolerance=TOLERANCE):
    return all(o-tolerance <= n <= o+s+tolerance for n,o,s in zip((p.x,p.y,p.z),bounds.origin,bounds.size))

def overlap(a,b): return all(min(o+s,p+t)-max(o,p)>TOLERANCE for o,s,p,t in zip(a.origin,a.size,b.origin,b.size))

class GeometryRule:
    def validate(self,project,registry):
        issues=[]; rooms={}; obstacles={}; room_queries={}
        for i,room in enumerate(project.geometry.rooms):
            bounds=registry.query_bounds('room',room.shape); rooms[room.id]=bounds
            query=registry.geometry_queries('room',room.shape); payload=registry.resolve('room',room.shape)
            if query is not None: room_queries[room.id]=(query,payload)
            if payload is not None and bounds is None: issues.append(ValidationIssue('geometry_uncheckable',f'/geometry/rooms/{i}/shape',blocks=('inputPreparation',)))
            if bounds:
                if sorted(s.face for s in room.surfaces)!=sorted(('xMin','xMax','yMin','yMax','floor','ceiling')):
                    issues.append(ValidationIssue('surface_topology',f'/geometry/rooms/{i}/surfaces'))
                for j,opening in enumerate(room.openings):
                    surface=next((s for s in room.surfaces if s.id==opening.surface_id),None)
                    values=tuple(parameter(wire_tree(v)) for v in (opening.offset_u,opening.offset_v,opening.width,opening.height))
                    if surface and all(v is not None for v in values):
                        u,v,w,h=values; size=bounds.size
                        extent=query.surface_extent(payload,surface.face)
                        if extent is None:
                            issues.append(ValidationIssue('surface_uncheckable',f'/geometry/rooms/{i}/openings/{j}',blocks=('inputPreparation',)))
                            continue
                        if u < -TOLERANCE or v < -TOLERANCE or u+w > extent[0]+TOLERANCE or v+h > extent[1]+TOLERANCE:
                            issues.append(ValidationIssue('opening_bounds',f'/geometry/rooms/{i}/openings/{j}'))
                        for k,other in enumerate(room.openings[:j]):
                            ov=tuple(parameter(wire_tree(p)) for p in (other.offset_u,other.offset_v,other.width,other.height))
                            if other.surface_id == opening.surface_id and all(p is not None for p in ov):
                                if min(u+w,ov[0]+ov[2])-max(u,ov[0])>TOLERANCE and min(v+h,ov[1]+ov[3])-max(v,ov[1])>TOLERANCE:
                                    issues.append(ValidationIssue('opening_overlap',f'/geometry/rooms/{i}/openings/{j}'))
        for i,obstacle in enumerate(project.geometry.obstacles):
            bounds=registry.query_bounds('obstacle',obstacle.shape)
            query=registry.geometry_queries('obstacle',obstacle.shape); payload=registry.resolve('obstacle',obstacle.shape)
            if not bounds:
                if payload is not None: issues.append(ValidationIssue('geometry_uncheckable',f'/geometry/obstacles/{i}/shape',blocks=('inputPreparation',)))
                continue
            room=rooms.get(obstacle.room_id)
            if room:
                from .domain import Position3D
                origin=Position3D(x=bounds.origin[0],y=bounds.origin[1],z=bounds.origin[2])
                end=Position3D(x=bounds.origin[0]+bounds.size[0],y=bounds.origin[1]+bounds.size[1],z=bounds.origin[2]+bounds.size[2])
                rq,rp=room_queries[obstacle.room_id]
                if not rq.contains(rp,(origin.x,origin.y,origin.z),TOLERANCE) or not rq.contains(rp,(end.x,end.y,end.z),TOLERANCE): issues.append(ValidationIssue('obstacle_bounds',f'/geometry/obstacles/{i}'))
            for previous,previous_query,previous_payload in obstacles.get(obstacle.room_id,[]):
                if query.intersects(payload,previous,TOLERANCE) or previous_query.intersects(previous_payload,bounds,TOLERANCE): issues.append(ValidationIssue('obstacle_overlap',f'/geometry/obstacles/{i}'))
            obstacles.setdefault(obstacle.room_id,[]).append((bounds,query,payload))
        def point(p,room_id,path,fluid=False):
            room=rooms.get(room_id)
            if room and not room_queries[room_id][0].contains(room_queries[room_id][1],(p.x,p.y,p.z),-TOLERANCE if fluid else TOLERANCE): issues.append(ValidationIssue('point_bounds',path))
            if any(q.contains(model,(p.x,p.y,p.z),TOLERANCE) for o,q,model in obstacles.get(room_id,[])): issues.append(ValidationIssue('point_in_solid',path))
        for i,s in enumerate(project.scenarios):
            base=f'/scenarios/{i}/inputs'
            for j,seat in enumerate(s.inputs.usage.seats):
                point(seat.position,seat.room_id,base+f'/usage/seats/{j}/position')
                for k,sample in enumerate(seat.samples): point(sample.position,seat.room_id,base+f'/usage/seats/{j}/samples/{k}/position',True)
            for j,e in enumerate(s.inputs.usage.equipment): point(e.position,e.room_id,base+f'/usage/equipment/{j}/position',True)
            devices={d.id:d for d in s.inputs.hvac}
            for j,d in enumerate(s.inputs.hvac):
                point(d.position,d.room_id,base+f'/hvac/{j}/position')
                for k,port in enumerate(d.ports): point(port.position,d.room_id,base+f'/hvac/{j}/ports/{k}/position')
            for j,c in enumerate(s.inputs.controls):
                if c.device_id in devices: point(c.sensor_position,devices[c.device_id].room_id,base+f'/controls/{j}/sensorPosition',True)
        return issues

class PhysicsRule:
    def validate(self,project,registry):
        issues=[]
        if len(project.geometry.rooms)!=1: issues.append(ValidationIssue('room_count','/geometry/rooms',blocks=('inputPreparation',)))
        if not project.scenarios: issues.append(ValidationIssue('scenario_required','/scenarios',blocks=('inputPreparation',)))
        for i,s in enumerate(project.scenarios):
            base=f'/scenarios/{i}/inputs'; inputs=s.inputs
            if len(inputs.hvac)!=1: issues.append(ValidationIssue('device_count',base+'/hvac',blocks=('inputPreparation',)))
            for j,d in enumerate(inputs.hvac):
                path=base+f'/hvac/{j}'; roles={p.role for p in d.ports}
                if roles!={'supply','return'}: issues.append(ValidationIssue('port_topology',path+'/ports',blocks=('inputPreparation',)))
                if any(p.volume_flow.state=='unknown' or p.density.state=='unknown' for p in d.ports):
                    issues.append(ValidationIssue('mass_balance_uncheckable',path+'/ports',blocks=('inputPreparation',)))
                else:
                    supply=sum(p.volume_flow.value*p.density.value for p in d.ports if p.role=='supply')
                    ret=sum(p.volume_flow.value*p.density.value for p in d.ports if p.role=='return')
                    if abs(supply-ret)>TOLERANCE*max(supply,ret,1e-12): issues.append(ValidationIssue('recirculation_balance',path+'/ports',blocks=('inputPreparation',)))
                for k,p in enumerate(d.ports):
                    pp=path+f'/ports/{k}'
                    norm=math.sqrt(p.direction.x**2+p.direction.y**2+p.direction.z**2)
                    if abs(norm-1)>TOLERANCE: issues.append(ValidationIssue('direction_unit',pp+'/direction'))
                    if all(v.state=='known' for v in (p.area,p.volume_flow,p.speed)) and abs(p.area.value*p.speed.value-p.volume_flow.value)>TOLERANCE*max(p.volume_flow.value,1e-12):
                        issues.append(ValidationIssue('flow_area_speed',pp))
            surface_ids={r.id for r in project.geometry.rooms for r in r.surfaces}
            if {c.surface_id for c in inputs.envelope.surfaces}!=surface_ids: issues.append(ValidationIssue('envelope_incomplete',base+'/envelope/surfaces',blocks=('inputPreparation',)))
            if {c.device_id for c in inputs.controls}!={d.id for d in inputs.hvac}: issues.append(ValidationIssue('control_incomplete',base+'/controls',blocks=('inputPreparation',)))
            if {v.room_id for v in inputs.ventilation}!={r.id for r in project.geometry.rooms}: issues.append(ValidationIssue('ventilation_incomplete',base+'/ventilation',blocks=('inputPreparation',)))
            for j,c in enumerate(inputs.envelope.surfaces):
                b=c.boundary
                if b.mode=='temperature' and (b.temperature is None or b.heat_flux is not None) or b.mode=='heatFlux' and (b.heat_flux is None or b.temperature is not None) or b.mode=='fromL1' and (b.temperature is not None or b.heat_flux is not None):
                    issues.append(ValidationIssue('boundary_exclusive',base+f'/envelope/surfaces/{j}/boundary'))
                if b.mode=='fromL1': issues.append(ValidationIssue('boundary_unresolved',base+f'/envelope/surfaces/{j}/boundary',blocks=('inputPreparation',)))
            for j,v in enumerate(inputs.ventilation):
                if all(p.state=='known' for p in (v.outdoor_air,v.exhaust_air,v.infiltration,v.exfiltration,v.density)):
                    inflow=v.outdoor_air.value+v.infiltration.value; outflow=v.exhaust_air.value+v.exfiltration.value
                    if abs(inflow-outflow)*v.density.value>TOLERANCE*max(inflow,outflow,1e-12)*v.density.value:
                        issues.append(ValidationIssue('outdoor_exchange_balance',base+f'/ventilation/{j}',blocks=('inputPreparation',)))
            e=inputs.environment
            for key,value in [('representativeDate',e.representative_date),('timeZone',e.time_zone),('weather',e.weather)]:
                if value is None: issues.append(ValidationIssue('required_input',base+'/environment/'+key,blocks=('inputPreparation',)))
            if e.representative_date:
                try:
                    if date.fromisoformat(e.representative_date).isoformat()!=e.representative_date: raise ValueError()
                except ValueError: issues.append(ValidationIssue('representative_date',base+'/environment/representativeDate'))
            if e.time_zone:
                try: ZoneInfo(e.time_zone)
                except ZoneInfoNotFoundError: issues.append(ValidationIssue('time_zone',base+'/environment/timeZone'))
            if e.weather:
                path=e.weather.relative_path
                if not path or path.startswith('/') or '\\' in path or any(p in ('','..','.') for p in path.split('/')) or ':' in path:
                    issues.append(ValidationIssue('relative_path',base+'/environment/weather/relativePath'))
                if not re.fullmatch('[a-fA-F0-9]{64}',e.weather.sha256): issues.append(ValidationIssue('content_hash',base+'/environment/weather/sha256'))
            window_ids={o.id for r in project.geometry.rooms for o in r.openings if o.kind=='window'}
            if {w.opening_id for w in inputs.envelope.windows} != window_ids:
                issues.append(ValidationIssue('windows_incomplete',base+'/envelope/windows',blocks=('inputPreparation',)))
            schedule_paths=[]
            for prefix,items in [('usage/occupants',inputs.usage.occupants),('usage/equipment',inputs.usage.equipment),('controls',inputs.controls)]:
                schedule_paths.extend(base+'/'+prefix+f'/{j}/schedule/intervals' for j in range(len(items)))
            issues.extend(InputRequirements(full_day_schedule_paths=tuple(schedule_paths)).validate(project,registry))
            for j,seat in enumerate(inputs.usage.seats):
                if not seat.samples: issues.append(ValidationIssue('sample_required',base+f'/usage/seats/{j}/samples',blocks=('inputPreparation',)))
            for j,v in enumerate(inputs.ventilation):
                opening_ids={o.id for r in project.geometry.rooms if r.id==v.room_id for o in r.openings}
                if {o.opening_id for o in v.openings} != opening_ids:
                    issues.append(ValidationIssue('opening_states_incomplete',base+f'/ventilation/{j}/openings',blocks=('inputPreparation',)))
                if len(v.openings) != len({o.opening_id for o in v.openings}):
                    issues.append(ValidationIssue('duplicate_assignment',base+f'/ventilation/{j}/openings'))
            currency=s.evaluation.cost.currency
            if currency is None and (any(t.rate.state=='known' for t in s.evaluation.cost.tariffs) or any(q.amount.state=='known' for q in s.evaluation.cost.quotes)):
                issues.append(ValidationIssue('currency_required',f'/scenarios/{i}/evaluation/cost/currency'))
            if currency is not None and not re.fullmatch('[A-Z]{3}',currency): issues.append(ValidationIssue('currency',f'/scenarios/{i}/evaluation/cost/currency'))
        return issues

@dataclass(frozen=True)
class InputRequirements:
    required_paths: tuple = ()
    full_day_schedule_paths: tuple = ()
    def validate(self,project,registry):
        tree=wire_tree(project); issues=[]
        def at(pointer):
            node=tree
            try:
                for part in pointer[1:].split('/'):
                    part=part.replace('~1','/').replace('~0','~')
                    node=node[int(part)] if isinstance(node,list) else node[part]
                return node
            except (KeyError,ValueError,IndexError,TypeError): return None
        for path in self.required_paths:
            value=at(path)
            if value is None or isinstance(value,dict) and value.get('state')=='unknown': issues.append(ValidationIssue('required_input',path,blocks=('inputPreparation',)))
        for path in self.full_day_schedule_paths:
            items=at(path) or []; cursor=0
            for item in items:
                if numeric(item['startMinute'])!=cursor: cursor=-1; break
                cursor=numeric(item['endMinute'])
            if cursor!=1440: issues.append(ValidationIssue('schedule_coverage',path,blocks=('inputPreparation',)))
        return issues

class ProjectValidator:
    def __init__(self,rules=None): self.rules=tuple(rules) if rules is not None else (ParameterRule(),IdentityRule(),GeometryRule(),PhysicsRule())
    def validate(self,project,registry):
        from .codec import ProjectCodec
        ProjectCodec(registry).encode(project)
        tree=wire_tree(project)
        def associated(issue):
            if issue.entity_id is not None: return issue
            pointer=issue.path
            while True:
                node=tree
                try:
                    for part in pointer[1:].split('/') if pointer else ():
                        key=part.replace('~1','/').replace('~0','~')
                        node=node[int(key)] if isinstance(node,list) else node[key]
                    if isinstance(node,dict):
                        for key in ('id','surfaceID','openingID','roomID','deviceID','seatID'):
                            if key in node: return replace(issue,entity_id=node[key].upper())
                except (KeyError,IndexError,TypeError,ValueError): pass
                if not pointer: return issue
                pointer=pointer.rsplit('/',1)[0]
        return ValidationReport(tuple(associated(issue) for rule in self.rules for issue in rule.validate(project,registry)))
