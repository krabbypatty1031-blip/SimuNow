"""Artificial contract inputs, NOT physical benchmarks or deployable weather data."""
from uuid import UUID
from copy import deepcopy

def identity(n): return str(UUID(int=n)).upper()
def known(value,unit,kind='assumed'):
    return {'state':'known','value':value,'unit':unit,'source':{'kind':kind,'note':'Artificial contract fixture; not measured or validated.'}}
def unknown(reason='Not supplied in this contract fixture'): return {'state':'unknown','reason':reason}
def point(x,y,z): return {'x':x,'y':y,'z':z}
def schedule(): return {'intervals':[{'startMinute':0,'endMinute':1440,'fraction':known(1,'1')}]}
def heat(): return {'sensible':known(80,'W'),'convectiveFraction':known(.6,'1'),'latent':known(40,'W')}

def project(space='office'):
    size=(6,4,3) if space=='office' else (8,6,3)
    room={'id':identity(2),'name':'Artificial '+space,'shape':{'kind':'simunow.geometry.rectangularRoom','payloadVersion':1,'payload':{'dimensions':dict(zip(('width','depth','height'),[known(v,'m') for v in size]))}},
          'northAngle':known(0,'deg'),'surfaces':[{'id':identity(10+i),'face':face} for i,face in enumerate(('xMin','xMax','yMin','yMax','floor','ceiling'))],
          'openings':[{'id':identity(20),'surfaceID':identity(10),'kind':'door','offsetU':known(.2,'m'),'offsetV':known(0,'m'),'width':known(.8,'m'),'height':known(2,'m')},
                      {'id':identity(21),'surfaceID':identity(11),'kind':'window','offsetU':known(.5,'m'),'offsetV':known(1,'m'),'width':known(1.2,'m'),'height':known(1,'m')}]}
    seat={'id':identity(40),'roomID':identity(2),'name':'Contract seat','position':point(3,2,.7),'samples':[{'id':identity(41),'position':point(3,2,1.1)}]}
    ports=[{'id':identity(51+i),'role':role,'position':point(.01,2+i*.5,2.3),'direction':point(1 if i==0 else -1,0,0),
            'area':known(.1,'m2'),'volumeFlow':known(.2,'m3/s'),'speed':known(2,'m/s'),'density':known(1.2,'kg/m3')} for i,role in enumerate(('supply','return'))]
    inputs={'usage':{'seats':[seat],'occupants':[{'id':identity(42),'seatID':identity(40),'activity':known(1.2,'met'),'clothing':known(.5,'clo'),'heat':heat(),'schedule':schedule()}],
                     'equipment':[{'id':identity(43),'roomID':identity(2),'position':point(4,3,1),'heat':heat(),'schedule':schedule()}]},
            'hvac':[{'id':identity(50),'roomID':identity(2),'name':'Artificial split unit','position':point(.01,2,2.3),
                     'definition':{'kind':'simunow.hvac.singleSplit','payloadVersion':1,'payload':{'coolingCapacity':known(3000,'W'),'electricalPower':known(1000,'W'),'cop':known(3,'1')}},
                     'ports':ports,'supplyTemperature':known(16,'degC')}],
            'controls':[{'id':identity(60),'deviceID':identity(50),'setpoint':known(25,'degC'),'sensorPosition':point(3,2,1.2),'schedule':schedule()}],
            'envelope':{'surfaces':[{'surfaceID':s['id'],'exposure':'outdoors' if i<4 else 'adiabatic','uValue':known(1,'W/(m2.K)'),
                                    'boundary':{'mode':'temperature','temperature':known(27,'degC')}} for i,s in enumerate(room['surfaces'])],
                        'windows':[{'openingID':identity(21),'uValue':known(2,'W/(m2.K)'),'shgc':known(.5,'1'),'shadingFactor':known(1,'1')}]},
            'ventilation':[{'roomID':identity(2),'outdoorAir':known(0,'m3/s'),'exhaustAir':known(0,'m3/s'),'infiltration':known(0,'m3/s'),'exfiltration':known(0,'m3/s'),'density':known(1.2,'kg/m3'),
                            'openings':[{'openingID':identity(20),'openFraction':known(0,'1')},{'openingID':identity(21),'openFraction':known(0,'1')}]}],
            'environment':{'representativeDate':'2026-10-02','timeZone':'Asia/Hong_Kong','weather':{'relativePath':'weather/contract-only.epw','sha256':'0'*64},
                           'outdoorTemperature':known(32,'degC'),'outdoorHumidity':known(.6,'1'),'indoorHumidity':known(.5,'1')}}
    return {'schemaVersion':2,'id':identity(1),'name':'Artificial '+space+' contract','spaceType':space,'lengthUnit':'m','coordinateSystem':'rightHandedZUp',
            'geometry':{'rooms':[room],'obstacles':[{'id':identity(30),'roomID':identity(2),'name':'Contract box','shape':{'kind':'simunow.geometry.box','payloadVersion':1,
                      'payload':{'origin':point(1,1,0),'dimensions':{'width':known(1,'m'),'depth':known(.5,'m'),'height':known(.8,'m')}}}}]},
            'scenarios':[{'id':identity(3),'name':'Artificial baseline','inputs':inputs,'evaluation':{'cost':{'currency':None,'tariffs':[],'quotes':[]}}}]}


