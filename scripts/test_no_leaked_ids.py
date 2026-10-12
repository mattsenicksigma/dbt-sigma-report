"""Fail if the repository contains something that looks like a real Sigma id, an email address or a local path.

Tests use placeholder ids (`00000000-0000-0000-0000-0000000000NN`) and example addresses; anything else that
looks like a UUID, an email outside example.com, or a home-directory path is treated as a leak. Git history is
permanent, so the fix for a leak that was already committed is not a follow-up commit.
"""
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SKIP_DIRS = {".git", "target", "dbt_packages", "logs", "duckdb", "__pycache__", ".venv", ".claude"}
SKIP_SUFFIXES = (".gz", ".duckdb", ".wal", ".pyc")
# Local files that are never committed: a worktree's `.git` pointer, and dbt's per-user id.
SKIP_FILES = {".git", ".user.yml"}

UUID = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I)
PLACEHOLDER_UUID = re.compile(r"^00000000-0000-0000-0000-0{11}\d$")
EMAIL = re.compile(r"\b[\w.+-]+@([\w-]+\.)+[a-z]{2,}\b", re.I)
LOCAL_PATH = re.compile(r"/(Users|home)/[a-z0-9._-]+/", re.I)
# The only non-example addresses that may appear: none.
ALLOWED_EMAIL_DOMAINS = {"example.com"}


def repo_files():
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if not name.endswith(SKIP_SUFFIXES) and name not in SKIP_FILES:
                yield os.path.join(folder, name)


class LeakTests(unittest.TestCase):
    def test_no_leaked_ids_emails_or_paths(self):
        leaks = []
        for path in repo_files():
            if os.path.basename(path) == os.path.basename(__file__):
                continue
            try:
                with open(path, encoding="utf-8") as handle:
                    text = handle.read()
            except UnicodeDecodeError:
                continue
            rel = os.path.relpath(path, ROOT)
            for match in UUID.finditer(text):
                if not PLACEHOLDER_UUID.match(match.group(0)):
                    leaks.append("%s: uuid %s" % (rel, match.group(0)))
            for match in EMAIL.finditer(text):
                if match.group(0).split("@")[1].lower() not in ALLOWED_EMAIL_DOMAINS:
                    leaks.append("%s: email %s" % (rel, match.group(0)))
            for match in LOCAL_PATH.finditer(text):
                leaks.append("%s: local path %s" % (rel, match.group(0)))
        self.assertEqual(leaks, [], "\n".join(leaks))


if __name__ == "__main__":
    unittest.main()
