"""Lossless JSON at the wire boundary; no floats in opaque extension payloads."""
from dataclasses import dataclass
import json
from pydantic_core import core_schema

@dataclass(frozen=True)
class Number:
    token: str


def parse(text: str):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f'duplicate_key: {key}')
            result[key] = value
        return result
    def invalid(value):
        raise ValueError(f'non_finite: {value}')
    tree = json.loads(text, parse_int=Number, parse_float=Number,
                      parse_constant=invalid, object_pairs_hook=pairs)
    def unicode_scalars(value,depth=0):
        if depth >= 128: raise ValueError("nesting too deep")
        if isinstance(value,str): value.encode('utf-8',errors='strict')
        elif isinstance(value,dict):
            for key,item in value.items(): key.encode('utf-8',errors='strict'); unicode_scalars(item,depth+1)
        elif isinstance(value,list):
            for item in value: unicode_scalars(item,depth+1)
    unicode_scalars(tree)
    return tree


def render(value):
    if isinstance(value, Number):
        # Tokens are only created by the JSON parser or from validated numeric values.
        parse(value.token)
        return value.token
    if isinstance(value, dict):
        return '{' + ','.join(json.dumps(k, ensure_ascii=True) + ':' + render(v)
                              for k, v in sorted(value.items())) + '}'
    if isinstance(value, (tuple, list)):
        return '[' + ','.join(map(render, value)) + ']'
    return json.dumps(value, ensure_ascii=True, allow_nan=False, separators=(',', ':'))


@dataclass(frozen=True)
class FrozenJSON:
    """An immutable canonical JSON string, including original numeric tokens."""
    text: str

    def __post_init__(self):
        tree = parse(self.text)
        if not isinstance(tree, dict):
            raise ValueError('payload must be an object')
        object.__setattr__(self, 'text', render(tree))

    @classmethod
    def from_tree(cls, tree):
        return cls(render(tree))

    def tree(self):
        return parse(self.text)  # Always returns an independent value.

    @classmethod
    def __get_pydantic_core_schema__(cls, source, handler):
        return core_schema.is_instance_schema(cls)

    @classmethod
    def __get_pydantic_json_schema__(cls, schema, handler):
        return {'type': 'object'}