def semantic_cases():
    cases={}
    def put(name,change):
        p=project(); change(p); cases[name]=p
    put('negative-dimension',lambda p:p['geometry']['rooms'][0]['shape']['payload']['dimensions']['width'].update(value=-1))
    put('duplicate-id',lambda p:p['geometry']['rooms'][0]['surfaces'][0].update(id=identity(2)))
    put('dangling-seat',lambda p:p['scenarios'][0]['inputs']['usage']['occupants'][0].update(seatID=identity(999)))
    put('opening-outside',lambda p:p['geometry']['rooms'][0]['openings'][0]['offsetU'].update(value=20))
    put('furniture-outside',lambda p:p['geometry']['obstacles'][0]['shape']['payload']['origin'].update(x=7))
    put('furniture-overlap',lambda p:p['geometry']['obstacles'].append({**deepcopy(p['geometry']['obstacles'][0]),'id':identity(31)}))
    put('sample-solid',lambda p:p['scenarios'][0]['inputs']['usage']['seats'][0]['samples'][0]['position'].update(x=1.5,y=1.2,z=.5))
    put('sample-wall',lambda p:p['scenarios'][0]['inputs']['usage']['seats'][0]['samples'][0]['position'].update(x=0))
    put('flow-mismatch',lambda p:p['scenarios'][0]['inputs']['hvac'][0]['ports'][0]['volumeFlow'].update(value=.3))
    put('density-missing',lambda p:p['scenarios'][0]['inputs']['hvac'][0]['ports'][0].update(density=unknown()))
    put('bad-direction',lambda p:p['scenarios'][0]['inputs']['hvac'][0]['ports'][0]['direction'].update(x=0))
    put('outdoor-imbalance',lambda p:p['scenarios'][0]['inputs']['ventilation'][0]['outdoorAir'].update(value=.1))
    put('boundary-exclusive',lambda p:p['scenarios'][0]['inputs']['envelope']['surfaces'][0]['boundary'].update(heatFlux=known(10,'W/m2')))
    put('boundary-unresolved',lambda p:p['scenarios'][0]['inputs']['envelope']['surfaces'][0].update(boundary={'mode':'fromL1'}))
    put('heat-fraction',lambda p:p['scenarios'][0]['inputs']['usage']['occupants'][0]['heat']['convectiveFraction'].update(value=1.5))
    put('missing-source',lambda p:p['scenarios'][0]['inputs']['hvac'][0]['definition']['payload']['cop'].update(source={'kind':'manufacturer'}))
    put('unknown-temperature',lambda p:p['scenarios'][0]['inputs']['controls'][0].update(setpoint=unknown()))
    put('schedule-overlap',lambda p:p['scenarios'][0]['inputs']['controls'][0]['schedule']['intervals'].append({'startMinute':600,'endMinute':700,'fraction':known(1,'1')}))
    put('bad-date',lambda p:p['scenarios'][0]['inputs']['environment'].update(representativeDate='2026-02-30'))
    put('bad-zone',lambda p:p['scenarios'][0]['inputs']['environment'].update(timeZone='Invalid/Zone'))
    put('private-path',lambda p:p['scenarios'][0]['inputs']['environment']['weather'].update(relativePath='../private.epw'))
    put('unknown-type',lambda p:p['scenarios'][0]['inputs']['hvac'][0].update(definition={'kind':'future.hvac','payloadVersion':7,'payload':{'big':1234567890123456789012345678901234567890,'nested':[None,{'flag':True}]}}))
    put('sample-missing',lambda p:p['scenarios'][0]['inputs']['usage']['seats'][0].update(samples=[]))
    put('window-missing',lambda p:p['scenarios'][0]['inputs']['envelope'].update(windows=[]))
    put('opening-state-missing',lambda p:p['scenarios'][0]['inputs']['ventilation'][0].update(openings=[]))
    put('schedule-gap',lambda p:p['scenarios'][0]['inputs']['controls'][0]['schedule']['intervals'][0].update(startMinute=100))
    put('currency-missing',lambda p:p['scenarios'][0]['evaluation']['cost'].update(quotes=[{'id':identity(80),'amount':known(100,'currency')}]))
    put('quote-duplicate',lambda p:p['scenarios'][0]['evaluation']['cost'].update(currency='HKD',quotes=[{'id':identity(50),'amount':known(100,'currency')}]))
    return cases


def structural_cases():
    cases={}
    def put(name,change):
        p=project(); change(p); cases[name]=p
    put('wrong-unit',lambda p:p['geometry']['rooms'][0]['shape']['payload']['dimensions']['width'].update(unit='ft'))
    put('wrong-type',lambda p:p['scenarios'][0]['inputs']['controls'][0]['setpoint'].update(value='25'))
    put('extra-field',lambda p:p.update(engine='fake'))
    put('missing-field',lambda p:p.pop('geometry'))
    put('unknown-version',lambda p:p.update(schemaVersion=3))
    put('known-invalid',lambda p:p['scenarios'][0]['inputs']['hvac'][0]['definition'].update(payload={'unexpected':True}))
    put('wrong-payload-category',lambda p:p['scenarios'][0]['inputs']['hvac'][0].update(definition=deepcopy(p['geometry']['rooms'][0]['shape'])))
    put('empty-kind',lambda p:p['scenarios'][0]['inputs']['hvac'][0]['definition'].update(kind=''))
    put('negative-version',lambda p:p['scenarios'][0]['inputs']['hvac'][0]['definition'].update(payloadVersion=-1))
    put('invalid-uuid',lambda p:p.update(id='not-an-id'))
    return cases
