#!/usr/bin/env python3
"""Validate every compiled report against Sigma's published request schema for `POST /v2/reports`.

    python scripts/validate_against_sigma_schema.py --manifest target/manifest.json

The schema (integration_tests/schema/create_report_request.schema.json.gz) is extracted from Sigma's
public OpenAPI document:

    https://assets.sigmacomputing.com/openapi/public-rest-api/sigma-computing-public-rest-api.json

Refresh it with `--refresh path/to/openapi.json` after Sigma changes the API. Needs `jsonschema`.
"""
import argparse
import gzip
import json
import os
import sys

from export_reports import load_reports, request_body

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.join(HERE, "..", "integration_tests", "schema", "create_report_request.schema.json.gz")


def extract_schema(openapi):
    """The standalone `POST /v2/reports` request schema, with only the component schemas it references."""
    components = openapi["components"]["schemas"]
    root = openapi["paths"]["/v2/reports"]["post"]["requestBody"]["content"]["application/json"]["schema"]
    needed = set()

    def walk(node):
        if isinstance(node, dict):
            ref = node.get("$ref")
            if ref and ref.split("/")[-1] not in needed:
                needed.add(ref.split("/")[-1])
                walk(components[ref.split("/")[-1]])
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(root)
    schema = dict(root)
    schema["components"] = {"schemas": {name: components[name] for name in sorted(needed)}}
    return schema


def anyof(node):
    """Sigma's OpenAPI document spells TypeScript unions as `oneOf`, but its alternatives overlap (the theme
    name "Light" is both a plain string and an enum member), which strict `oneOf` rejects. `anyOf` is what
    the document means."""
    if isinstance(node, dict):
        return {("anyOf" if k == "oneOf" else k): anyof(v) for k, v in node.items()}
    if isinstance(node, list):
        return [anyof(v) for v in node]
    return node


def load_schema():
    with gzip.open(SCHEMA_PATH, "rt") as handle:
        return anyof(json.load(handle))


def errors_for(validator, body):
    """Human-readable errors. A failed union reports its closest alternative, not every alternative."""
    from jsonschema.exceptions import best_match

    out = []
    for error in validator.iter_errors(body):
        best = best_match([error]) if error.context else error
        path = "/".join(str(p) for p in error.absolute_path) or "<root>"
        out.append("%s: %s" % (path, best.message[:300]))
    return sorted(out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", default="target/manifest.json")
    parser.add_argument("--refresh", metavar="OPENAPI_JSON", help="rewrite the bundled schema from an OpenAPI file")
    args = parser.parse_args(argv)

    if args.refresh:
        with open(args.refresh) as handle:
            schema = extract_schema(json.load(handle))
        with gzip.open(SCHEMA_PATH, "wt") as handle:
            json.dump(schema, handle)
        print("refreshed " + SCHEMA_PATH)
        return 0

    try:
        import jsonschema
    except ImportError:
        raise SystemExit("jsonschema is required: pip install jsonschema")
    validator = jsonschema.Draft7Validator(load_schema())
    reports = load_reports(args.manifest)
    if not reports:
        raise SystemExit("no sigma_report models found in " + args.manifest)
    bad = 0
    for name, spec in sorted(reports.items()):
        problems = errors_for(validator, request_body(spec))
        for problem in problems:
            print("%s: %s" % (name, problem), file=sys.stderr)
        bad += bool(problems)
        if not problems:
            print("%s conforms to the Sigma request schema" % name)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
