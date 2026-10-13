# Integration tests

A real dbt project that uses the package (`packages.yml: local: ../`) against DuckDB. Run it with `bash scripts/run_integration_tests_duckdb.sh` from the repository root; no credentials, no network beyond `dbt deps`.

| Model | Exercises |
| --- | --- |
| `sigma_sales_simple` | the smallest `simple_dashboard`: one KPI, one chart |
| `sigma_sales_untitled` | `simple_dashboard(show_title=false)`: no title, subtitle or rule |
| `sigma_last_days_dashboard` | `last_days` + `date_column` on a KPI, a chart and a `table_pivot`, alongside an unwindowed KPI and chart, with `filter_by_value` on top |
| `sigma_sales_dashboard` | a full `simple_dashboard`: three KPIs (one against a target), four chart kinds, a sorted, paginated (`table_paginate`) detail table; continues onto a second page |
| `simple_leaderboard` | ranked horizontal bars per dimension |
| `preset_executive_summary` | `simple_executive_summary`: three KPIs (one against plan), a headline chart, highlights |
| `preset_period_review` | `simple_period_review`: period-over-period KPIs with sparklines, a trend, two breakdowns, notes |
| `preset_statement` | `simple_statement`: facts, a totals band, a paginated line-item table last on the page, a footer note with page numbers |
| `sigma_paginated_tables` | `paginate=true` on a table and on a pivot (`flow="paginated"`, each last on its page) and `page_numbers=true` |
| `sigma_footer_page_numbers` | `page_numbers=true` next to a footer of your own |
| `sigma_sales_report` | the primitives: A4, header and footer panels, a `row` with a `stack`, pivot, calculated column, a chart built on a table, `extend`, `raw`, a per-report theme, two pages |
| `sigma_sales_from_data_model` | a source that is a table of a Sigma data model (composed by `sigma_sales_model` with `sigma_data_models`) |
| `sigma_sales_long_form` | content-sized heights: a wrapping title, text in a narrow cell, `rows=`, `h='fill'` |
| `sigma_flexible_layout` | the layout tree (rows and stacks nested three deep), `flex` weights shared 2:1, `at()` with overlap, `table_pages` over three pages, and the wider chart family (combo with a secondary axis, treemap, waterfall, funnel, gauge, sankey, box, a region map, progress, embed) |
| `sigma_orders_from_source` | a dbt source, the `screen` page size, and a project `relation_path` override |

What each step checks is listed in the header of [`scripts/run_integration_tests_duckdb.sh`](../scripts/run_integration_tests_duckdb.sh). In short:

- `macros/assert_reports.sql` - the compiled shape: ids, cross-references, theme flow, vars.
- `scripts/check_layout.py` - pixel geometry from the layout XML.
- `expected/*.json` - golden files for every report (`UPDATE_GOLDEN=1` to accept new output; review the diff).
- `schema/create_report_request.schema.json.gz` - Sigma's `POST /v2/reports` request schema, extracted from its public OpenAPI document (`scripts/validate_against_sigma_schema.py --refresh <openapi.json>` regenerates it).
- `macros/assert_rejected.sql` + `negative_cases.txt` - inputs that must fail `dbt parse`, with the exact error each must raise.

Connection, folder and data model ids are project vars (`SIGMA_CONNECTION_ID`, `SIGMA_FOLDER_ID`, `SIGMA_DATA_MODEL_ID` in the environment override the placeholder defaults), and the assertions are re-run with different ids to prove nothing is baked in. No real Sigma id belongs in this repository.
