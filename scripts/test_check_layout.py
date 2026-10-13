"""Unit tests for scripts/check_layout.py: the geometry checks must actually catch geometry mistakes."""
import unittest

import check_layout


def element_line(e):
    # (id, x, y, width, height) or (id, x, y, width, height, flow)
    flow = ' flow="%s"' % e[5] if len(e) > 5 else ""
    return '  <Element elementId="%s" x="%s" y="%s" width="%s" height="%s"%s/>' % (e[:5] + (flow,))


def spec(page_elements, panels=None, margin=10, width=200, height=300):
    lines = "\n".join(element_line(e) for e in page_elements)
    layout = '<?xml version="1.0" encoding="utf-8"?>\n<Page id="p1">\n%s\n</Page>\n' % lines
    contents = {"config": {"margin": margin, "pageWidth": width, "pageHeight": height}, "layout": layout}
    if panels:
        contents["panels"] = [{"id": "hdr", "type": "header", "config": {"height": 40}, "pages": ["p1"]}]
        contents["layout"] += '<Panel id="hdr" type="header">\n%s\n</Panel>\n' % "\n".join(
            element_line(e) for e in panels)
    return {"contents": contents}


class LayoutTests(unittest.TestCase):
    def test_clean_page(self):
        self.assertEqual(check_layout.violations("r", spec([("a", 0, 0, 180, 100), ("b", 0, 120, 180, 100)])), [])

    def test_touching_edges_are_not_an_overlap(self):
        self.assertEqual(check_layout.violations("r", spec([("a", 0, 0, 90, 100), ("b", 90, 0, 90, 100)])), [])

    def test_overlap_is_caught(self):
        problems = check_layout.violations("r", spec([("a", 0, 0, 100, 100), ("b", 50, 50, 100, 100)]))
        self.assertTrue(any("a overlaps b" in p for p in problems))

    def test_paginated_element_last_on_its_page_is_clean(self):
        self.assertEqual(check_layout.violations("r", spec([("a", 0, 0, 180, 50), ("t", 0, 70, 180, 100, "paginated")])), [])

    def test_something_below_a_paginated_element_is_caught(self):
        problems = check_layout.violations("r", spec([("t", 0, 0, 180, 100, "paginated"), ("a", 0, 120, 180, 50)]))
        self.assertTrue(any("t is paginated but a sits at or below it" in p for p in problems))

    def test_unknown_flow_is_caught(self):
        problems = check_layout.violations("r", spec([("t", 0, 0, 180, 100, "scrolling")]))
        self.assertTrue(any("unknown flow 'scrolling'" in p for p in problems))

    def test_paginated_element_in_a_panel_is_caught(self):
        problems = check_layout.violations("r", spec([("a", 0, 0, 100, 100)], panels=[("t", 0, 0, 180, 40, "paginated")]))
        self.assertTrue(any("panel cannot hold" in p for p in problems))

    def test_wider_than_the_content_area_is_caught(self):
        problems = check_layout.violations("r", spec([("a", 0, 0, 181, 10)]))
        self.assertTrue(any("outside" in p for p in problems))

    def test_taller_than_the_content_area_is_caught(self):
        problems = check_layout.violations("r", spec([("a", 0, 0, 100, 281)]))
        self.assertTrue(any("outside" in p for p in problems))

    def test_header_space_is_taken_from_the_page(self):
        # 300 - 2*10 margin - 40 header = 240 available
        self.assertEqual(check_layout.violations("r", spec([("a", 0, 0, 100, 240)], panels=[("h", 0, 0, 180, 40)])), [])
        problems = check_layout.violations("r", spec([("a", 0, 0, 100, 241)], panels=[("h", 0, 0, 180, 40)]))
        self.assertTrue(any("outside" in p for p in problems))

    def test_panel_elements_must_fit_the_panel(self):
        problems = check_layout.violations("r", spec([("a", 0, 0, 100, 100)], panels=[("h", 0, 0, 180, 41)]))
        self.assertTrue(any("header panel" in p for p in problems))

    def test_degenerate_boxes_are_caught(self):
        problems = check_layout.violations("r", spec([("a", 0, 0, 0, 10)]))
        self.assertTrue(any("non-positive" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
