"""Typed wire primitives. SI-derived units are explicit, never inferred."""
import math
import re
from typing import Annotated, Generic, Literal, TypeVar
from uuid import UUID
from pydantic import BaseModel, ConfigDict, BeforeValidator, Field
from pydantic.alias_generators import to_camel
from .json_value import Number


def floating(value):
    if isinstance(value, Number):
        value = float(value.token)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError('finite number required')
    return float(value)


def integer(value):
    if isinstance(value, Number):
        from decimal import Decimal
        number = Decimal(value.token)
        if number != number.to_integral_value():
            raise ValueError('integer required')
        value = int(number)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError('integer required')
    if not -(2**63) <= value <= 2**63-1:
        raise ValueError('integer out of range')
    return value


def identity(value):
    if isinstance(value, str):
        if not re.fullmatch(r"[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}",value):
            raise ValueError("canonical UUID required")
        return UUID(value)
    return value

FloatValue = Annotated[float, BeforeValidator(floating)]
IntValue = Annotated[int, BeforeValidator(integer), Field(json_schema_extra={'minimum':-(2**63), 'maximum':2**63-1})]
Identity = Annotated[UUID, BeforeValidator(identity)]
SpaceType = Literal['office', 'classroom', 'home', 'publicSpace']
SourceKind = Literal['scan', 'measured', 'manufacturer', 'user', 'preset', 'assumed']
OpeningKind = Literal['door', 'window']
SurfaceFace = Literal['xMin', 'xMax', 'yMin', 'yMax', 'floor', 'ceiling']
PortRole = Literal['supply', 'return']
Exposure = Literal['outdoors', 'adiabatic']
BoundaryMode = Literal['temperature', 'heatFlux', 'fromL1']

def wire_alias(name):
    result = to_camel(name)
    return result[:-2] + "ID" if result.endswith("Id") else result

class WireModel(BaseModel):
    model_config = ConfigDict(strict=True, frozen=True, extra='forbid', allow_inf_nan=False,
                             alias_generator=wire_alias, populate_by_name=False)

class SourceRecord(WireModel):
    kind: SourceKind
    reference: str | None = None
    note: str | None = None

class UncertaintyBounds(WireModel):
    lower: FloatValue
    upper: FloatValue
    meaning: str

U = TypeVar('U')
class Known(WireModel, Generic[U]):
    state: Literal['known']
    value: FloatValue
    unit: U
    source: SourceRecord
    uncertainty: UncertaintyBounds | None = None

class Unknown(WireModel):
    state: Literal['unknown']
    reason: str

Length = Known[Literal['m']] | Unknown
Area = Known[Literal['m2']] | Unknown
Temperature = Known[Literal['degC']] | Unknown
class ThermalPowerKnown(Known[Literal['W']]):
    pass
class ElectricalPowerKnown(Known[Literal['W']]):
    pass
ThermalPower = ThermalPowerKnown | Unknown
ElectricalPower = ElectricalPowerKnown | Unknown
VolumeFlow = Known[Literal['m3/s']] | Unknown
Speed = Known[Literal['m/s']] | Unknown
Pressure = Known[Literal['Pa']] | Unknown
Angle = Known[Literal['deg']] | Unknown
Ratio = Known[Literal['1']] | Unknown
Activity = Known[Literal['met']] | Unknown
Clothing = Known[Literal['clo']] | Unknown
Density = Known[Literal['kg/m3']] | Unknown
UValue = Known[Literal['W/(m2.K)']] | Unknown
HeatFlux = Known[Literal['W/m2']] | Unknown
Money = Known[Literal['currency']] | Unknown
EnergyRate = Known[Literal['currency/kWh']] | Unknown
