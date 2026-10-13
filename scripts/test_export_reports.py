"""Unit tests for scripts/export_reports.py, including a push against a fake Sigma API (no network)."""
import copy
import json
import os
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

import export_reports


def good_spec():
    return {
        "name": "Sales",
        "folderId": "folder-1",
        "contents": {
            "schemaVersion": 1,
            "kind": "report",
            "pages": [{"id": "p1", "name": "Sales"}],
            "elements": [{"id": "e1", "kind": "text", "body": "hi"}],
            "config": {"margin": 48, "pageWidth": 816, "pageHeight": 1056},
            "layout": '<?xml version="1.0" encoding="utf-8"?>\n<Page id="p1">\n  <Element elementId="e1" x="0" y="0" width="10" height="10"/>\n</Page>\n',
        },
    }


def manifest_for(specs):
    nodes = {}
    for name, spec in specs.items():
        nodes["model.p.%s" % name] = {"resource_type": "model", "name": name, "config": {"meta": {"sigma_report": spec}}}
    nodes["model.p.plain"] = {"resource_type": "model", "name": "plain", "config": {"meta": {}}}
    return {"nodes": nodes}


def schedule(title="Weekly"):
    return {
        "target": [{"email": "finance@example.com"}],
        "schedule": {"cronSpec": "0 8 * * 1", "timezone": "UTC"},
        "configV2": {"title": title, "messageBody": "", "exportAttachments": [{"formatOptions": {"type": "PDF", "layout": "portrait"}}]},
    }


class FakeSigma(BaseHTTPRequestHandler):
    calls = []
    existing_schedules = []

    def log_message(self, *args):
        pass

    def _reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode() if length else ""
        FakeSigma.calls.append((self.command, self.path, self.headers.get("Authorization"), raw))
        if self.path == "/v2/auth/token":
            return self._reply(200, {"access_token": "tok"}) if "client_secret=s3cret" in raw else self._reply(401, {"message": "bad"})
        if self.headers.get("Authorization") != "Bearer tok":
            return self._reply(401, {"message": "no token"})
        if self.path == "/v2/reports":
            return self._reply(200, {"reportId": "r-new", "url": "https://sigma.example/r-new"})
        if self.path.startswith("/v2/reports/") and self.path.endswith("/contents"):
            return self._reply(200, {})
        if self.path.split("?")[0].endswith("/schedules"):
            if self.command == "GET":
                if "page=2" in self.path:
                    return self._reply(200, {"entries": FakeSigma.existing_schedules[1:], "nextPage": None})
                return self._reply(200, {"entries": FakeSigma.existing_schedules[:1], "nextPage": "2"})
            return self._reply(200, {"scheduledNotificationId": "s-new"})
        if "/schedules/" in self.path and self.command == "PATCH":
            return self._reply(200, {})
        return self._reply(404, {})

    do_POST = do_PUT = do_GET = do_PATCH = _handle


class ExportTests(unittest.TestCase):
    def test_load_reports_reads_meta_and_skips_other_models(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "manifest.json")
            with open(path, "w") as fh:
                json.dump(manifest_for({"a": good_spec(), "b": good_spec()}), fh)
            self.assertEqual(sorted(export_reports.load_reports(path)), ["a", "b"])
            self.assertEqual(sorted(export_reports.load_reports(path, select=["a"])), ["a"])
            with self.assertRaises(SystemExit):
                export_reports.load_reports(path, select=["nope"])

    def test_request_body_drops_report_id(self):
        spec = dict(good_spec(), reportId="r1")
        self.assertNotIn("reportId", export_reports.request_body(spec))

    def test_request_body_drops_schedules(self):
        spec = dict(good_spec(), schedules=[schedule()])
        self.assertNotIn("schedules", export_reports.request_body(spec))

    def test_schedule_problems_are_caught(self):
        spec = dict(good_spec(), schedules=[schedule("A"), schedule("A")])
        self.assertTrue(any("distinct" in p for p in export_reports.check_spec("a", spec)))
        bad = schedule()
        bad["schedule"]["cronSpec"] = "daily"
        bad["target"] = []
        problems = export_reports.check_spec("a", dict(good_spec(), schedules=[bad]))
        self.assertTrue(any("cron" in p for p in problems) and any("no recipients" in p for p in problems))
        gated = schedule()
        gated["configV2"]["conditionOptions"] = {"type": "workbook", "condition": {"type": "isNotEmpty", "elementId": "ghost"}}
        self.assertTrue(any("not in the report" in p for p in export_reports.check_spec("a", dict(good_spec(), schedules=[gated]))))
        self.assertEqual(export_reports.check_spec("a", dict(good_spec(), schedules=[schedule()])), [])

    def test_good_spec_has_no_problems(self):
        self.assertEqual(export_reports.check_spec("a", good_spec()), [])

    def test_unplaced_element_is_caught(self):
        spec = good_spec()
        spec["contents"]["elements"].append({"id": "e2", "kind": "text", "body": "x"})
        self.assertTrue(any("e2 is not placed" in p for p in export_reports.check_spec("a", spec)))

    def test_missing_page_in_layout_is_caught(self):
        spec = good_spec()
        spec["contents"]["pages"].append({"id": "p2", "name": "Two"})
        self.assertTrue(any("p2 has no <Page>" in p for p in export_reports.check_spec("a", spec)))

    def test_duplicate_ids_and_private_keys_are_caught(self):
        spec = good_spec()
        spec["contents"]["elements"].append({"id": "e1", "kind": "text", "body": "x", "_h": 3})
        problems = export_reports.check_spec("a", spec)
        self.assertTrue(any("duplicate element ids" in p for p in problems))
        self.assertTrue(any("private" in p for p in problems))

    def test_panel_pointing_at_unknown_page_is_caught(self):
        spec = good_spec()
        spec["contents"]["panels"] = [{"id": "h", "type": "header", "pages": ["ghost"], "config": {"height": 1}}]
        self.assertTrue(any("unknown page" in p for p in export_reports.check_spec("a", spec)))

    def test_push_refuses_placeholders_and_missing_folder(self):
        spec = good_spec()
        spec["contents"]["elements"][0]["source"] = {"dataModelId": "unresolved:model"}
        self.assertTrue(any("unresolved placeholder" in p for p in export_reports.check_spec("a", spec, for_push=True)))
        spec = good_spec()
        spec["folderId"] = "00000000-0000-0000-0000-000000000002"
        self.assertTrue(any("placeholder id" in p for p in export_reports.check_spec("a", spec, for_push=True)))
        spec = good_spec()
        del spec["folderId"]
        self.assertTrue(any("no folderId" in p for p in export_reports.check_spec("a", spec, for_push=True)))
        # the same specs are fine offline
        self.assertEqual(export_reports.check_spec("a", spec, for_push=False), [])

    def test_main_writes_files(self):
        with tempfile.TemporaryDirectory() as d:
            manifest = os.path.join(d, "manifest.json")
            with open(manifest, "w") as fh:
                json.dump(manifest_for({"a": dict(good_spec(), reportId="r1")}), fh)
            out = os.path.join(d, "out")
            export_reports.main(["--manifest", manifest, "--out", out, "--check"])
            with open(os.path.join(out, "a.json")) as fh:
                written = json.load(fh)
            self.assertEqual(written["name"], "Sales")
            self.assertNotIn("reportId", written)

    def test_main_fails_on_a_bad_spec(self):
        spec = good_spec()
        spec["contents"]["layout"] = '<Page id="p1"/>'
        with tempfile.TemporaryDirectory() as d:
            manifest = os.path.join(d, "manifest.json")
            with open(manifest, "w") as fh:
                json.dump(manifest_for({"a": spec}), fh)
            with self.assertRaises(SystemExit):
                export_reports.main(["--manifest", manifest, "--check"])


class PushTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), FakeSigma)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = "http://127.0.0.1:%d" % cls.server.server_port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        FakeSigma.calls.clear()

    def client(self, secret="s3cret"):
        return export_reports.SigmaClient(self.url, "id", secret)

    def test_create_posts_the_body_without_report_id(self):
        export_reports.push({"a": dict(good_spec())}, dry_run=False, client=self.client())
        method, path, auth, raw = FakeSigma.calls[-1]
        self.assertEqual((method, path, auth), ("POST", "/v2/reports", "Bearer tok"))
        body = json.loads(raw)
        self.assertEqual(body["name"], "Sales")
        self.assertNotIn("dryRun", body)

    def test_dry_run_sends_dry_run_and_never_updates(self):
        export_reports.push({"a": dict(good_spec(), reportId="r1")}, dry_run=True, client=self.client())
        method, path, _, raw = FakeSigma.calls[-1]
        self.assertEqual((method, path), ("POST", "/v2/reports"))
        body = json.loads(raw)
        self.assertTrue(body["dryRun"])
        self.assertNotIn("reportId", body)

    def test_report_id_updates_contents_in_place(self):
        spec = dict(good_spec(), reportId="r1")
        export_reports.push({"a": spec}, dry_run=False, client=self.client())
        method, path, _, raw = FakeSigma.calls[-1]
        self.assertEqual((method, path), ("PUT", "/v2/reports/r1/contents"))
        self.assertEqual(json.loads(raw), {"contents": spec["contents"]})

    def test_the_spec_is_not_mutated(self):
        spec = good_spec()
        before = copy.deepcopy(spec)
        export_reports.push({"a": spec}, dry_run=True, client=self.client())
        self.assertEqual(spec, before)

    def test_schedules_follow_the_report_and_match_by_title(self):
        FakeSigma.existing_schedules = [
            {"scheduledNotificationId": "s-old", "configV2": {"title": "Weekly"}},
            {"scheduledNotificationId": "s-other", "configV2": {"title": "Monthly"}},
        ]
        spec = dict(good_spec(), schedules=[schedule("Monthly"), schedule("Daily")])
        export_reports.push({"a": spec}, dry_run=False, client=self.client())
        calls = [(m, p) for m, p, _, _ in FakeSigma.calls if "/schedules" in p or p == "/v2/reports"]
        self.assertEqual(calls[0], ("POST", "/v2/reports"))
        self.assertIn(("GET", "/v2/reports/r-new/schedules"), calls)
        self.assertIn(("GET", "/v2/reports/r-new/schedules?page=2"), calls)
        self.assertIn(("PATCH", "/v2/reports/r-new/schedules/s-other"), calls)
        self.assertIn(("POST", "/v2/reports/r-new/schedules"), calls)
        self.assertNotIn("DELETE", [m for m, _ in calls])
        self.assertFalse(any(p.endswith("s-old") for _, p in calls))  # unmentioned schedules are left alone

    def test_dry_run_never_touches_schedules(self):
        export_reports.push({"a": dict(good_spec(), schedules=[schedule()])}, dry_run=True, client=self.client())
        self.assertFalse(any("/schedules" in p for _, p, _, _ in FakeSigma.calls))

    def test_bad_credentials_raise(self):
        with self.assertRaises(RuntimeError):
            self.client(secret="wrong")


if __name__ == "__main__":
    unittest.main()
