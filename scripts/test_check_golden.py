"""Unit tests for scripts/check_golden.py and scripts/validate_against_sigma_schema.py."""
import json
import os
import tempfile
import unittest

import check_golden
import validate_against_sigma_schema as validator


def write(directory, name, payload):
    with open(os.path.join(directory, name), "w") as handle:
        json.dump(payload, handle)


class GoldenTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.actual = os.path.join(self.tmp.name, "actual")
        self.expected = os.path.join(self.tmp.name, "expected")
        os.makedirs(self.actual)
        os.makedirs(self.expected)

    def tearDown(self):
        self.tmp.cleanup()

    def test_identical_files_match_regardless_of_key_order(self):
        write(self.actual, "a.json", {"x": 1, "y": [1, 2]})
        write(self.expected, "a.json", {"y": [1, 2], "x": 1})
        self.assertEqual(check_golden.compare(self.actual, self.expected), [])

    def test_a_difference_is_reported_with_a_diff(self):
        write(self.actual, "a.json", {"x": 2})
        write(self.expected, "a.json", {"x": 1})
        problems = check_golden.compare(self.actual, self.expected)
        self.assertEqual(len(problems), 1)
        self.assertIn('-  "x": 1', problems[0])
        self.assertIn('+  "x": 2', problems[0])

    def test_missing_and_stale_golden_files_are_reported(self):
        write(self.actual, "new.json", {})
        write(self.expected, "old.json", {})
        problems = check_golden.compare(self.actual, self.expected)
        self.assertTrue(any("new.json has no golden file" in p for p in problems))
        self.assertTrue(any("old.json has a golden file but was not compiled" in p for p in problems))

    def test_update_rewrites_and_prunes(self):
        write(self.actual, "new.json", {"k": 1})
        write(self.expected, "old.json", {})
        self.assertEqual(check_golden.compare(self.actual, self.expected, update=True), [])
        self.assertEqual(sorted(os.listdir(self.expected)), ["new.json"])
        self.assertEqual(check_golden.compare(self.actual, self.expected), [])


class SchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import jsonschema
        except ImportError:
            raise unittest.SkipTest("jsonschema is not installed")
        cls.validator = jsonschema.Draft7Validator(validator.load_schema())

    def body(self):
        return {
            "name": "r", "folderId": "f",
            "contents": {
                "schemaVersion": 1, "kind": "report",
                "pages": [{"id": "p", "name": "P"}],
                "elements": [{"id": "e", "kind": "text", "body": "hi"}],
                "layout": '<Page id="p"/>',
            },
        }

    def test_a_minimal_report_conforms(self):
        self.assertEqual(validator.errors_for(self.validator, self.body()), [])

    def test_the_theme_name_overlap_in_sigmas_schema_is_tolerated(self):
        body = self.body()
        body["contents"]["settings"] = {"theme": {"name": "Light"}}
        self.assertEqual(validator.errors_for(self.validator, body), [])

    def test_a_missing_required_field_is_caught(self):
        body = self.body()
        del body["folderId"]
        self.assertTrue(validator.errors_for(self.validator, body))

    def test_a_malformed_element_is_caught(self):
        body = self.body()
        body["contents"]["elements"][0] = {"id": "e", "kind": "text"}  # no body
        self.assertTrue(validator.errors_for(self.validator, body))

    def test_an_unknown_element_kind_is_caught(self):
        body = self.body()
        body["contents"]["elements"][0] = {"id": "e", "kind": "hologram"}
        self.assertTrue(validator.errors_for(self.validator, body))


if __name__ == "__main__":
    unittest.main()
