"""Unit tests for scripts/generate_kinds.py: the element-kind registry must match Sigma's schema."""
import unittest

import check_layout
import export_reports
import generate_kinds


class KindsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.kinds = generate_kinds.kinds(generate_kinds.load_schema())

    def test_the_committed_registry_is_up_to_date(self):
        self.assertEqual(generate_kinds.main(["--check"]), 0)

    def test_every_kind_the_package_builds_is_in_the_registry(self):
        built = ["text", "divider", "image", "table", "pivot-table", "kpi-chart", "bar-chart", "line-chart", "area-chart",
                 "scatter-chart", "pie-chart", "donut-chart", "combo-chart", "waterfall-chart", "box-chart", "funnel-chart",
                 "gauge-chart", "treemap-chart", "sankey-chart", "point-map", "region-map", "geography-map", "progress",
                 "button", "embed"]
        self.assertEqual([k for k in built if k not in self.kinds], [])

    def test_required_properties_include_the_channels_the_macros_fill(self):
        self.assertIn("yAxis", self.kinds["combo-chart"][0])
        self.assertEqual(sorted(self.kinds["funnel-chart"][0]), ["columns", "id", "kind", "series", "source", "stage"])
        self.assertIn("url", self.kinds["embed"][0])

    def test_properties_are_a_superset_of_required(self):
        for kind, (required, props) in self.kinds.items():
            self.assertTrue(set(required) <= set(props), kind)


class BookkeepingTests(unittest.TestCase):
    def test_underscore_keys_never_reach_sigma(self):
        spec = {"name": "r", "contents": {}, "reportId": "x", "_overlap_ok": ["a"]}
        self.assertEqual(export_reports.request_body(spec), {"name": "r", "contents": {}})

    def test_pinned_overlaps_are_allowed_by_the_geometry_check_only_when_flagged(self):
        layout = ('<Page id="p"><Element elementId="a" x="0" y="0" width="100" height="100"/>'
                  '<Element elementId="b" x="50" y="0" width="100" height="100"/></Page>')
        spec = {"contents": {"config": {"margin": 0, "pageWidth": 400, "pageHeight": 400}, "layout": layout}}
        self.assertTrue(any("overlaps" in p for p in check_layout.violations("r", spec)))
        spec["_overlap_ok"] = ["b"]
        self.assertEqual(check_layout.violations("r", spec), [])


if __name__ == "__main__":
    unittest.main()
