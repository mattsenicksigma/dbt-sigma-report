# dbt-sigma-report

Compose [Sigma reports](https://help.sigmacomputing.com/docs/manage-reports-as-code) from dbt macros instead of hand-writing Sigma's JSON. A report is a dbt model: it can `ref()` your dbt models and `source()`s, it can read the tables of your [Sigma data models](https://github.com/Matts52/dbt-sigma-data-models), it is reviewed like the rest of your project, and its compiled spec lands in `manifest.json` on `dbt parse`.

```sql
-- models/sigma_sales_dashboard.sql
{% set spec = sigma_report.simple_dashboard(
    name='Sales at a glance',
    subtitle='Bookings and orders, year to date',
    source=sigma_report.from_ref('stg_orders'),
    kpis=[
      {'value': 'Sum([Amount])', 'name': 'Revenue', 'format': sigma_report.format_currency()},
      {'value': 'Count()', 'name': 'Orders'},
    ],
    charts=[
      {'type': 'bar',   'x': 'region',  'y': 'Sum([Amount])', 'name': 'Revenue by region'},
      {'type': 'donut', 'category': 'segment', 'value': 'Sum([Amount])', 'name': 'Revenue by segment'},
    ],
    table_columns=['order_id', 'order_date', 'region', 'segment', 'amount'],
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
```

That is a title, a KPI band, two charts and a detail table, laid out on US Letter pages, in the Sigma look, from one model.

The package never calls Sigma. It composes JSON at parse time (no warehouse connection needed) and stores it on the model's `meta`. An optional script, [`scripts/export_reports.py`](#publishing-to-sigma), turns the manifest into files or pushes them to the Sigma API.

## Reports are not workbooks

A Sigma **report** is the paginated-document object: fixed pages (US Letter, A4, ...), elements placed at absolute pixel positions, headers and footers that repeat on every page, built for exporting and scheduling. A **workbook** is the interactive canvas (24-column grid, controls, tabs). The two have different code representations (`POST /v2/reports` with `kind: "report"` versus `POST /v2/workbooks`), and this package targets reports. If you want workbooks, see its sibling [`dbt-sigma-workbook`](https://github.com/Matts52/dbt-sigma-workbook); the macro vocabulary is deliberately similar.

Because a report is paginated, the package lays elements out for you with a simple vertical flow (title, KPI band, charts, table) and starts a new page when one fills up. See [Layout](#layout).

## Requirements

- dbt `>=1.6.0, <3.0.0`. Tested on dbt 1.12 and on dbt 2.0 (the Rust engine) in CI; see [dbt versions](#dbt-versions).
- Any adapter. The macros emit JSON, not SQL.
- To publish: a Sigma organization with reports as code (Beta), a Sigma connection to your warehouse, and an API client for the export script.

## Installation

Not on the dbt Package Hub yet; install from git in `packages.yml`:

```yaml
packages:
  - git: "https://github.com/mattsenicksigma/dbt-sigma-report.git"
    revision: main            # pin a tag or commit for reproducible builds
```

Then `dbt deps`. To read from Sigma data model tables, also install [`Matts52/dbt-sigma-data-models`](https://github.com/Matts52/dbt-sigma-data-models) (optional).

## Setup

Set project variables in `dbt_project.yml`:

```yaml
vars:
  sigma_connection_id: "<your-sigma-connection-id>"   # Sigma connection to your warehouse
  sigma_folder_id: "<your-sigma-folder-id>"           # folder new reports are created in
```

| Variable | Used for | Required |
| --- | --- | --- |
| `sigma_connection_id` | Warehouse sources. Or pass `connection_id=` per source. | When reading from the warehouse |
| `sigma_folder_id` | Where the report is created. Or pass `folder_id=` per report. | To create (not update) a report |
| `sigma_data_model_ids` | `{dbt_model_name: sigma_data_model_id}` for [`from_data_model`](#sources). | When reading from data models |
| `sigma_report_theme` | The project-wide [theme](#theming). | No |

`sigma_connection_id` and `sigma_folder_id` are the same names `dbt-sigma-data-models` and `dbt-sigma-workbook` use, so a project using several configures them once. Find the ids in Sigma (the connection's page; `GET /v2/files?typeFilters=folder` for folders).

## Quickstart

1. Create `models/sigma_sales_dashboard.sql` from the example above (adjust the `ref` and the columns).
2. Run `dbt parse`.
3. The report is in `target/manifest.json` at `nodes` -> `model.<project>.sigma_sales_dashboard` -> `config.meta.sigma_report`.
4. Write it out: `python dbt_packages/sigma_report/scripts/export_reports.py --out sigma_reports/`, or push it ([below](#publishing-to-sigma)).

Things worth knowing about the model:

- `materialize()` sets the model's `meta` via `config(meta=...)`, which replaces `meta` wholesale, so keep report models single-purpose.
- The body (`select 1 as report`) is a throwaway. By default the model is a view; `materialize(spec, materialized='ephemeral')` creates nothing in the warehouse.
- Pair the model with an [`exposures:`](integration_tests/models/exposures.yml) entry so `dbt ls -s +exposure:sales_dashboard` lists everything the report depends on.
- Column names in formulas are the names Sigma shows: `Sum([Amount])`, `[Order Date]`. A bare lowercase name such as `'order_date'` is title-cased the way Sigma title-cases warehouse columns.

## Layout

A report has **pages**. A page is a vertical stack of **blocks**, and a block is an **element** (full content width) or a **row** (a band of elements sharing the width). Each element has a height in pixels (`h=`, with a default per kind); widths come from the row it sits in.

```sql
{% set spec = sigma_report.report(
    name='Sales report',
    page_size='a4',                       -- letter (default) | legal | tabloid | a4 | a3 | screen | {width: .., height: ..}
    margin=40,
    header=[sigma_report.text('**Acme Corp** | Sales', key='header', h=32)],   -- repeats on every page
    footer=[sigma_report.text('Generated by dbt', key='footer', h=24)],
    pages=[
      sigma_report.page('Summary', [
        sigma_report.report_header('Sales summary', 'Hand-assembled from primitives'),
        sigma_report.row([sigma_report.stack([revenue, orders]), by_month], widths=[1, 2]),
        sigma_report.section('Mix', [pivot]),
      ]),
      sigma_report.page('Detail', [detail_table], paginate=true),
    ],
) %}
```

- `row([a, b, c])` shares the width equally; `widths=[2, 1]` are relative weights. Every element in a row is stretched to the tallest one's height.
- `stack([a, b])` is a vertical group that fits in one cell of a row (two KPIs beside a chart).
- `grid(elements, per_row=2)` turns a list of elements into rows.
- Content that does not fit a page **fails the build** with the overflow in pixels, so a clipped page can never ship silently. Add `paginate=true` to a `page()` and it continues on a new physical page instead (`Detail`, `Detail (2)`, ...), repeating the header and footer.
- Header and footer heights are subtracted from the content area, so panel content can never overlap page content.
- A table's row count is unknown at compile time, so you choose the height you reserve for it (`h=`). Size it to what fits the page, or use `paginate=true`.
- Pixel positions are validated in CI: nothing outside its page, nothing overlapping (`scripts/check_layout.py`, which you can run on your own manifest too).

## Components

Everything is a macro under `sigma_report.`; every public macro is documented with its arguments in [`macros/schema.yml`](macros/schema.yml).

| Layer | Macros |
| --- | --- |
| Report | `report`, `page`, `materialize` |
| Layout | `row`, `stack`, `grid`, `section`, `report_header` |
| Elements | `kpi`, `bar_chart`, `line_chart`, `area_chart`, `scatter_chart`, `pie_chart`, `donut_chart`, `table`, `pivot_table`, `text`, `title`, `heading`, `divider`, `image` |
| Composites | `simple_dashboard`, `simple_leaderboard`, `kpi_row`, `kpi_from_spec`, `chart_from_spec`, `facts_line`, `bullet_list` |
| Report presets | `simple_executive_summary`, `simple_period_review`, `simple_statement` |
| Sources | `from_ref`, `from_source`, `from_data_model`, `warehouse_table`, `data_model`, `element` |
| Fields | `field`, `format_currency`, `format_integer`, `format_percent`, `format_compact`, `format_number`, `format_date` |
| Escape hatches | `extend`, `raw` |
| Theme | `theme`, `color`, plus the `sigma_report_theme` var |

### Dashboards in one call

`simple_dashboard` is the general-purpose shape: title, KPI band, charts two to a row, optional detail table. Every part is optional. `simple_leaderboard` is a second one built from the same pieces: a KPI plus one ranked horizontal bar chart per dimension.

```sql
{% set spec = sigma_report.simple_leaderboard(
    name='Regional standings',
    source=sigma_report.from_ref('stg_orders'),
    dimensions=['region', 'segment'],
    measure='Sum([Amount])', measure_name='Revenue',
    measure_format=sigma_report.format_currency(),
) %}
```

Both take `report_args={...}`: any argument of `report()` (`page_size`, `orientation`, `margin`, `header`, `footer`, `theme`, `description`, `folder_id`, `report_id`).

KPI mappings take `value`, `name`, `format`, `compare_to` (compare against a target measure), `timeline` + `period` (compare the latest period with the one before), `trend` (sparkline), `direction` (`higher` / `lower` / `none`), `description`. Chart mappings take a `type` of `bar`, `line`, `area`, `scatter`, `pie` or `donut` plus that chart macro's arguments (`x`, `y`, `color`, `sort_by`, `stacking`, `labels`, ...).

### Report presets

Whole documents from data alone, each a thin layer over the same public macros as `simple_dashboard` (and each taking `report_args`):

| Preset | What it makes |
| --- | --- |
| `simple_executive_summary` | headline KPIs, one full-width chart, a few highlight bullets |
| `simple_period_review` | KPIs for the latest period against the one before (with sparklines), a trend, a breakdown per dimension, notes and actions |
| `simple_statement` | a statement or invoice: facts, a line-item table, a totals band, a footer note |

```sql
{% set spec = sigma_report.simple_period_review(
    name='Monthly review',
    source=sigma_report.from_ref('stg_orders'),
    date_field='order_date', period='month',
    kpis=[{'value': 'Sum([Amount])', 'name': 'Revenue'}, {'value': 'Count()', 'name': 'Orders'}],
    breakdowns=['region', 'segment'],
    notes=['Action: review SMB pricing'],
) %}
```

Reports have no per-viewer filters, so `simple_statement` describes whatever its `source` holds: point it at a model already limited to one customer, and loop in dbt to make one per customer.

### Building your own

`simple_dashboard` uses only public macros; when you outgrow it, write the same thing by hand. [`integration_tests/models/sigma_sales_report.sql`](integration_tests/models/sigma_sales_report.sql) is a runnable two-page example with header and footer panels, a pivot, a calculated column, a chart built on a table that is already on the page, and both escape hatches.

### Escape hatches

Sigma's schema has hundreds of options beyond what the macros model.

- `extend(element, {...})` deep-merges raw Sigma properties onto an element you built with a normal macro.
- `raw(kind, key, {...}, h=...)` makes an element of any kind the package has no macro for yet (`gauge-chart`, `combo-chart`, `embed`, `report-repeated-container`, ...). It still takes part in layout, id checks and validation.

Raw properties are not checked by the macros; `scripts/validate_against_sigma_schema.py` checks every compiled report against Sigma's published schema.

## Sources

| Macro | Reads from |
| --- | --- |
| `from_ref('stg_orders')` | a dbt model, seed or snapshot (calls `ref()`, so the report is downstream of it in the DAG) |
| `from_source('raw', 'orders')` | a dbt source (calls `source()`) |
| `from_data_model('my_model', 'orders')` | a table in a Sigma data model built with `sigma_data_models` |
| `warehouse_table([db, schema, table])` | any warehouse table by physical path |
| `element(table_element)` | another element already on the page |

A Sigma report refers to warehouse tables by physical path, but at parse time dbt cannot resolve other nodes' relations, so the path is built from `target.database` / `target.schema` and the model name. If your models build into other schemas, pass `schema=` per call, or override the one macro that decides this once:

```yaml
# dbt_project.yml
dispatch:
  - macro_namespace: sigma_report
    search_order: ['my_project', 'sigma_report']
```

```sql
-- macros/sigma_report_overrides.sql  (the name must be exactly `default__relation_path`)
{% macro default__relation_path(kind, name, database=none, schema=none, identifier=none) %}
  {% do return([database or target.database, schema or 'analytics', identifier or name]) %}
{% endmacro %}
```

`kind` is `'ref'` or `'source'`. A runnable example is in [`integration_tests/macros/overrides.sql`](integration_tests/macros/overrides.sql).

**Sigma data models.** `from_data_model` takes the dbt model that carries the data model, and the `key` the table was given in `sigma_data_models.table()`. Sigma assigns the data model's id when you create it, so record it once in the `sigma_data_model_ids` var; until then the report carries an `unresolved:<model>` placeholder that the export script refuses to push. The table's element id is derived from the same path `sigma_data_models` uses, so the two packages agree without coordinating.

## Theming

Defaults are Sigma's: the Neutral gray scale with the Blue accent, Inter type, rounded white cards with a hairline border, and Sigma's `superbloom` categorical palette for multi-series charts. Re-skin every report from `dbt_project.yml`:

```yaml
vars:
  sigma_report_theme:
    hue: Emerald                       # swap the accent scale
    base: Slate                        # swap the gray scale
    colors: {primary: "#0b6e4f"}       # or pin any single token to your brand color
    categorical: ["#0b6e4f", "#f2a900", "#3d5a80"]   # series palette (or a Sigma palette name)
    fonts: {text: Inter, data: Inter}
    border_radius: round               # square | round | pill
    cards: true                        # false = no card border around data elements
```

| Key | Choices |
| --- | --- |
| `base` | `Neutral` (default), `Stone`, `Zinc`, `Slate` |
| `hue` | `Blue` (default), `Neutral`, `Indigo`, `Violet`, `Emerald`, `Teal`, `Green`, `Rose`, `Orange`, `Amber` |
| `colors` | any of the tokens below |
| `categorical`, `sequential`, `diverging` | a Sigma palette name; `categorical` also takes a list of hex colors |

Tokens: `canvas`, `ink`, `body`, `muted`, `hairline`, `fill`, `series_grey` (from the base); `primary`, `tint`, `edge`, `series`, `series_mid` (from the hue); `surface`, `success`, `danger`, `warning` and their `_fill` variants. The scales are Sigma's own design-system scales.

Precedence, lowest to highest: package defaults, the `sigma_report_theme` var, then `theme={...}` on a single `report()`. Each level is deep-merged, so overriding one thing keeps the rest. A per-report theme recolors elements that were built before `report()` ran (colors are late-bound), and an unknown hue, base or token fails at `dbt parse` rather than silently falling back.

## Publishing to Sigma

```bash
python dbt_packages/sigma_report/scripts/export_reports.py --out sigma_reports/   # one <model>.json per report
python dbt_packages/sigma_report/scripts/export_reports.py --check                # offline sanity checks
python dbt_packages/sigma_report/scripts/export_reports.py --push --dry-run       # validate against your Sigma org
python dbt_packages/sigma_report/scripts/export_reports.py --push                 # create / update
```

The script needs only the Python standard library. Pushing needs [API credentials](https://help.sigmacomputing.com/docs/generate-api-client-credentials) in `SIGMA_BASE_URL` (your cloud's API URL), `SIGMA_CLIENT_ID` and `SIGMA_CLIENT_SECRET`.

- First push creates the report (`POST /v2/reports`). Note the `reportId` Sigma returns and pass it as `report_id=` (or `report_args={'report_id': ...}`) from then on: the next push replaces that report's contents in place (`PUT /v2/reports/{id}/contents`), so the report keeps its URL, schedules and sharing.
- `--dry-run` sends `dryRun: true`, which validates formulas, sources and layout without saving. Run it against your own organization after any change to what elements look like.
- The script refuses to push an `unresolved:` data model id or the all-zero placeholder ids used in this repository's tests.

Reports as code is a Beta Sigma feature; its API can change.

## dbt versions

The package declares `dbt >=1.6.0, <3.0.0`, and CI runs the whole integration suite on **both dbt 1.12 and dbt 2.0** (`dbt-core==2.0.0rc8`), producing byte-identical output (the same golden files pass on both). What dbt 2 conformance took:

- **Macro arguments are documented and checked.** `macros/schema.yml` lists every public macro's arguments with types from dbt's grammar (`string`, `bool`, `int`, `any`, `list[any]`, `dict[string,any]`). dbt 2 validates it against the macro signatures, and the integration project sets `flags: validate_macro_args: true` and runs `dbt parse --warn-error`, so a drift between the two fails CI on either version. (dbt >= 1.10 warns on a mismatch; dbt 2 is stricter.)
- **Portable Jinja only.** No `modules.re` or other Python-only escapes: strings are parsed with `split`, mutation uses `namespace`, and dict keys that collide with dict methods (`values`, `items`) are read with `['values']`.
- **Config goes in `meta`.** The spec is attached with `config(meta=...)`, not a custom config key.
- **Dispatch is by adapter prefix.** The one override point, `relation_path`, uses `adapter.dispatch`, which works the same on both engines.
- **No warehouse needed to compose.** Everything resolves at parse time, which is also what makes `dbt parse` on dbt 2 enough to produce reports.

## Testing

```bash
pip install -r ci/requirements-dbt1.txt        # or ci/requirements-dbt2.txt for dbt 2.x
bash scripts/run_integration_tests_duckdb.sh   # the whole suite; DuckDB, no credentials
python -m unittest discover -s scripts -p "test_*.py"
```

The integration suite is a real dbt project ([`integration_tests/`](integration_tests)) that compiles six reports from a seed, then:

1. asserts the shape of every compiled report (field names, cross-references, theme flow, ids from vars);
2. checks pixel geometry from the layout XML (inside the page, nothing overlapping);
3. compares each report with a committed golden JSON file (output is deterministic: every id is a hash of a stable path);
4. validates each against Sigma's request schema, extracted from the public OpenAPI document;
5. runs 36 inputs that must fail `dbt parse`, each with the exact error it must raise;
6. re-runs the assertions with different Sigma ids to prove every id flows from the vars.

CI (`.github/workflows/integration-tests.yml`) runs all of it on dbt 1.x and dbt 2.x.

## Coverage and limits

An initial version aimed at dashboards.

- **Validated against Sigma's schema, not rendered in CI.** The request schema check, the geometry check and the golden files run in CI. CI has no Sigma credentials, so how a report *looks* in Sigma, and whether Sigma accepts the formulas against your data, is checked by `--push --dry-run` against your own organization. Panel sizing in particular is an assumption: header and footer heights are subtracted from the content area, which is safe (no overlap) but may leave more white space than Sigma needs.
- **Modeled elements**: KPI, bar / line / area / scatter / pie / donut charts, table, pivot table, text, divider, image. Not modeled (use [`raw`](#escape-hatches)): combo, waterfall, funnel, gauge, sankey, treemap and box charts, maps, input tables, buttons, embeds, repeated containers, conditional formatting, reference marks, trellis.
- **No controls.** Reports have no interactive controls in Sigma's code representation.
- **Layout is a vertical flow** of rows and stacks. There is no free x/y placement and no nesting of rows inside stacks beyond one level; `raw` elements still sit in the same flow.
- **Heights are yours to choose.** Table and text height depend on data and content that the compiler cannot see.
- **Source paths** use `target.database` / `target.schema` unless overridden (see [Sources](#sources)).
- **Formulas are strings.** The package cannot check them against your data; the dry run does.
- One `sigma_report` per model; other `meta` keys are lost to `materialize()`.

## More

- [`docs/design.md`](docs/design.md): why the package is shaped this way, a critique of how composable it really is, what that review changed, and the recipe for adding an element.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`AGENTS.md`](AGENTS.md): working on the package.

## License

MIT, see [`LICENSE`](LICENSE).
