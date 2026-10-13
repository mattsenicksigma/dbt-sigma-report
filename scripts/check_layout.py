#!/usr/bin/env python3
"""Check the pixel geometry of every compiled report: nothing outside its page, nothing overlapping.

    python scripts/check_layout.py --manifest target/manifest.json

A report is a paginated document, so a mistake in the layout is a clipped or overprinted page, and it
cannot be caught by looking at the JSON. This parses `contents.layout` and checks, per `<Page>`:

  * every element sits inside the content area (page size minus margin, minus the header / footer panels);
  * no two elements overlap (except elements pinned with `at(..., overlap=true)`, listed in the spec's
    `_overlap_ok`);

and, per `<Panel>`, that its elements fit the panel's width and height. Exit status is non-zero on any
violation, so it can gate CI.
"""
import argparse
import sys
import xml.etree.ElementTree as ET

from export_reports import load_reports


def violations(name, spec):
    """Return a list of geometry problems in one report spec."""
    contents = spec["contents"]
    config = contents["config"]
    margin, width, height = config["margin"], config["pageWidth"], config["pageHeight"]
    panels = {p["id"]: p for p in contents.get("panels", [])}
    overlap_ok = set(spec.get("_overlap_ok", []))
    panel_space = sum(p["config"]["height"] for p in panels.values())
    content_w = width - 2 * margin
    content_h = height - 2 * margin - panel_space

    root = ET.fromstring("<root>" + contents["layout"].split("?>", 1)[-1] + "</root>")
    problems = []
    for node in root:
        boxes = [
            (e.get("elementId"), float(e.get("x")), float(e.get("y")), float(e.get("width")), float(e.get("height")))
            for e in node.findall("Element")
        ]
        if node.tag == "Page":
            limit_w, limit_h, label = content_w, content_h, "page " + node.get("id")
        elif node.tag == "Panel":
            limit_w, limit_h, label = content_w, panels[node.get("id")]["config"]["height"], "%s panel" % node.get("type")
        else:
            problems.append("%s: unexpected layout root <%s>" % (name, node.tag))
            continue
        for element_id, x, y, w, h in boxes:
            if x < 0 or y < 0 or w <= 0 or h <= 0:
                problems.append("%s: %s: %s has a non-positive or negative box" % (name, label, element_id))
            if x + w > limit_w + 0.01 or y + h > limit_h + 0.01:
                problems.append("%s: %s: %s ends at (%g, %g) outside the %gx%g area" % (name, label, element_id, x + w, y + h, limit_w, limit_h))
        for i, a in enumerate(boxes):
            for b in boxes[i + 1:]:
                if a[0] in overlap_ok or b[0] in overlap_ok:  # pinned with at(..., overlap=true)
                    continue
                if a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]:
                    problems.append("%s: %s: %s overlaps %s" % (name, label, a[0], b[0]))
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", default="target/manifest.json")
    args = parser.parse_args(argv)
    reports = load_reports(args.manifest)
    if not reports:
        raise SystemExit("no sigma_report models found in " + args.manifest)
    bad = False
    for name, spec in sorted(reports.items()):
        problems = violations(name, spec)
        for problem in problems:
            print(problem, file=sys.stderr)
        bad = bad or bool(problems)
        if not problems:
            print("%s: layout is clean" % name)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
