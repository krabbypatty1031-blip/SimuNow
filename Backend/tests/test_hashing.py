"""Canonical hash text rules shared with Swift InputHash."""
import unittest
from simunow_worker.models.json_value import parse
from simunow_worker.models.hashing import canonical_text, input_hash


class CanonicalTextTests(unittest.TestCase):
    def test_key_order_by_utf8_bytes(self):
        tree = parse('{"b":1,"a":2,"ä":3}')
        self.assertEqual(canonical_text(tree), '{"a":2,"b":1,"ä":3}')

    def test_string_escapes_minimal(self):
        tree = parse('{"s":"a\\"b\\\\c\\nd"}')
        self.assertEqual(canonical_text(tree), '{"s":"a\\"b\\\\c\\nd"}')

    def test_number_tokens_preserved(self):
        self.assertEqual(canonical_text(parse('[1.50,1e2,-0]')), '[1.50,1e2,-0]')

    def test_scalars(self):
        self.assertEqual(canonical_text(parse('[true,false,null]')), '[true,false,null]')

    def test_hash_is_sha256_hex(self):
        value = input_hash('{"a":1}')
        self.assertEqual(len(value), 64)
        self.assertTrue(all(c in '0123456789abcdef' for c in value))

    def test_control_character_escape_lowercase(self):
        tree = parse('{"s":"\\u0001"}')
        self.assertEqual(canonical_text(tree), '{"s":"\\u0001"}')


if __name__ == '__main__':
    unittest.main()
