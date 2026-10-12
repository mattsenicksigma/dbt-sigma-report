#!/usr/bin/env python3
"""Compare exported report JSON with the golden copies in integration_tests/expected/.

    python scripts/check_golden.py --actual DIR            # fail on any difference
    python scripts/check_golden.py --actual DIR --update   # accept the current output (review the diff!)

The compiled specs are deterministic (every id is a hash of a stable path), so the exact JSON is
committed. A change to what the macros emit then shows up in a pull request as a diff of real Sigma JSON.
"""
import argparse
import difflib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXPECTED = os.path.join(HERE, "..", "integration_tests", "expected")


def canonical(path):
    with open(path) as handle:
        return json.dumps(json.load(handle), indent=2, sort_keys=True) + "\n"


def compare(actual_dir, expected_dir, update=False):
    """Returns a list of problems (empty = identical). With `update`, rewrites the golden files instead."""
    problems = []
    actual = {f for f in os.listdir(actual_dir) if f.endswith(".json")}
    expected = {f for f in os.listdir(expected_dir) if f.endswith(".json")} if os.path.isdir(expected_dir) else set()
    if update:
        os.makedirs(expected_dir, exist_ok=True)
        for name in sorted(actual):
            with open(os.path.join(expected_dir, name), "w") as handle:
                handle.write(canonical(os.path.join(actual_dir, name)))
        for name in sorted(expected - actual):
            os.remove(os.path.join(expected_dir, name))
        return []
    for name in sorted(actual - expected):
        problems.append("%s has no golden file (run with UPDATE_GOLDEN=1 to create it)" % name)
    for name in sorted(expected - actual):
        problems.append("%s has a golden file but was not compiled" % name)
    for name in sorted(actual & expected):
        now = canonical(os.path.join(actual_dir, name))
        then = canonical(os.path.join(expected_dir, name))
        if now != then:
            diff = difflib.unified_diff(then.splitlines(), now.splitlines(), "expected/" + name, "actual/" + name, lineterm="", n=2)
            problems.append("%s differs from its golden file:\n%s" % (name, "\n".join(list(diff)[:60])))
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--actual", required=True)
    parser.add_argument("--expected", default=EXPECTED)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args(argv)
    problems = compare(args.actual, args.expected, args.update)
    for problem in problems:
        print(problem, file=sys.stderr)
    if not problems:
        print("golden files %s" % ("updated" if args.update else "match"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
