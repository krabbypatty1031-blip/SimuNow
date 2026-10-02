"""Immutable, injected registry. No central device/geometry type switch."""
from dataclasses import dataclass
from types import MappingProxyType
from typing import Callable
from .domain import RectangularRoom, BoxObstacle, SingleSplit
from .json_value import FrozenJSON, Number


def native(value):
    if isinstance(value, Number): return value
    if isinstance(value, dict):
        return {k: FrozenJSON.from_tree(v) if k == 'payload' else native(v) for k,v in value.items()}
    if isinstance(value, list): return tuple(map(native, value))
    return value


@dataclass(frozen=True)
class Bounds:
    origin: tuple[float, float, float]
    size: tuple[float, float, float]

@dataclass(frozen=True)
class GeometryQueries:
    contains: Callable
    surface_extent: Callable
    intersects: Callable

@dataclass(frozen=True)
class Registration:
    category: str
    kind: str
    version: int
    model: type
    bounds: Callable | None = None
    rules: tuple = ()
    geometry: GeometryQueries | None = None

@dataclass(frozen=True, init=False)
class ModelRegistry:
    _entries: object
    def __init__(self, registrations):
        entries = {}
        for item in registrations:
            if item.category in ('room','obstacle') and (item.bounds is None or item.geometry is None):
                raise ValueError('geometry queries required')
            key = (item.category, item.kind, item.version)
            if key in entries: raise ValueError('duplicate_registration: ' + item.kind)
            entries[key] = item
        object.__setattr__(self, "_entries", MappingProxyType(entries))

    @property
    def registrations(self): return tuple(self._entries.values())

    def lookup(self, category, record):
        return self._entries.get((category, record.kind, record.payload_version))

    def resolve(self, category, record):
        item = self.lookup(category, record)
        return None if item is None else item.model.model_validate(native(record.payload.tree()))

    def query_bounds(self, category, record):
        item = self.lookup(category, record)
        if item is None or item.bounds is None: return None
        return item.bounds(self.resolve(category, record))

    def geometry_queries(self, category, record):
        item = self.lookup(category, record)
        return None if item is None else item.geometry


def axis_aligned_queries(bounds_function):
    def contains(model, point, tolerance):
        b=bounds_function(model)
        return b is not None and all(o-tolerance <= v <= o+s+tolerance for v,o,s in zip(point,b.origin,b.size))
    def extent(model, face):
        b=bounds_function(model)
        if b is None: return None
        return (b.size[1],b.size[2]) if face.startswith('x') else (b.size[0],b.size[2]) if face.startswith('y') else (b.size[0],b.size[1])
    def intersects(model, other, tolerance):
        b=bounds_function(model)
        return b is not None and all(min(o+s,p+t)-max(o,p)>tolerance for o,s,p,t in zip(b.origin,b.size,other.origin,other.size))
    return GeometryQueries(contains,extent,intersects)


def dimensions(value):
    params = (value.width, value.depth, value.height)
    if any(p.state == 'unknown' for p in params): return None
    return tuple(p.value for p in params)


def rectangle_bounds(model):
    size = dimensions(model.dimensions)
    return None if size is None else Bounds((0.,0.,0.), size)


def box_bounds(model):
    size = dimensions(model.dimensions)
    return None if size is None else Bounds((model.origin.x,model.origin.y,model.origin.z), size)


def default_registry():
    return ModelRegistry((
        Registration('room','simunow.geometry.rectangularRoom',1,RectangularRoom,rectangle_bounds,geometry=axis_aligned_queries(rectangle_bounds)),
        Registration('obstacle','simunow.geometry.box',1,BoxObstacle,box_bounds,geometry=axis_aligned_queries(box_bounds)),
        Registration('hvac','simunow.hvac.singleSplit',1,SingleSplit),
    ))
