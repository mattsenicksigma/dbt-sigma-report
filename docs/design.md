# Design notes and a critique of the abstraction

The reasoning behind the package's shape, followed by an honest look at how composable and abstract it really is, what that review changed, and what is still open.

## The shape

```
sources ─┐
fields  ─┼─► elements ─► blocks (rows / stacks) ─► pages ─► report ─► materialize ─► manifest.json ─► (export script) ─► Sigma
theme   ─┘                                                  ▲
                                          header / footer panels
```

Five decisions carry most of the design.

1. **A report is a dbt model; the spec is compile-time JSON.** The macros never touch Sigma or the warehouse. The spec is stored in `config.meta.sigma_report`, so it is in `manifest.json` after `dbt parse`, diffable in a PR, and visible to any tool that reads the manifest. This mirrors `dbt-sigma-data-models` and `dbt-sigma-workbook`, so a project using several has one mental model and one set of vars (`sigma_connection_id`, `sigma_folder_id`).
2. **Everything is a plain dict.** A source, a field, an element, a row and a whole report are dicts in (nearly) Sigma's own shape. They can be built by any macro, held in variables, passed around, mutated and inspected in tests. There are no classes and no hidden state.
3. **Layers only depend downward.** Elements know nothing about pages or widths; layout (`row`, `stack`, `flow`) knows nothing about element kinds; composites (`simple_dashboard`, `simple_leaderboard`, `report_header`, `grid`, ...) are written using nothing but the public macros; `report()` is the only place that knows the output format. A composite is therefore also documentation: it is what you would write yourself.
4. **Sigma's shape wins over invention.** Field names (`xAxis.columnId`, `comparisonColumn`, `holeValue`), the passthrough-column convention, panels, the layout XML and the theme settings are Sigma's. Where the package adds a private field (`_h`, `_row`, `_source`) it is stripped before output.
5. **Reports are paginated documents, so layout is a flow with a hard fail.** A report page has a fixed pixel size. Rather than ask authors to compute `x`/`y`, the package stacks blocks and gives each element a *height*; widths come from the row it sits in, so one chart works full-width or as half of a pair without being rebuilt. Content that does not fit a page fails the build (with the overflow in pixels) unless the page opts into `paginate=true`. A clipped page is the worst failure a paginated report has, so it is the one that cannot happen silently.

Deterministic ids follow from (1): every id is a hash of a stable path (kind + name/key for elements, formula + role for columns), so identical input gives byte-identical output and re-deploys are idempotent. That is also what makes golden-file testing possible.

## What the Sigma schema taught the design

The first thing the research turned up was that "reports" and "workbooks" are different objects with different representations:

| | Workbook | Report |
| --- | --- | --- |
| Endpoint | `POST /v2/workbooks` | `POST /v2/reports` |
| Layout | 24-column grid (`gridColumn` / `gridRow`) | absolute pixels (`x` / `y` / `width` / `height`) |
| Page | responsive canvas | fixed `pageWidth` x `pageHeight`, `margin` |
| Chrome | tabs, controls | header / footer **panels** that repeat per page |
| Elements | includes controls and containers | no controls; adds `report-repeated-container` |

So the sibling workbook package's grid placement could not be reused, and the layout layer here is new. The schema is also the oracle: CI extracts the `POST /v2/reports` request schema from Sigma's public OpenAPI document and validates every compiled report against it (the document spells TypeScript unions as `oneOf` with overlapping alternatives, so the validator reads them as `anyOf`; one test pins that).

## Is it as composable and abstracted as it can be?

Short answer: composable enough that the common cases need no escape and the escape exists for the rest; not as abstract as it could be, deliberately. The review, by principle:

### What holds up

- **Closure.** Every constructor returns the same kind of thing it accepts: sources go into elements, elements into rows, rows into pages, lists of any of those flatten one level (`flatten`), and a chart can take another element as its `source`. `simple_dashboard` is written with the public API only; nothing in it is privileged. That is tested: the integration reports are built three ways (composite, primitives, data-model source) and go through the same validators.
- **One place per concern.** Colors live in the theme; ids in `freeze_id`; where dbt nodes live in `relation_path`; page geometry in `layout.sql`; the output shape in `report()`. Changing the layout tags for a new API generation touches one file.
- **Late binding where it matters.** Element colors are markers resolved when the report is assembled, so a report-level `theme=` recolors elements built earlier (a test pins this). Without it every element macro would need a `theme` argument.
- **Width is not an element property.** Keeping width out of elements is what lets `row`, `stack` and `grid` recombine the same elements freely.
- **Fail early, name the line.** Empty pages, duplicate names, colliding ids, bad tokens, malformed fields, bad page sizes and overflowing content all fail at `dbt parse` with the macro that caught them. 62 kinds of invalid input are pinned by tests, each with the exact message.

