{# Correctness checks for the compiled report specs, run with `dbt run-operation assert_reports`.

   They assert the *shape* of what lands in manifest.json - the field names, nesting and cross-references
   the request body of Sigma's `POST /v2/reports` requires - not merely that compilation succeeded.
   Pixel geometry (nothing outside the page, nothing overlapping) is checked in Python by
   scripts/check_layout.py, which can parse the layout XML; the request schema is checked by
   scripts/validate_against_sigma_schema.py. #}


{% macro _ok(condition, message) %}
{% if not condition %}
  {% do exceptions.raise_compiler_error('ASSERTION FAILED: ' ~ message) %}
{% endif %}
{% endmacro %}


{% macro _spec_of(model_name) %}
{% for node in graph.nodes.values() %}
  {% if node.resource_type == 'model' and node.name == model_name %}
    {% do return(node.config.meta.sigma_report) %}
  {% endif %}
{% endfor %}
{% do exceptions.raise_compiler_error('ASSERTION FAILED: model ' ~ model_name ~ ' has no sigma_report meta') %}
{% endmacro %}


{# Every key anywhere in a structure, so leaked private keys can be caught. #}
{% macro _all_keys(value, acc) %}
{% if value is mapping %}
  {% for k in value.keys() %}
    {% do acc.append(k) %}
    {% do sigma_report_integration_tests._all_keys(value[k], acc) %}
  {% endfor %}
{% elif value is sequence and value is not string %}
  {% for item in value %}
    {% do sigma_report_integration_tests._all_keys(item, acc) %}
  {% endfor %}
{% endif %}
{% endmacro %}


{# Column ids an element refers to, from every channel that carries them. #}
{% macro _column_refs(value, acc) %}
{% if value is mapping %}
  {% for k in value.keys() %}
    {% if k == 'columnId' and value[k] is string %}{% do acc.append(value[k]) %}
    {% elif k == 'columnIds' %}{% for c in value[k] %}{% do acc.append(c['columnId'] if c is mapping else c) %}{% endfor %}
    {% elif k in ['order', 'values'] and value[k] is sequence and value[k] is not string and not (k == 'values' and value.get('kind') == 'list') %}{% for c in value[k] %}{% if c is string %}{% do acc.append(c) %}{% endif %}{% endfor %}
    {% elif k == 'column' and value[k] is string %}{% do acc.append(value[k]) %}
    {% elif k == 'by' and value.get('direction') %}{% do acc.append(value[k]) %}
    {% endif %}
    {% if k != 'columns' %}{% do sigma_report_integration_tests._column_refs(value[k], acc) %}{% endif %}
  {% endfor %}
{% elif value is sequence and value is not string %}
  {% for item in value %}
    {% do sigma_report_integration_tests._column_refs(item, acc) %}
  {% endfor %}
{% endif %}
{% endmacro %}


{# First element of `kind` whose title text (or, for a plain-string name, the name; a button's `text`) matches `title`;
   `title` none matches any. #}
{% macro _find(elements, kind, title) %}
{% for el in elements %}
  {% if el.kind == kind %}
    {% set shown = el.name.text if el.get('name') is mapping else (el.get('name') if el.get('name') is not none else el.get('text')) %}
    {% set shown = shown if shown is not none else '' %}
    {% if title is none or shown == title %}
      {% do return(el) %}
    {% endif %}
  {% endif %}
{% endfor %}
{% do exceptions.raise_compiler_error('ASSERTION FAILED: no ' ~ kind ~ ' titled ' ~ title) %}
{% endmacro %}


{# The text element whose body contains `snippet` (text elements have no name to match on). #}
{% macro _find_text(elements, snippet) %}
{% for el in elements %}
  {% if el.kind == 'text' and snippet in el.body %}
    {% do return(el) %}
  {% endif %}
{% endfor %}
{% do exceptions.raise_compiler_error('ASSERTION FAILED: no text containing ' ~ snippet) %}
{% endmacro %}


{# True when some text element's body contains `needle`. #}
{% macro _text_has(elements, needle) %}
{% for el in elements %}
  {% if el.kind == 'text' and needle in el.body %}{% do return(true) %}{% endif %}
{% endfor %}
{% do return(false) %}
{% endmacro %}

{# The layout line that places element `id` (the first match), or none. #}
{% macro _layout_line(layout, id) %}
{% for line in layout.split('\n') %}
  {% if 'elementId="' ~ id ~ '"' in line %}{% do return(line) %}{% endif %}
{% endfor %}
{% do return(none) %}
{% endmacro %}


{# The y coordinate of the first layout line for element `id`. #}
{% macro _layout_y(layout, id) %}
{% do return(sigma_report_integration_tests._layout_line(layout, id).split(' y="')[1].split('"')[0] | int) %}
{% endmacro %}


{% macro _count(elements, kind) %}
{% set n = namespace(count=0) %}
{% for el in elements %}{% if el.kind == kind %}{% set n.count = n.count + 1 %}{% endif %}{% endfor %}
{% do return(n.count) %}
{% endmacro %}


{# Structural invariants that must hold for *every* report this package emits. #}
{% macro _check_report(model_name) %}
{% set t = sigma_report_integration_tests %}
{% set spec = t._spec_of(model_name) %}
{% set c = spec.contents %}
{% set where = model_name ~ ': ' %}

{% do t._ok(spec.name, where ~ 'has a name') %}
{% do t._ok(spec.folderId == var('sigma_folder_id'), where ~ 'folderId comes from the sigma_folder_id var') %}
{% do t._ok(c.schemaVersion == 1 and c.kind == 'report', where ~ 'schemaVersion 1, kind report') %}
{% do t._ok(c.pages | length > 0 and c.elements | length > 0, where ~ 'has pages and elements') %}
{% do t._ok(c.config.margin is number and c.config.pageWidth > 0 and c.config.pageHeight > 0, where ~ 'config has margin and page size in pixels') %}
{% do t._ok(c.layout.startswith('<?xml'), where ~ 'layout is an XML document') %}

{# no private keys, no unresolved color markers #}
{% set keys = [] %}
{% do t._all_keys(spec, keys) %}
{% for k in keys %}
  {# `_overlap_ok` is deliberate top-level bookkeeping for the geometry check; request_body() strips it #}
  {% do t._ok(not k.startswith('_') or k == '_overlap_ok', where ~ 'private key ' ~ k ~ ' leaked into the spec') %}
{% endfor %}
{% do t._ok('__color:' not in (spec | tojson), where ~ 'every color marker was resolved') %}

{# every page and element is placed; every element id is unique #}
{% set seen = [] %}
{% for p in c.pages %}
  {% do t._ok('<Page id="' ~ p.id ~ '"' in c.layout, where ~ 'page ' ~ p.name ~ ' is in the layout') %}
{% endfor %}
{% for el in c.elements %}
  {% do t._ok(el.id not in seen, where ~ 'element id ' ~ el.id ~ ' is unique') %}
  {% do seen.append(el.id) %}
  {% do t._ok('elementId="' ~ el.id ~ '"' in c.layout, where ~ 'element ' ~ el.id ~ ' (' ~ el.kind ~ ') is placed in the layout') %}
  {% if el.get('source') %}
    {% set s = el.source %}
    {% if s.kind == 'warehouse-table' %}
      {% do t._ok(s.path | length == 3, where ~ 'warehouse path is [database, schema, table]') %}
    {% endif %}
    {# every column an element refers to is declared on it, and column ids are unique #}
    {% set declared = [] %}
    {% for col in el.columns %}
      {% do t._ok(col.id not in declared, where ~ el.id ~ ' declares column ' ~ col.id ~ ' once') %}
      {% do declared.append(col.id) %}
    {% endfor %}
    {% set refs = [] %}
    {% do t._column_refs(el, refs) %}
    {% for ref in refs %}
      {% do t._ok(ref in declared, where ~ el.id ~ ' (' ~ el.kind ~ ') refers to undeclared column ' ~ ref) %}
    {% endfor %}
  {% endif %}
{% endfor %}

{# panels only ever point at real pages #}
{% set page_ids = [] %}
{% for p in c.pages %}{% do page_ids.append(p.id) %}{% endfor %}
{% for panel in c.get('panels', []) %}
  {% do t._ok(panel.type in ['header', 'footer'], where ~ 'panel type is header or footer') %}
  {% for pid in panel.pages %}{% do t._ok(pid in page_ids, where ~ 'panel ' ~ panel.id ~ ' points at a real page') %}{% endfor %}
  {% do t._ok('<Panel id="' ~ panel.id ~ '" type="' ~ panel.type ~ '"' in c.layout, where ~ 'panel ' ~ panel.id ~ ' is in the layout') %}
{% endfor %}
{% endmacro %}


{% macro _check_simple() %}
{% set t = sigma_report_integration_tests %}
{% set c = t._spec_of('sigma_sales_simple').contents %}
{% do t._ok(c.elements | length == 4, 'sigma_sales_simple: title, rule, one KPI, one chart') %}
{% do t._ok(c.pages | length == 1 and c.pages[0].name == 'Sales simple', 'sigma_sales_simple: one page named after the report') %}
{% do t._ok(c.config.pageWidth == 816 and c.config.pageHeight == 1056 and c.config.margin == 48, 'sigma_sales_simple: US Letter with a 48px margin by default') %}
{% do t._ok(not c.get('panels'), 'sigma_sales_simple: no panels unless header/footer are given') %}
{% set kpi = t._find(c.elements, 'kpi-chart', 'Revenue') %}
{% do t._ok(kpi.source.connectionId == var('sigma_connection_id'), 'sigma_sales_simple: connection id comes from the var') %}
{% do t._ok(kpi.source.path[2] == 'stg_orders', 'sigma_sales_simple: from_ref points at the model') %}
{% do t._ok(kpi.columns[0].formula == 'Sum([Amount])' and kpi.columns[1].formula == '[stg_orders/Amount]', 'sigma_sales_simple: unqualified formula gets its qualified passthrough column') %}
{% endmacro %}


{% macro _check_dashboard() %}
{% set t = sigma_report_integration_tests %}
{% set spec = t._spec_of('sigma_sales_dashboard') %}
{% set c = spec.contents %}
{% do t._ok(spec.description == 'Compiled by dbt-sigma-report', 'sigma_sales_dashboard: description passes through report_args') %}
{% do t._ok(c.elements | length == 10, 'sigma_sales_dashboard: title, rule, 3 KPIs, 4 charts, 1 table') %}
{% do t._ok(t._count(c.elements, 'kpi-chart') == 3 and t._count(c.elements, 'table') == 1, 'sigma_sales_dashboard: element counts') %}
{% for kind in ['bar-chart', 'donut-chart', 'line-chart', 'area-chart'] %}
  {% do t._ok(t._count(c.elements, kind) == 1, 'sigma_sales_dashboard: one ' ~ kind) %}
{% endfor %}
{# the content is taller than one Letter page, so the page continues rather than overflowing #}
{% do t._ok(c.pages | length == 2, 'sigma_sales_dashboard: paginates onto a second page') %}
{% do t._ok(c.pages[0].name == 'Sales at a glance' and c.pages[1].name == 'Sales at a glance (2)', 'sigma_sales_dashboard: continuation pages are numbered') %}
{% set plan = t._find(c.elements, 'kpi-chart', 'Revenue vs plan') %}
{% do t._ok(plan.comparisonColumn.columnId is string, 'sigma_sales_dashboard: compare_to becomes comparisonColumn') %}
{% do t._ok(plan.value.columnId != plan.comparisonColumn.columnId, 'sigma_sales_dashboard: a column is on one channel only') %}
{% set table = t._find(c.elements, 'table', 'Detail') %}
{% do t._ok(table.order | length == 5, 'sigma_sales_dashboard: the table shows the five requested columns') %}
{% do t._ok(table.sort[0].direction == 'descending', 'sigma_sales_dashboard: table_sort is applied') %}
{% set bar = t._find(c.elements, 'bar-chart', 'Revenue by region') %}
{% do t._ok(bar.xAxis.sort.direction == 'descending', 'sigma_sales_dashboard: bars are sorted largest first') %}
{# the project theme var: hue Indigo, primary pinned to a brand blue #}
{% set o = c.settings.theme.overrides %}
{% do t._ok(o.colors.highlight == '#1A70F1', 'sigma_sales_dashboard: sigma_report_theme.colors.primary reaches the report theme') %}
{% do t._ok(bar.color.value == '#4f39f6', 'sigma_sales_dashboard: sigma_report_theme.hue (Indigo) recolors chart series') %}
{% do t._ok(o.categoricalScheme == 'superbloom', 'sigma_sales_dashboard: the Sigma categorical palette is the default') %}
{% endmacro %}


{% macro _check_manual() %}
{% set t = sigma_report_integration_tests %}
{% set c = t._spec_of('sigma_sales_report').contents %}
{% do t._ok(c.config.pageWidth == 794 and c.config.pageHeight == 1123 and c.config.margin == 40, 'sigma_sales_report: A4 with a 40px margin') %}
{% do t._ok(c.pages | map(attribute='name') | list == ['Summary', 'Detail'], 'sigma_sales_report: two pages, in order') %}
{% do t._ok(c.panels | length == 2 and c.panels[0].type == 'header' and c.panels[1].type == 'footer', 'sigma_sales_report: header and footer panels') %}
{% do t._ok(c.panels[0].config.height == 48 and c.panels[0].pages | length == 2, 'sigma_sales_report: the header repeats on every page') %}
{# the per-report theme overrides the project var, and recolors elements that were built before report() ran #}
{% do t._ok(c.settings.theme.overrides.categoricalScheme == ['#007a55', '#f54900', '#432dd7'], 'sigma_sales_report: a custom categorical palette') %}
{% set bar = t._find(c.elements, 'bar-chart', 'Revenue by region') %}
{% do t._ok(bar.color.value == '#009966', 'sigma_sales_report: theme=hue Emerald recolors a chart built earlier (late-bound color)') %}
{% do t._ok(bar.orientation == 'horizontal' and bar.gap.width == 'small', 'sigma_sales_report: horizontal bars and an extend() option') %}
{# a chart built on a table that is on the page #}
{% set table = t._find(c.elements, 'table', 'Orders') %}
{% set top = t._find(c.elements, 'bar-chart', 'Largest orders') %}
{% do t._ok(top.source.kind == 'table' and top.source.elementId == table.id, 'sigma_sales_report: a chart can read from another element') %}
{% do t._ok(top.columns[0].formula == '[Order Id]' or top.columns[0].formula == '[stg_orders/Order Id]', 'sigma_sales_report: child columns reference the parent table') %}
{# raw() elements keep their properties and take part in layout #}
{% set embed = t._find(c.elements, 'embed', none) %}
{% do t._ok(embed.url == 'https://example.com/status', 'sigma_sales_report: raw() keeps Sigma properties as written') %}
{% set pivot = t._find(c.elements, 'pivot-table', 'Revenue by region and segment') %}
{% do t._ok(pivot.rowsBy | length == 1 and pivot.columnsBy | length == 1 and pivot['values'] | length == 1, 'sigma_sales_report: pivot rows, columns and values') %}
{% set rev = t._find(c.elements, 'kpi-chart', 'Orders') %}
{% do t._ok(rev.timeline.columnId is string and rev.periodComparison == 'month' and rev.trend.shape == 'area', 'sigma_sales_report: KPI timeline, period comparison and sparkline') %}
{% endmacro %}


{# The `height="N"` (or `y`, `width`) the layout gives an element. #}
{% macro _box(layout, element_id, attribute) %}
{% set segment = layout.split('elementId="' ~ element_id ~ '"')[1].split('/>')[0] %}
{% do return(segment.split(' ' ~ attribute ~ '="')[1].split('"')[0] | int) %}
{% endmacro %}


{% macro _check_long_form() %}
{% set t = sigma_report_integration_tests %}
{% set c = t._spec_of('sigma_sales_long_form').contents %}
{% set title = t._find(c.elements, 'text', none) %}
{% do t._ok('Quarterly sales performance review' in title.body and 'font-size: 28px' in title.body, 'sigma_sales_long_form: titles are 28px bold spans, not markdown H1s') %}
{# a title that wraps takes more room than one that does not: sized from its content, not a fixed 64px #}
{% do t._ok(t._box(c.layout, title.id, 'height') >= 150, 'sigma_sales_long_form: a long title and its subtitle get the height they need (' ~ t._box(c.layout, title.id, 'height') ~ 'px)') %}
{# the same text in a narrow cell is taller than in a wide one, and the row stretches its neighbour to match #}
{% set narrow = t._find_text(c.elements, 'Revenue is summed') %}
{% set wide = t._find_text(c.elements, 'Short note.') %}
{% set kpi = t._find(c.elements, 'kpi-chart', 'Revenue') %}
{% do t._ok(t._box(c.layout, narrow.id, 'height') > 100 and t._box(c.layout, wide.id, 'height') < 40, 'sigma_sales_long_form: text height follows the width it is laid out at') %}
{% do t._ok(t._box(c.layout, kpi.id, 'height') == t._box(c.layout, narrow.id, 'height'), 'sigma_sales_long_form: a row is as tall as its tallest cell') %}
{# a table is a window of `rows` rows: 130px of chrome (title, header, summary bar) + 20px a row, and `fill` takes the rest of the page #}
{% set top = t._find(c.elements, 'table', 'Top orders') %}
{% do t._ok(t._box(c.layout, top.id, 'height') == 230, 'sigma_sales_long_form: rows=5 gives a 230px table') %}
{% set all = t._find(c.elements, 'table', 'All orders') %}
{% do t._ok(t._box(c.layout, all.id, 'y') + t._box(c.layout, all.id, 'height') == 960, 'sigma_sales_long_form: h=fill runs to the bottom of the content area') %}
{% do t._ok(c.pages | map(attribute='name') | list == ['Overview', 'Full list'], 'sigma_sales_long_form: both pages, nothing spilled') %}
{% endmacro %}


{% macro _check_leaderboard() %}
{% set t = sigma_report_integration_tests %}
{% set c = t._spec_of('simple_leaderboard').contents %}
{% do t._ok(t._count(c.elements, 'bar-chart') == 2 and t._count(c.elements, 'kpi-chart') == 1, 'simple_leaderboard: a KPI and one bar per dimension') %}
{% set bar = t._find(c.elements, 'bar-chart', 'Revenue by Region') %}
{% do t._ok(bar.orientation == 'horizontal' and bar.xAxis.sort.direction == 'descending', 'simple_leaderboard: horizontal, ranked bars') %}
{% endmacro %}


{% macro _check_sources() %}
{% set t = sigma_report_integration_tests %}
{% set dm = t._find(t._spec_of('sigma_sales_from_data_model').contents.elements, 'bar-chart', 'Revenue by region') %}
{% do t._ok(dm.source.kind == 'data-model', 'data model source: kind') %}
{% do t._ok(dm.source.dataModelId == var('sigma_data_model_ids').sigma_sales_model, 'data model source: id comes from the sigma_data_model_ids var') %}
{% do t._ok(dm.source.elementId | length == 32, 'data model source: element id is the full md5 sigma_data_models uses') %}
{% do t._ok(dm.columns[0].formula == '[Orders/Region]', 'data model source: columns are qualified with the data model table name') %}
{% set src = t._find(t._spec_of('sigma_orders_from_source').contents.elements, 'pie-chart', 'Orders by segment') %}
{% do t._ok(src.source.path == ['raw_database', 'raw_data', 'orders'], 'dbt source: the project relation_path override and schema= apply') %}
{% set c = t._spec_of('sigma_orders_from_source').contents %}
{% do t._ok(c.config.pageWidth == 1280 and c.config.pageHeight == 720 and c.config.margin == 32, 'dbt source: the screen preset') %}
{% endmacro %}


{% macro _check_pagination() %}
{% set t = sigma_report_integration_tests %}
{% set c = t._spec_of('sigma_paginated_tables').contents %}
{% set table = t._find(c.elements, 'table', 'Orders') %}
{% set pivot = t._find(c.elements, 'pivot-table', 'Revenue pivot') %}
{% do t._ok('flow="paginated"' in t._layout_line(c.layout, table.id), 'paginated table: the table is placed with flow="paginated"') %}
{% do t._ok('flow="paginated"' in t._layout_line(c.layout, pivot.id), 'paginated table: the pivot is placed with flow="paginated"') %}
{% do t._ok(c.layout.split('flow="paginated"') | length == 3, 'paginated table: exactly the two paginated elements carry a flow') %}
{% do t._ok(c.pages | length == 2, 'paginated table: one page per paginated element, no extra pages') %}
{% do t._ok(not table.get('flow') and not pivot.get('flow'), 'paginated table: flow is a layout property, not an element property') %}
{% do t._ok(t._text_has(c.elements, '{{CurrentPageNumber()}} of {{TotalPageCount()}}'), 'page numbers: the footer text is Sigma\'s page number') %}
{% do t._ok(c.panels | length == 1 and c.panels[0].type == 'footer' and c.panels[0].pages | length == 2, 'page numbers: a footer panel on every page') %}
{% set number = t._find(c.elements, 'text', none) %}
{% set f = t._spec_of('sigma_footer_page_numbers').contents %}
{% do t._ok(t._text_has(f.elements, 'Confidential') and t._text_has(f.elements, 'CurrentPageNumber()'), 'page numbers: a footer of your own keeps its content and gains the number') %}
{% set footer_xml = f.layout.split('<Panel')[1] %}
{% do t._ok(footer_xml.split('<Element') | length == 3, 'page numbers: the footer row holds the footer element and the number') %}
{% set dash = t._spec_of('sigma_sales_dashboard').contents %}
{% do t._ok('flow="paginated"' in t._layout_line(dash.layout, t._find(dash.elements, 'table', 'Detail').id), 'simple_dashboard: table_paginate expands the detail table') %}
{% endmacro %}


{% macro _check_flexible() %}
{% set t = sigma_report_integration_tests %}
{% set spec = t._spec_of('sigma_flexible_layout') %}
{% set c = spec.contents %}
{% set pages = c.pages | map(attribute='name') | list %}
{% do t._ok(pages == ['Nesting', 'Flexible', 'Chart family', 'Chart family (2)', 'All orders', 'All orders (2)', 'All orders (3)'], 'sigma_flexible_layout: pages ' ~ pages) %}
{# rows and stacks nest: the KPI stack sits left of the chart row, and the inner stack's two charts share a cell #}
{% set revenue = t._find(c.elements, 'kpi-chart', 'Revenue') %}
{% set region = t._find(c.elements, 'bar-chart', 'By region') %}
{% set month = t._find(c.elements, 'line-chart', 'By month') %}
{% set segment = t._find(c.elements, 'donut-chart', 'By segment') %}
{% do t._ok(t._box(c.layout, revenue.id, 'x') == 0 and t._box(c.layout, region.id, 'x') > t._box(c.layout, revenue.id, 'width'), 'sigma_flexible_layout: the chart row sits to the right of the KPI stack') %}
{% do t._ok(t._box(c.layout, month.id, 'x') == t._box(c.layout, segment.id, 'x') and t._box(c.layout, segment.id, 'y') > t._box(c.layout, month.id, 'y'), 'sigma_flexible_layout: a stack inside a row inside a row') %}
{# the row stretches its cells: the bar chart is as tall as the two stacked charts and their gap #}
{% do t._ok(t._box(c.layout, region.id, 'height') == t._box(c.layout, month.id, 'height') + 16 + t._box(c.layout, segment.id, 'height'), 'sigma_flexible_layout: a row gives every cell the full height') %}
{# at(): pinned, and flagged as allowed to overlap #}
{% set stamp = t._find_text(c.elements, 'DRAFT') %}
{% do t._ok(t._box(c.layout, stamp.id, 'x') == 520 and t._box(c.layout, stamp.id, 'width') == 200, 'sigma_flexible_layout: at() pins an element') %}
{% do t._ok(spec['_overlap_ok'] == [stamp.id], 'sigma_flexible_layout: an overlapping at() is recorded for the geometry check') %}
{# flexible heights: the stack runs to the bottom of the page and the flex children split the extra 2:1 #}
{% set big = t._find(c.elements, 'combo-chart', 'Revenue and plan') %}
{% set small = t._find(c.elements, 'treemap-chart', 'Mix') %}
{% set note = t._find_text(c.elements, 'Heights above share') %}
{% do t._ok(t._box(c.layout, note.id, 'y') + t._box(c.layout, note.id, 'height') == 960, 'sigma_flexible_layout: a flexible block takes the rest of the page') %}
{% set big_extra = t._box(c.layout, big.id, 'height') - 260 %}
{% set small_extra = t._box(c.layout, small.id, 'height') - 260 %}
{% do t._ok((big_extra - 2 * small_extra) | abs <= 2, 'sigma_flexible_layout: flex weights share the extra height 2:1 (' ~ big_extra ~ ' vs ' ~ small_extra ~ ')') %}
{# the combo chart draws its series with the types asked for #}
{% do t._ok(big.yAxis.columnIds | map(attribute='type') | list == ['bar', 'line'], 'sigma_flexible_layout: combo series types') %}
{% do t._ok(big.yAxis2.columnIds == [big.yAxis.columnIds[1].columnId], 'sigma_flexible_layout: the second measure is on the secondary axis') %}
{# the chart family #}
{% for kind in ['waterfall-chart', 'funnel-chart', 'gauge-chart', 'sankey-chart', 'box-chart', 'region-map', 'progress', 'embed', 'treemap-chart', 'combo-chart'] %}
  {% do t._ok(t._count(c.elements, kind) == 1, 'sigma_flexible_layout: one ' ~ kind) %}
{% endfor %}
{% set gauge = t._find(c.elements, 'gauge-chart', 'Attainment') %}
{% do t._ok(gauge.value.columnId is string and gauge.minimum.columnId is string and gauge.maximum.columnId is string, 'sigma_flexible_layout: gauge shelves') %}
{% do t._ok((gauge.columns | selectattr('formula', 'equalto', '0') | list) | length == 1, 'sigma_flexible_layout: a number literal is a formula, not a column') %}
{% set sankey = t._find(c.elements, 'sankey-chart', 'Flow') %}
{% do t._ok(sankey.stages | length == 2, 'sigma_flexible_layout: sankey stages') %}
{% set map = t._find(c.elements, 'region-map', 'Regions') %}
{% do t._ok(map.region.regionType == 'us-state' and map.color.by == 'scale', 'sigma_flexible_layout: region map') %}
{# a table over several pages: windows of five rows, each filtered on a hidden row-number column #}
{% set windows = [] %}
{% for el in c.elements if el.kind == 'table' %}{% do windows.append(el) %}{% endfor %}
{% do t._ok(windows | length == 3, 'sigma_flexible_layout: 12 rows at 5 a page is three table windows') %}
{% for w in windows %}
  {% set f = w.filters[0] %}
  {% do t._ok(f.kind == 'number-range' and f.min == loop.index0 * 5 + 1 and f.max == loop.index * 5, 'sigma_flexible_layout: window ' ~ loop.index ~ ' shows rows ' ~ f.min ~ '-' ~ f.max) %}
  {% set hidden = [] %}
  {% for col in w.columns if col.get('hidden') %}{% do hidden.append(col) %}{% endfor %}
  {% do t._ok(hidden | length == 1 and hidden[0].formula == 'RowNumber()' and hidden[0].id == f.columnId, 'sigma_flexible_layout: the filter is on a hidden RowNumber() column') %}
  {% do t._ok(w.order | length == 4, 'sigma_flexible_layout: the hidden column is not displayed') %}
{% endfor %}
{% do t._ok(windows[1].name == 'Orders (page 2 of 3)', 'sigma_flexible_layout: windows are numbered') %}
{% do t._ok(pages[-3:] == ['All orders', 'All orders (2)', 'All orders (3)'], 'sigma_flexible_layout: each window is on its own page') %}
{% endmacro %}


{# Run with --vars overriding sigma_report_settings (see scripts/run_integration_tests_duckdb.sh): every
   size the package would hard-code comes from the project instead. #}
{% macro assert_settings() %}
{% set t = sigma_report_integration_tests %}
{% set c = t._spec_of('sigma_sales_simple').contents %}
{% do t._ok(c.config.margin == 20 and c.config.pageWidth == 794 and c.config.pageHeight == 1123, 'settings: margin and page_size come from the project') %}
{% set bar = t._find(c.elements, 'bar-chart', 'Revenue by region') %}
{% do t._ok(t._box(c.layout, bar.id, 'height') == 111, 'settings: chart_h comes from the project (' ~ t._box(c.layout, bar.id, 'height') ~ ')') %}
{% set kpi = t._find(c.elements, 'kpi-chart', 'Revenue') %}
{% do t._ok(t._box(c.layout, kpi.id, 'height') == 77, 'settings: kpi_h comes from the project') %}
{% set title = c.elements[0] %}
{% do t._ok('font-size: 40px' in title.body, 'settings: title_size comes from the project') %}
{# a per-call argument still beats the project setting #}
{% set explicit = t._spec_of('sigma_sales_report').contents %}
{% do t._ok(explicit.config.margin == 40 and explicit.config.pageWidth == 794, 'settings: report(margin=, page_size=) wins over the project') %}
{{ log('settings assertions passed', info=True) }}
{% endmacro %}


{% macro _check_presets() %}
{% set t = sigma_report_integration_tests %}
{% set c = t._spec_of('preset_executive_summary').contents %}
{% do t._ok(t._count(c.elements, 'kpi-chart') == 3 and t._count(c.elements, 'line-chart') == 1, 'preset_executive_summary: three KPIs and the headline chart') %}
{% do t._ok(t._find(c.elements, 'kpi-chart', 'Revenue').comparisonColumn.columnId is string, 'preset_executive_summary: a KPI spec keeps compare_to') %}
{% do t._ok(t._text_has(c.elements, '- SMB is running below plan'), 'preset_executive_summary: highlights are written as bullets') %}

{% set c = t._spec_of('preset_period_review').contents %}
{% set revenue = t._find(c.elements, 'kpi-chart', 'Revenue') %}
{% do t._ok(revenue.timeline.columnId is string and revenue.periodComparison == 'month' and revenue.trend.shape == 'area', 'preset_period_review: every KPI compares the latest period with the one before, with a sparkline') %}
{% do t._ok(t._find(c.elements, 'kpi-chart', 'Orders').periodComparison == 'month', 'preset_period_review: the period default reaches every KPI') %}
{% do t._ok(t._count(c.elements, 'line-chart') == 1 and t._count(c.elements, 'bar-chart') == 2, 'preset_period_review: one trend and a bar chart per breakdown') %}
{% do t._find(c.elements, 'bar-chart', 'Revenue by Segment') %}

{% set c = t._spec_of('preset_statement').contents %}
{% set table = t._find(c.elements, 'table', 'Line items') %}
{% do t._ok(table.order | length == 4 and table.sort[0].direction == 'ascending', 'preset_statement: line-item columns and sort') %}
{% do t._find(c.elements, 'kpi-chart', 'Total due') %}
{% do t._ok(t._text_has(c.elements, 'Payment terms: net 30.'), 'preset_statement: footer note') %}
{# the table is paginated and last on its page, so the totals sit above it and the note is in the footer #}
{% do t._ok(t._layout_line(c.layout, table.id) is string and 'flow="paginated"' in t._layout_line(c.layout, table.id), 'preset_statement: the line-item table is paginated') %}
{% do t._ok(t._layout_y(c.layout, t._find(c.elements, 'kpi-chart', 'Total due').id) < t._layout_y(c.layout, table.id), 'preset_statement: totals sit above the paginated table') %}
{% do t._ok(c.panels | length == 1 and c.panels[0].type == 'footer', 'preset_statement: the footer holds the note and the page number') %}
{% do t._ok(t._text_has(c.elements, 'CurrentPageNumber()') and t._text_has(c.elements, 'TotalPageCount()'), 'preset_statement: page numbers are on by default') %}
{% endmacro %}

{% macro _check_actions() %}
{% set t = sigma_report_integration_tests %}
{% set spec = t._spec_of('sigma_actions_report') %}
{% set c = spec.contents %}
{% set table = t._find(c.elements, 'table', 'Orders') %}
{% set notes_id = c.pages | selectattr('name', 'equalto', 'Notes') | map(attribute='id') | first %}
{% set refresh = t._find(c.elements, 'button', 'Refresh orders') %}
{% do t._ok(refresh.text == 'Refresh orders' and refresh.appearance == 'filled', 'sigma_actions_report: a button with its text and appearance') %}
{% do t._ok(refresh.actions | length == 1 and refresh.actions[0].trigger == 'on-click', 'sigma_actions_report: one on-click action') %}
{% do t._ok(refresh.actions[0].id is string and refresh.actions[0].effects | length == 2, 'sigma_actions_report: the action has an id and two effects, in order') %}
{% do t._ok(refresh.actions[0].effects[0] == {'effect': 'refresh-element', 'target': {'type': 'element', 'element': table.id}}, 'sigma_actions_report: refresh_element points at the table id') %}
{% do t._ok(refresh.actions[0].effects[1] == {'effect': 'navigate', 'target': {'type': 'page', 'page': notes_id}}, 'sigma_actions_report: navigate points at the page id') %}
{% set download = t._find(c.elements, 'button', 'Download PDF') %}
{% do t._ok(download.actions[0].effects[0].format == {'type': 'pdf', 'layout': 'landscape', 'pageSize': 'a4'} and download.actions[0].effects[0].source == {'type': 'all'}, 'sigma_actions_report: download exports the whole report as a landscape A4 PDF') %}
{% set reset = t._find(c.elements, 'button', 'Reset filters') %}
{% do t._ok(reset.actions[0].effects[1].value == {'type': 'constant', 'value': {'type': 'text', 'value': 'West'}}, 'sigma_actions_report: set_control_value types a plain string') %}
{% do t._ok(reset.actions[0].effects[0].scope == {'type': 'page'} and reset.actions[0].effects[2].url == 'https://example.com/help', 'sigma_actions_report: clear_controls and open_url') %}
{% do t._ok(table.actions | length == 1 and table.actions[0].trigger == 'on-select' and table.actions[0].effects[0].effect == 'call-api', 'sigma_actions_report: with_actions attaches to an existing element; effect() passes Sigma fields through') %}
{% do t._ok(refresh.actions[0].id != download.actions[0].id and refresh.actions[0].id != reset.actions[0].id, 'sigma_actions_report: action ids differ') %}
{% do t._ok(spec.schedules | length == 2 and 'schedules' not in c, 'sigma_actions_report: schedules sit beside contents, not inside it') %}
{% set weekly = spec.schedules[0] %}
{% do t._ok(weekly.schedule == {'cronSpec': '0 8 * * 1', 'timezone': 'America/New_York'}, 'sigma_actions_report: schedule cron and timezone') %}
{% do t._ok(weekly.target == [{'email': 'finance@example.com'}, {'teamId': '<your-team-id>'}], 'sigma_actions_report: recipients, an email and a team mapping') %}
{% do t._ok(weekly.configV2.title == 'Weekly orders' and weekly.configV2.exportAttachments[0].formatOptions == {'type': 'PDF', 'layout': 'landscape'}, 'sigma_actions_report: schedule title and PDF attachment') %}
{% do t._ok(weekly.configV2.conditionOptions.condition == {'type': 'isNotEmpty', 'elementId': table.id}, 'sigma_actions_report: only_if_not_empty tests the table id') %}
{% do t._ok(spec.schedules[1].schedule.timezone == 'UTC' and spec.schedules[1].configV2.attachmentSettings.zipAttachments, 'sigma_actions_report: default timezone, and options merge onto configV2') %}
{% endmacro %}

{% macro _check_filtered() %}
{% set t = sigma_report_integration_tests %}
{% set c = t._spec_of('sigma_filtered_dashboard').contents %}
{% set filtered = namespace(count=0) %}
{% for el in c.elements if el.get('source') %}
  {% set filtered.count = filtered.count + 1 %}
  {% do t._ok(el.filters | length == 1, 'sigma_filtered_dashboard: ' ~ el.kind ~ ' has exactly one filter') %}
  {% set f = el.filters[0] %}
  {% do t._ok(f.kind == 'list' and f.mode == 'include' and f['values'] == ['West'], 'sigma_filtered_dashboard: the filter keeps only West') %}
  {% set hidden = [] %}
  {% for col in el.columns if col.id == f.columnId %}{% do hidden.append(col) %}{% endfor %}
  {% do t._ok(hidden | length == 1 and hidden[0].hidden is true and hidden[0].formula.endswith('/Region]'), 'sigma_filtered_dashboard: the filter targets a hidden Region column') %}
{% endfor %}
{% do t._ok(filtered.count == 3, 'sigma_filtered_dashboard: the KPI, the chart and the table are all filtered') %}
{% endmacro %}


{% macro assert_reports() %}
{% set t = sigma_report_integration_tests %}
{% for name in ['sigma_flexible_layout', 'sigma_sales_long_form', 'sigma_sales_simple', 'sigma_sales_dashboard', 'simple_leaderboard', 'sigma_sales_report', 'sigma_sales_from_data_model', 'sigma_orders_from_source', 'preset_executive_summary', 'preset_period_review', 'preset_statement', 'sigma_actions_report', 'sigma_paginated_tables', 'sigma_footer_page_numbers', 'sigma_filtered_dashboard'] %}
  {% do t._check_report(name) %}
{% endfor %}
{% do t._check_simple() %}
{% do t._check_dashboard() %}
{% do t._check_manual() %}
{% do t._check_long_form() %}
{% do t._check_flexible() %}
{% do t._check_leaderboard() %}
{% do t._check_presets() %}
{% do t._check_pagination() %}
{% do t._check_sources() %}
{% do t._check_filtered() %}
{% do t._check_actions() %}
{{ log('all assertions passed', info=True) }}
{% endmacro %}
