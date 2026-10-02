"""Explicit unfinished values, without physical default assumptions."""
from uuid import uuid4
from .domain import ProjectDocument, Scenario
from .primitives import Unknown

def unfinished_project(name, space_type='office', identity=None):
    return ProjectDocument(schemaVersion=2,id=identity or uuid4(),name=name,spaceType=space_type,
                           lengthUnit='m',coordinateSystem='rightHandedZUp',geometry={'rooms':(),'obstacles':()},scenarios=())

def unfinished_scenario(name, identity=None):
    return Scenario(id=identity or uuid4(),name=name,
                    inputs={'usage':{'seats':(),'occupants':(),'equipment':()},'hvac':(),'controls':(),
                            'envelope':{'surfaces':(),'windows':()},'ventilation':(),
                            'environment':{'outdoorTemperature':Unknown(state='unknown',reason='Not supplied'),
                                           'outdoorHumidity':Unknown(state='unknown',reason='Not supplied'),
                                           'indoorHumidity':Unknown(state='unknown',reason='Not supplied')}},
                    evaluation={'cost':{'tariffs':(),'quotes':()}})

def split_sensible_heat(gain):
    if gain.sensible.state=='unknown' or gain.convective_fraction.state=='unknown': return None
    total=gain.sensible.value; fraction=gain.convective_fraction.value
    return total*fraction, total*(1-fraction)
