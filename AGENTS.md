# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## What this is

`dbt-sigma-report` composes [Sigma reports](https://help.sigmacomputing.com/docs/manage-reports-as-code) (the paginated-document object, `POST /v2/reports`) from dbt macros. The spec is pure compile-time JSON, attached to a dbt model's `meta.sigma_report` via `sigma_report.materialize()` and read from `manifest.json`. The macros never call Sigma or the warehouse. `scripts/export_reports.py` is the optional last mile (write files / push to the Sigma API).

Read `README.md` for usage and `docs/design.md` for the reasoning, the composability critique and the extension recipe.

## Commands

```bash
pip install -r ci/requirements-dbt1.txt        # dbt 1.x;  ci/requirements-dbt2.txt for dbt 2.x
bash scripts/run_integration_tests_duckdb.sh   # the whole suite (DuckDB, no credentials)
python -m unittest discover -s scripts -p "test_*.py"
```

The script honors `DBT`, `PYTHON`, `PARSE_FLAGS` and `UPDATE_GOLDEN=1`. CI runs it on dbt 1.x and on dbt 2.x, both with `PARSE_FLAGS=--warn-error`. **Both must pass**; dbt 2.x is the stricter of the two.

Live validation against Sigma (needs credentials, creates nothing): `python scripts/export_reports.py --push --dry-run`. Do this after any change to what elements look like; no offline check can replace it.

## Layout

- `macros/core` ids, string/dict helpers, `fail()`. `macros/theme` design tokens + late-bound colors. `macros/data` sources, fields, formats. `macros/elements` one file per element family plus `escape_hatches`. `macros/layout` pixel flow (`row`, `stack`, `flow`) + layout XML. `macros/report` `page`/`report`/`materialize`. `macros/components` composites and `simple_*`.
- `macros/schema.yml` documents every public macro. **dbt validates it against the signatures** (`validate_macro_args`); adding, renaming or removing an argument means updating it, or `dbt parse --warn-error` fails on both dbt 1 and dbt 2. Use only types from dbt's grammar: `string`, `bool`, `int`, `any`, `list[any]`, `dict[string,any]`.
- `integration_tests/` is a real dbt project (`packages.yml: local: ../`). `assert_reports.sql` = positive assertions, `assert_rejected.sql` = expected compile errors, each listed in `negative_cases.txt` with the message it must raise (the script checks the two agree). `expected/*.json` = golden copies of every compiled report; after an intended change to emitted JSON, run `UPDATE_GOLDEN=1 bash scripts/run_integration_tests_duckdb.sh` and review the diff.
- `scripts/` holds the Python tooling and its tests: `export_reports.py`, `check_layout.py` (pixel geometry), `check_golden.py`, `validate_against_sigma_schema.py` (against `integration_tests/schema/*.gz`, extracted from Sigma's OpenAPI document; `--refresh` regenerates it).

## Conventions and gotchas

- **Elements are dicts.** Keys starting with `_` are private (`_h`, `_row`, `_stack`, `_source`, ...) and stripped by `report()`. Never put a private key in output another way.
- **Reports are pixel-laid-out, workbooks are grid-laid-out.** Elements carry a height (`_h`); widths come from `row()`. Do not add a width to an element macro.
- **dbt Jinja limits.** No `**kwargs`. Dict keys named `items` / `keys` / `values` collide with dict methods: use `el['values']`, never `el.values`. `{% set %}` inside a `for` doesn't leak: use `namespace`. Comments (`{# #}`) can't sit inside a `{% ... %}` tag. No `modules.re` (not portable to dbt 2): parse strings with `split`. Use `is false`, not `is sameas false`.
- **Dispatch is by adapter prefix.** A project overrides `relation_path` by defining `default__relation_path` and listing itself first in `dispatch:`; a macro named after the project is never found.
- **Every id is a hash of a stable path** (`freeze_id`). Never use timestamps, counters or `run_started_at`. Column ids include the *role* (channel) because Sigma allows a column on one channel only.
- **Unqualified formula references** (`Sum([Amount])`) get a qualified passthrough column (`[table/Amount]`) added by `add_column`; that is Sigma's own export convention. Keep it.
- **Colors are late-bound**: element macros call `color_ref('primary')` (a marker), never `color()` (a hex), so a report-level `theme=` reaches them. `report()` resolves the markers.
- **Overflow is an error, never a clip.** `flow` fails with the overflow in pixels unless the page has `paginate=true`.
- **Never commit a real Sigma id, email address, internal host or local path.** Connection, folder and data model ids come from project vars (`SIGMA_*` environment variables with `00000000-0000-0000-0000-0000000000NN` placeholder defaults); use `<your-...-id>` placeholders in docs. `scripts/test_no_leaked_ids.py` enforces it in CI.
- **Sigma names win.** Use Sigma's own field names in emitted JSON; check the OpenAPI schema before inventing a field.
- Fail with `sigma_report.fail('macro_name', 'message')` so errors carry the macro name; add a matching `assert_*_rejected` negative test.
- Dependencies in `ci/` are pinned to versions at least three days old. Keep it that way when refreshing.

## Adding an element

See "Adding an element" in `docs/design.md`. In short: a macro that calls `new_element`, `add_column(s)` (with a `role`), stores `_source`, applies `card_style`; then document it in `macros/schema.yml`, use it in an integration report, assert on it, and dry-run it against Sigma.
