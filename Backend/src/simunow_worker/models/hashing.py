"""Canonical hash text + SHA-256 for run input identity.

Shared rules with Swift InputHash (Protocols/run-input-v1.md):
- object keys sorted by UTF-8 byte sequence; no whitespace
- strings escape only `"` `\\` and control chars (short escapes, else \\u00xx lowercase);
  non-ASCII passes through as UTF-8
- numbers keep their original wire token
"""
import hashlib
from .json_value import Number, parse

_ESCAPES = {'"': '\\"', '\\': '\\\\', '\b': '\\b', '\t': '\\t', '\n': '\\n', '\f': '\\f', '\r': '\\r'}


def _string(value: str) -> str:
    out = []
    for ch in value:
        if ch in _ESCAPES:
            out.append(_ESCAPES[ch])
        elif ord(ch) < 0x20:
            out.append('\\u%04x' % ord(ch))
        else:
            out.append(ch)
    return '"' + ''.join(out) + '"'


def canonical_text(tree) -> str:
    if isinstance(tree, Number):
        return tree.token
    if isinstance(tree, dict):
        items = sorted(tree.items(), key=lambda kv: kv[0].encode('utf-8'))
        return '{' + ','.join(_string(k) + ':' + canonical_text(v) for k, v in items) + '}'
    if isinstance(tree, (tuple, list)):
        return '[' + ','.join(canonical_text(v) for v in tree) + ']'
    if isinstance(tree, str):
        return _string(tree)
    if tree is True:
        return 'true'
    if tree is False:
        return 'false'
    if tree is None:
        return 'null'
    raise TypeError(f'unhashable node: {type(tree)}')


def input_hash(canonical: str) -> str:
    return hashlib.sha256(canonical.encode('utf-8')).hexdigest()


def snapshot_hash(snapshot) -> str:
    """SHA-256 over the canonical text of a ScenarioInputSnapshot wire tree."""
    from .codec import wire_tree
    return input_hash(canonical_text(parse_snapshot(snapshot)))


def parse_snapshot(snapshot):
    from .codec import wire_tree
    return parse_rendered(wire_tree(snapshot))


def parse_rendered(tree):
    """Normalize a wire tree (dict/tuple/Number/str/None) through render+parse."""
    from .json_value import render
    return parse(render(tree))
