"""Load Protocols/Schemas into a referencing Registry so cross-file $ref resolves."""
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

SCHEMAS = Path(__file__).resolve().parents[2] / "Protocols" / "Schemas"


def make_registry():
    pairs = []
    for path in SCHEMAS.glob("*.schema.json"):
        contents = json.loads(path.read_text(encoding="utf-8"))
        resource = Resource.from_contents(contents, default_specification=DRAFT202012)
        uris = {path.name, f"https://simunow.local/schemas/{path.name}"}
        if isinstance(contents.get("$id"), str):
            uris.add(contents["$id"])
        pairs.extend((uri, resource) for uri in uris)
    return Registry().with_resources(pairs)


def validator(name, registry=None):
    return Draft202012Validator(json.loads((SCHEMAS / name).read_text(encoding="utf-8")),
                                registry=registry or make_registry(),
                                format_checker=FormatChecker())
