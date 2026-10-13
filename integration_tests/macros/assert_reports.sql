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
    {% elif k == 'columnIds' %}{% for c in value[k] %}{% do acc.append(c) %}{% endfor %}
    {% elif k in ['order', 'values'] and value[k] is sequence and value[k] is not string %}{% for c in value[k] %}{% if c is string %}{% do acc.append(c) %}{% endif %}{% endfor %}
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


{# First element of `kind` whose title text (or, for a plain-string name, the name) matches `title`;
   `title` none matches any. #}
{% macro _find(elements, kind, title) %}
{% for el in elements %}
  {% if el.kind == kind %}
    {% set shown = el.name.text if el.get('name') is mapping else el.get('name') %}
    {% set shown = shown if shown is not none else '' %}
    {% if title is none or shown == title %}
      {% do return(el) %}
    {% endif %}
  {% endif %}
{% endfor %}
{% do exceptions.raise_compiler_error('ASSERTION FAILED: no ' ~ kind ~ ' titled ' ~ title) %}
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
  {% do t._ok(not k.startswith('_'), where ~ 'private key ' ~ k ~ ' leaked into the spec') %}
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

{% macro assert_reports() %}
{% set t = sigma_report_integration_tests %}
{% for name in ['sigma_sales_simple', 'sigma_sales_dashboard', 'simple_leaderboard', 'sigma_sales_report', 'sigma_sales_from_data_model', 'sigma_orders_from_source', 'preset_executive_summary', 'preset_period_review', 'preset_statement', 'sigma_paginated_tables', 'sigma_footer_page_numbers'] %}
  {% do t._check_report(name) %}
{% endfor %}
{% do t._check_simple() %}
{% do t._check_dashboard() %}
{% do t._check_manual() %}
{% do t._check_leaderboard() %}
{% do t._check_presets() %}
{% do t._check_pagination() %}
{% do t._check_sources() %}
{{ log('all assertions passed', info=True) }}
{% endmacro %}