### Where it fell short, and what was done about it

| Weakness found in review | Status |
| --- | --- |
| A row could only hold elements, so "two KPIs beside a chart" needed hand-placing, i.e. leaving the library. | **Fixed, twice.** First `stack()` (a vertical group in one row cell) - which was still a fixed two-level layout. Then the layout was rewritten as a **recursive tree**: rows and stacks nest to any depth. See "The layout is a tree" below. |
| Calling `simple_dashboard` and `simple_leaderboard` repeated 12 lines of report assembly. | **Fixed**: extracted `report_from_args`, public, so a user's own composite ends the same way. |
| No way to set a Sigma option the macros do not expose, or use an element kind they do not model. | **Fixed**: `extend()` (deep-merge raw properties) and `raw()` (any kind, still laid out and id-checked). Both are tested and used in the integration report. |
| Where a dbt node's table lives is unknowable at parse time, and was a hard-coded `target.schema` guess. | **Fixed**: one dispatched macro, `relation_path`, that a project overrides once; tested with a real override. (A first draft documented the override with the wrong macro name; the test is what caught it.) |
| A `stack` placed directly on a page, or a row nested in a row, would produce garbage. | **Superseded**: both are now valid. `row`, `stack`, `flex` and the page flow validate what *is* invalid (`at()` or `page_break()` inside a row or stack) and name the fix. |
| The ceiling: layout was a flow with fixed heights, tables could not run over several pages, most chart kinds were unmodeled, and `raw()` was unchecked JSON. | **Fixed** by [seven changes](#what-made-it-less-fixed) below. |
| Fixed pixel heights: a 28px-high H1 clipped a long title (seen in Sigma's own render of a pushed example), and a "table of N hundred rows" could not be expressed. | **Fixed**: titles, headings and text are sized from their content and the cell width (resolved in the layout flow, where the width is finally known); tables take `rows=` or `h='fill'`; page background is white. Found by exporting the pushed report to PDF, which is now the recommended way to check a report visually. |
| Chart macros repeat a long argument list. | **Accepted**: dbt's Jinja has no `**kwargs`. The repetition is confined to `xy_chart` / `part_to_whole` (internal), which the public macros feed, and `extend()` covers the long tail. |
| `simple_dashboard` accepts data (mappings), a second calling convention next to the macros. | **Accepted**: it is a convenience over the primitives, with `kpi_from_spec` / `chart_from_spec` as public dispatchers. Nothing else depends on the mapping convention. |

### What made it less fixed

1. **The layout is a tree.** A block is an element, a `row`, a `stack`, an `at()`-pinned element or a `page_break()`. Rows and stacks nest to any depth, and the same two primitives express every grid shape. The page is just the root of the tree, with pagination. Width flows *down* (a row divides its width by weight); height is *measured up* (each block's natural height from its children) and then *shared out*.
2. **Measure, then place.** The engine has two recursive passes: `measure(block, width)` returns the natural height and flex weight (nothing mutated, so it is safe to call from any level), and `place(block, box)` lays it out. Width-dependent heights (wrapping text) resolve inside `measure`, where the width is finally known. The rewrite reproduced the previous engine's output byte for byte on the existing reports (the one golden that changed was the leaderboard, whose chart height now follows the unified `chart_h` default), which is what let the old behaviour be kept while the model changed underneath.
3. **Flexible heights.** `flex(block, weight, min)` (and `h='fill'`) take a share of leftover height in proportion to their weight, like CSS `flex-grow`. A block that contains a flexible child is flexible, so "fill the page" works through any nesting.
4. **Absolute placement as an explicit, checked exception.** `at()` pins an element and takes no flow room. Overlap is a mistake unless declared (`overlap=true`), and that declaration travels to the geometry check via a `_`-prefixed key that never reaches Sigma.
5. **Tables over several pages.** Found by experiment, not documentation: a Sigma table *element* has no pagination or row-limit property (expansion is a layout attribute, a separate feature), but a `RowNumber()` column plus a number-range filter shows an exact row window, and Sigma accepts a hidden column for the filter. `table_pages` stacks windows with page breaks. Rendered in Sigma: 90 rows, 30 per page, windows correct, hidden column hidden, true total in every summary bar. Sigma also offers native expansion (`flow="paginated"` on the layout entry, `table(paginate=true)`), found later and verified live (a 70-row table continued onto a second page): it needs no row budget, but must be the last block on its page, so windows remain the answer when content follows the table or page boundaries must be fixed.
6. **Every constant is a setting.** Element heights, margins, gaps, type sizes and the text / table calibration constants come from the `sigma_report_settings` project var (unknown keys fail), with per-call arguments winning. The calibration numbers are exactly the ones most likely to be wrong for a different theme or font, so they are the ones a user can now correct without touching the package.
7. **The element set is a registry, and `raw()` is checked against it.** `scripts/generate_kinds.py` builds `kinds.sql` from Sigma's own schema (29 kinds, with required and allowed properties); `raw()` and `extend()` reject an unknown kind, a missing required property or a misspelt one at `dbt parse`. CI fails if the registry is stale. Thirteen more kinds got typed macros (combo with secondary axis, waterfall, box, funnel, gauge, treemap, sankey, three maps, progress, button, embed) built on one `channel_element` assembler, so a new kind is a list of channel descriptions rather than a new macro body.

One deliberate non-change: `fill`/`flex` shares space *beyond* natural heights (flex-grow semantics, not flex-basis 0). That keeps a flexible chart at least as tall as it would have been fixed, and a test pins the 2:1 split on the extra.

### Still open (not done, on purpose or for lack of information)

- **No free-form drag layout.** Everything is a row, a stack or a pinned element. There is still no row *spanning* (a cell covering two rows of its neighbour), though nesting covers most cases; and `at()` takes single elements, not groups.
- **Height estimates are heuristics.** Text height comes from character counts and font size, and table height from a measured 20px row plus ~130px of chrome. Both were calibrated against a real Sigma PDF export and are deliberately generous, but they are not Sigma's own numbers. They are now settings, but they are still guesses.
- **Multi-page tables need a row budget.** `table_pages` cannot see the data, so it shows `rows_per_page * pages` rows and relies on the summary bar to reveal a shortfall. A compile-time count would need a warehouse query, which the package deliberately never makes.
- **Panel sizing is an assumption.** Header and footer heights are subtracted from the content area. If Sigma places panels inside the margin the reports will have extra white space, never overlap. The rendered examples had the footer where expected, but the margin question is not settled.
- **Some typed charts are schema-checked, not rendered.** Rendered in Sigma: combo, treemap, funnel, waterfall, gauge, box. Sankey, the three maps, progress, button and embed are checked against Sigma's request schema in CI but not yet seen drawn.
- **Formulas are opaque strings.** A small formula builder (`sigma_report.sum('amount')`) would help typos but not semantics, and would have to track Sigma's function set.
- **Sigma-side identity.** Ids are stable at compile time, but Sigma assigns its own `reportId` on create; the package does not read it back. `report_id=` updates an existing report (a full replace of its contents) but there is no drift detection.
- **Rendering is checked by schema and geometry in CI, and by eye only manually.** CI has no Sigma credentials, so appearance is not covered by automated tests; the manual loop (push, export to PDF, look) is what found the clipped title and the wrong table calibration.
- **Theme coverage.** Sigma's report `settings.theme.overrides` documents more fields than the package exposes (`elementBorder`, for one); the theme var covers colors, palettes, fonts and corner radius. Anything else can be added with `report(...)['contents']['settings']` after the fact, or requested as a theme key.

## Adding an element (the extension recipe)

Every element macro follows one pattern; a new one is 20-40 lines. This one is illustrative (look up the real field names for the kind in Sigma's schema first):

```jinja
{% macro gauge(source, value, name=none, key=none, h=200, style=none) %}
{% set source = sigma_report.resolve_source(source, 'gauge') %}                          {# 1. normalize the source #}
{% set el = sigma_report.new_element('gauge-chart', 'gauge', key, name, h) %}             {# 2. id + pixel height #}
{% set cols = [] %}
{% set value_id = sigma_report.add_column(cols, el['id'], value, source, 'gauge', 'value') %}  {# 3. fields -> columns #}
{% do el.update({"source": source, "columns": cols, "value": {"columnId": value_id}, "_source": source}) %}
{% do sigma_report.apply_titles(el, name, none) %}
{% do el.update(sigma_report.compact({"style": sigma_report.card_style(style)})) %}       {# 4. house style #}
{% do return(el) %}
{% endmacro %}
```

For a kind whose channels are plain "this field feeds that property" mappings (most of Sigma's charts), skip the macro body entirely and call `channel_element(kind, where, source, name, key, h, description, channels, style, extra)` with a list of `{prop, fields, shape}` descriptions; `gauge_chart` and `funnel_chart` are each four lines of channel descriptions. `_source` is what lets other elements be built on this one; `role` (the last argument to `add_column`) is the Sigma channel the column feeds, and is part of the column id because Sigma allows a column on one channel only. Then add the macro to `macros/schema.yml` (dbt checks it against the signature on both dbt 1 and dbt 2), a report in `integration_tests/models/` that uses it, an assertion in `assert_reports.sql`, and regenerate the golden files (`UPDATE_GOLDEN=1 bash scripts/run_integration_tests_duckdb.sh`, then review the diff). `scripts/validate_against_sigma_schema.py` checks the shape against Sigma's schema for free.
