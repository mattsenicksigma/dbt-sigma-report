# Contributing

Issues and pull requests are welcome.

## Getting set up

```bash
python -m venv .venv && . .venv/bin/activate
pip install -r ci/requirements-dbt1.txt
bash scripts/run_integration_tests_duckdb.sh   # the whole suite; no credentials needed
python -m unittest discover -s scripts -p "test_*.py"
```

CI runs the suite on dbt 1.x and dbt 2.x, and both must pass. [`AGENTS.md`](AGENTS.md) lists the conventions and dbt Jinja gotchas (no `**kwargs`, deterministic ids, late-bound colors, dbt 2 portability); read it before writing macros.

## Changing behavior

- Adding, renaming or removing a macro argument: update [`macros/schema.yml`](macros/schema.yml), or the build fails.
- Adding an element: follow "Adding an element" in [`docs/design.md`](docs/design.md), then use it in an integration report and assert on it.
- A new size, margin, font size or calibration number is a project setting (`macros/core/settings.sql`), not a literal in a macro.
- After refreshing the bundled Sigma schema, run `python scripts/generate_kinds.py` (CI fails on a stale `kinds.sql`).
- Expected compile errors get a negative test in `assert_rejected.sql` and a line in `negative_cases.txt`.
- If the change alters the emitted JSON, run `UPDATE_GOLDEN=1 bash scripts/run_integration_tests_duckdb.sh` and review the golden diff.
- If the change alters what elements look like, run `python scripts/export_reports.py --push --dry-run` against a Sigma organization and mention the result in the PR.

## Please do not commit

Real Sigma ids, hosts, email addresses, credentials or local paths. `scripts/test_no_leaked_ids.py` rejects them; use obviously fake values in examples.

## Pull requests

Keep them focused, say what changed and why, and note anything you could not test (for example, rendering in Sigma).
