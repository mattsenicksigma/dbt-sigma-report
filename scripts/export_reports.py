#!/usr/bin/env python3
"""Export the reports compiled by dbt-sigma-report from manifest.json, and optionally push them to Sigma.

    python scripts/export_reports.py --out sigma_reports/             # write one JSON file per report
    python scripts/export_reports.py --check                          # offline sanity checks only
    python scripts/export_reports.py --push --dry-run                 # validate against your Sigma org
    python scripts/export_reports.py --push                           # create / update the reports

The package itself never talks to Sigma: `dbt parse` leaves each report's request body in the manifest at
`nodes.<model>.config.meta.sigma_report`. This script is the optional last mile. Standard library only.

Pushing needs API credentials (https://help.sigmacomputing.com/docs/generate-api-client-credentials):

    SIGMA_BASE_URL       e.g. https://aws-api.sigmacomputing.com (your cloud's API URL)
    SIGMA_CLIENT_ID
    SIGMA_CLIENT_SECRET

A report whose spec has a `reportId` is updated in place (`PUT /v2/reports/{id}/contents`, a full
replace of its contents); otherwise a new report is created (`POST /v2/reports`). `--dry-run` sends
`dryRun: true` to the create endpoint, which validates formulas, sources and layout without saving.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

PLACEHOLDER_PREFIX = "unresolved:"
PLACEHOLDER_ID_PREFIX = "00000000-0000-0000-0000-"


def load_reports(manifest_path, select=None):
    """Return {model_name: spec} for every model that carries `meta.sigma_report`."""
    with open(manifest_path) as handle:
        manifest = json.load(handle)
    reports = {}
    for node in manifest.get("nodes", {}).values():
        if node.get("resource_type") != "model":
            continue
        meta = (node.get("config") or {}).get("meta") or node.get("meta") or {}
        if "sigma_report" in meta:
            if select and node["name"] not in select:
                continue
            reports[node["name"]] = meta["sigma_report"]
    if select:
        missing = sorted(set(select) - set(reports))
        if missing:
            raise SystemExit("no compiled report for: " + ", ".join(missing))
    return reports


def request_body(spec):
    """The `POST /v2/reports` body: the spec without the package's own bookkeeping (`reportId`, and any
    `_`-prefixed key such as `_overlap_ok`, which only the geometry check reads)."""
    return {k: v for k, v in spec.items() if k != "reportId" and not k.startswith("_")}


def check_spec(name, spec, for_push=False):
    """Offline checks a deploy would want to pass before it ever calls Sigma. Returns a list of problems."""
    problems = []
    contents = spec.get("contents") or {}
    if not spec.get("name"):
        problems.append("no name")
    if contents.get("schemaVersion") != 1 or contents.get("kind") != "report":
        problems.append("contents must have schemaVersion 1 and kind 'report'")
    page_ids = {p["id"] for p in contents.get("pages", [])}
    if not page_ids:
        problems.append("no pages")
    element_ids = {e["id"] for e in contents.get("elements", [])}
    if len(element_ids) != len(contents.get("elements", [])):
        problems.append("duplicate element ids")
    layout = contents.get("layout") or ""
    for element_id in element_ids:
        if 'elementId="%s"' % element_id not in layout:
            problems.append("element %s is not placed in the layout" % element_id)
    for page_id in page_ids:
        if 'id="%s"' % page_id not in layout:
            problems.append("page %s has no <Page> in the layout" % page_id)
    for panel in contents.get("panels", []):
        if not set(panel.get("pages", [])) <= page_ids:
            problems.append("panel %s refers to an unknown page" % panel["id"])
    if any(k.startswith("_") for e in contents.get("elements", []) for k in e):
        problems.append("a private `_` key leaked into an element")
    if for_push:
        if not spec.get("folderId") and not spec.get("reportId"):
            problems.append("no folderId (set the `sigma_folder_id` var or pass folder_id=)")
        text = json.dumps(spec)
        if PLACEHOLDER_PREFIX in text:
            problems.append("contains an unresolved placeholder (see `sigma_data_model_ids`)")
        if PLACEHOLDER_ID_PREFIX in text:
            problems.append("contains a placeholder id (supply real Sigma ids via vars / SIGMA_* env)")
    return problems


class SigmaClient:
    def __init__(self, base_url, client_id, client_secret):
        self.base_url = base_url.rstrip("/")
        self.token = self._token(client_id, client_secret)

    def _call(self, method, path, body=None, form=None, token=None):
        data, headers = None, {"Accept": "application/json"}
        if form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        elif body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = "Bearer " + token
        request = urllib.request.Request(self.base_url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            raise RuntimeError("%s %s -> HTTP %s: %s" % (method, path, error.code, error.read().decode(errors="replace")))
        return json.loads(payload) if payload else {}

    def _token(self, client_id, client_secret):
        reply = self._call("POST", "/v2/auth/token", form={
            "grant_type": "client_credentials", "client_id": client_id, "client_secret": client_secret})
        return reply["access_token"]

    def create(self, spec, dry_run):
        body = request_body(spec)
        if dry_run:
            body["dryRun"] = True
        return self._call("POST", "/v2/reports", body=body, token=self.token)

    def update(self, report_id, spec):
        return self._call("PUT", "/v2/reports/%s/contents" % report_id,
                          body={"contents": spec["contents"]}, token=self.token)


def push(reports, dry_run, client):
    for name, spec in sorted(reports.items()):
        if dry_run or not spec.get("reportId"):
            reply = client.create(spec, dry_run)
            print("%s %s: %s" % (name, "validated" if dry_run else "created", reply.get("url") or reply.get("reportId") or "ok"))
        else:
            client.update(spec["reportId"], spec)
            print("%s updated: %s" % (name, spec["reportId"]))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", default="target/manifest.json")
    parser.add_argument("--out", help="write <model>.json request bodies into this directory")
    parser.add_argument("--select", nargs="*", help="only these model names")
    parser.add_argument("--check", action="store_true", help="offline sanity checks; non-zero exit on a problem")
    parser.add_argument("--push", action="store_true", help="send the reports to Sigma")
    parser.add_argument("--dry-run", action="store_true", help="with --push: validate only, create nothing")
    args = parser.parse_args(argv)

    reports = load_reports(args.manifest, args.select)
    if not reports:
        raise SystemExit("no sigma_report models found in %s (did you run `dbt parse`?)" % args.manifest)

    failed = False
    for name, spec in sorted(reports.items()):
        problems = check_spec(name, spec, for_push=args.push)
        for problem in problems:
            print("%s: %s" % (name, problem), file=sys.stderr)
        failed = failed or bool(problems)
    if failed:
        raise SystemExit(1)

    if args.out:
        os.makedirs(args.out, exist_ok=True)
        for name, spec in sorted(reports.items()):
            path = os.path.join(args.out, name + ".json")
            with open(path, "w") as handle:
                json.dump(request_body(spec), handle, indent=2, sort_keys=True)
                handle.write("\n")
            print("wrote " + path)
    if args.check:
        print("%d report(s) passed the offline checks" % len(reports))
    if args.push:
        missing = [v for v in ("SIGMA_BASE_URL", "SIGMA_CLIENT_ID", "SIGMA_CLIENT_SECRET") if not os.environ.get(v)]
        if missing:
            raise SystemExit("set " + ", ".join(missing) + " to push")
        client = SigmaClient(os.environ["SIGMA_BASE_URL"], os.environ["SIGMA_CLIENT_ID"], os.environ["SIGMA_CLIENT_SECRET"])
        push(reports, args.dry_run, client)
    if not (args.out or args.check or args.push):
        parser.print_usage()
        print("nothing to do: pass --out, --check or --push")
    return 0


if __name__ == "__main__":
    sys.exit(main())
