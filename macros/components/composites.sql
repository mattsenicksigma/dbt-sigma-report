{# Composites: reusable blocks written with nothing but the public element and layout macros. A
   composite is also documentation - it is exactly what you would write yourself.

   Every composite returns either a block (an element or a `row`) or a *list* of blocks; `page()`,
   `row()` and `report()` flatten lists, so composites nest freely. #}


{# A report title block: the title, a muted subtitle, and a rule underneath. #}
{% macro report_header(title, subtitle=none, key=none) %}
{% do return([
  sigma_report.title(title, subtitle, key=key),
  sigma_report.divider(key='rule:' ~ (key or title)),
]) %}
{% endmacro %}


{# A titled section: a heading followed by its blocks. Use distinct headings (or `key=`) per section. #}
{% macro section(heading, blocks, key=none) %}
{% set out = [sigma_report.heading(heading, key=key)] %}
{% for block in sigma_report.flatten(blocks) %}
  {% do out.append(block) %}
{% endfor %}
{% do return(out) %}
{% endmacro %}


{# A band of KPI tiles sharing the page width equally. Pass `sigma_report.kpi(...)` results. #}
{% macro kpi_row(kpis, gap=none) %}
{% do return(sigma_report.row(kpis, gap=gap)) %}
{% endmacro %}


{# Builds a KPI from a plain mapping - the calling convention `simple_dashboard` uses. Keys are the
   arguments of `sigma_report.kpi`: value (required), name, format, compare_to, timeline, period,
   trend, direction, description, key, h. #}
{% macro kpi_from_spec(source, spec) %}
{% if spec is not mapping or 'value' not in spec %}
  {% do sigma_report.fail('kpi_from_spec', "a KPI spec is a mapping with at least `value`, got " ~ spec) %}
{% endif %}
{% do return(sigma_report.kpi(
  source, spec['value'],
  name=spec.get('name'), key=spec.get('key'), h=spec.get('h'), format=spec.get('format'),
  compare_to=spec.get('compare_to'), compare_label=spec.get('compare_label'),
  timeline=spec.get('timeline'), period=spec.get('period', 'month'), trend=spec.get('trend', false),
  direction=spec.get('direction', 'higher'), description=spec.get('description')
)) %}
{% endmacro %}


{# Builds a chart from a plain mapping. `type` is bar, line, area, scatter, pie, donut, combo, waterfall,
   box, funnel, gauge, treemap or sankey; the other keys are that chart macro's arguments (x / y for
   cartesian charts, category / value for pie, donut and treemap, stage / value for funnel, ...). This is the dispatcher behind `simple_dashboard`'s `charts=`; it is public so you can use
   the same convention in your own composites. #}
{% macro chart_from_spec(source, spec) %}
{% if spec is not mapping or 'type' not in spec %}
  {% do sigma_report.fail('chart_from_spec', "a chart spec is a mapping with at least `type`, got " ~ spec) %}
{% endif %}
{% set t = spec['type'] %}
{% set common_h = spec.get('h') %}
{% if t == 'bar' %}
  {% do return(sigma_report.bar_chart(source, spec['x'], spec['y'], color=spec.get('color'), name=spec.get('name'), key=spec.get('key'), h=common_h, sort_by=spec.get('sort_by', 'y'), sort_direction=spec.get('sort_direction', 'desc'), stacking=spec.get('stacking'), labels=spec.get('labels', false), legend=spec.get('legend', true), horizontal=spec.get('horizontal', false))) %}
{% elif t == 'line' %}
  {% do return(sigma_report.line_chart(source, spec['x'], spec['y'], color=spec.get('color'), name=spec.get('name'), key=spec.get('key'), h=common_h, sort_by=spec.get('sort_by', 'x'), sort_direction=spec.get('sort_direction', 'asc'), labels=spec.get('labels', false), legend=spec.get('legend', true))) %}
{% elif t == 'area' %}
  {% do return(sigma_report.area_chart(source, spec['x'], spec['y'], color=spec.get('color'), name=spec.get('name'), key=spec.get('key'), h=common_h, sort_by=spec.get('sort_by', 'x'), sort_direction=spec.get('sort_direction', 'asc'), stacking=spec.get('stacking'), labels=spec.get('labels', false), legend=spec.get('legend', true))) %}
{% elif t == 'scatter' %}
  {% do return(sigma_report.scatter_chart(source, spec['x'], spec['y'], color=spec.get('color'), size=spec.get('size'), name=spec.get('name'), key=spec.get('key'), h=common_h, legend=spec.get('legend', true))) %}
{% elif t == 'pie' %}
  {% do return(sigma_report.pie_chart(source, spec['category'], spec['value'], name=spec.get('name'), key=spec.get('key'), h=common_h, labels=spec.get('labels', true), legend=spec.get('legend', true))) %}
{% elif t == 'donut' %}
  {% do return(sigma_report.donut_chart(source, spec['category'], spec['value'], hole_value=spec.get('hole_value'), name=spec.get('name'), key=spec.get('key'), h=common_h, labels=spec.get('labels', true), legend=spec.get('legend', true))) %}
{% elif t == 'combo' %}
  {% do return(sigma_report.combo_chart(source, spec['x'], spec['y'], series_types=spec.get('series_types'), secondary=spec.get('secondary'), color=spec.get('color'), name=spec.get('name'), key=spec.get('key'), h=common_h, labels=spec.get('labels', false), legend=spec.get('legend', true))) %}
{% elif t == 'waterfall' %}
  {% do return(sigma_report.waterfall_chart(source, spec['x'], spec['y'], name=spec.get('name'), key=spec.get('key'), h=common_h, legend=spec.get('legend', true))) %}
{% elif t == 'box' %}
  {% do return(sigma_report.box_chart(source, spec['y'], x=spec.get('x'), name=spec.get('name'), key=spec.get('key'), h=common_h, legend=spec.get('legend', true))) %}
{% elif t == 'funnel' %}
  {% do return(sigma_report.funnel_chart(source, spec['stage'], spec['value'], name=spec.get('name'), key=spec.get('key'), h=common_h)) %}
{% elif t == 'gauge' %}
  {% do return(sigma_report.gauge_chart(source, spec['value'], minimum=spec.get('minimum'), maximum=spec.get('maximum'), target=spec.get('target'), name=spec.get('name'), key=spec.get('key'), h=common_h)) %}
{% elif t == 'treemap' %}
  {% do return(sigma_report.treemap_chart(source, spec['category'], spec['value'], split_by=spec.get('split_by'), color=spec.get('color'), color_by=spec.get('color_by', 'scale'), name=spec.get('name'), key=spec.get('key'), h=common_h)) %}
{% elif t == 'sankey' %}
  {% do return(sigma_report.sankey_chart(source, spec['stages'], spec['value'], name=spec.get('name'), key=spec.get('key'), h=common_h)) %}
{% endif %}
{% do sigma_report.fail('chart_from_spec', "unknown chart type '" ~ t ~ "' - use bar, line, area, scatter, pie, donut, combo, waterfall, box, funnel, gauge, treemap or sankey (or build the element with sigma_report.raw).") %}
{% endmacro %}


{# Groups elements into rows of `per_row` (default 2), so a list of charts becomes a tidy grid. A short
   last row keeps the same cell width as the rows above it (the remaining space stays empty) rather
   than stretching one chart across the page. #}
{% macro grid(elements, per_row=2, gap=none) %}
{% set items = sigma_report.flatten(elements) %}
{% set rows = [] %}
{% for start in range(0, items | length, per_row) %}
  {% set chunk = items[start:start + per_row] %}
  {% do rows.append(sigma_report.row(chunk, gap=gap, pad=per_row - (chunk | length))) %}
{% endfor %}
{% do return(rows) %}
{% endmacro %}


{# Assembles blocks into a one-page, paginating report. The shared tail of the `simple_*` composites:
   `args` is a mapping of `sigma_report.report()` arguments (theme, folder_id, report_id, description,
   page_size, orientation, margin, gap, header, footer, header_height, footer_height). Public so your
   own composites can end the same way. #}
{% macro report_from_args(name, blocks, args={}) %}
{% set a = {} %}
{% do a.update(args) %}
{% do return(sigma_report.report(
  name,
  [sigma_report.page(name, blocks, paginate=true)],
  theme=a.get('theme', {}), folder_id=a.get('folder_id'), report_id=a.get('report_id'),
  description=a.get('description'), page_size=a.get('page_size'), orientation=a.get('orientation'),
  margin=a.get('margin'), gap=a.get('gap'), header=a.get('header'), footer=a.get('footer'),
  header_height=a.get('header_height'), footer_height=a.get('footer_height'),
  page_numbers=a.get('page_numbers', false), schedules=a.get('schedules', [])
)) %}
{% endmacro %}


{# A complete one-page dashboard from data alone: title, KPI band, chart rows and a detail table.
   Everything is optional except `name` and `source`.

     sigma_report.simple_dashboard(
       name='Sales at a glance',
       source=sigma_report.from_ref('stg_orders'),
       subtitle='Bookings and orders',
       kpis=[{'value': 'Sum([Amount])', 'name': 'Revenue', 'format': sigma_report.format_currency()},
             {'value': 'Count()', 'name': 'Orders'}],
       charts=[{'type': 'bar', 'x': 'region', 'y': 'Sum([Amount])', 'name': 'Revenue by region'},
               {'type': 'donut', 'category': 'segment', 'value': 'Sum([Amount])', 'name': 'By segment'}],
       table_columns=['order_id', 'order_date', 'region', 'amount'],
     )

   `kpis` and `charts` are lists of mappings (see `kpi_from_spec` / `chart_from_spec`); charts are laid
   out two to a row (`charts_per_row`). The table is the detail view, built on the same source and
   showing `table_rows` rows (default 10) - or pass `table_h='fill'` to give it the rest of its page, or
   a pixel height. Give `table_page_count` (with `table_sort`) to run the table over that many pages of
   `table_rows` rows each instead - see `table_pages` - or `table_paginate=true` to let Sigma expand the
   table to all its rows when the report renders (it must then be the last block). Content that does not
   fit one page continues on the next
   (`paginate=true`). Pass `show_title=false` to leave out the title, subtitle and rule (the report is still
   named `name`). Pass any `sigma_report.report()` argument through `report_args`
   (page_size, orientation, margin, header, footer, theme, ...). The result is a finished report spec,
   ready for `sigma_report.materialize()`.

   It is built from the public macros only; when you outgrow it, write the same thing by hand with
   `page()` and `row()`. #}
{% macro simple_dashboard(name, source, subtitle=none, kpis=[], charts=[], charts_per_row=2, table_columns=none, table_name='Detail', table_rows=none, table_h=none, table_page_count=none, table_paginate=false, table_sort=[], show_title=true, report_args={}) %}
{% set blocks = sigma_report.report_header(name, subtitle) if show_title else [] %}
{% if kpis %}
  {% set tiles = [] %}
  {% for spec in kpis %}{% do tiles.append(sigma_report.kpi_from_spec(source, spec)) %}{% endfor %}
  {% do blocks.append(sigma_report.kpi_row(tiles)) %}
{% endif %}
{% if charts %}
  {% set figures = [] %}
  {% for spec in charts %}{% do figures.append(sigma_report.chart_from_spec(source, spec)) %}{% endfor %}
  {% for r in sigma_report.grid(figures, per_row=charts_per_row) %}{% do blocks.append(r) %}{% endfor %}
{% endif %}
{% if table_columns and table_page_count %}
  {# the detail table runs over `table_page_count` pages of `table_rows` rows each #}
  {% do blocks.append(sigma_report.page_break()) %}
  {% for b in sigma_report.table_pages(source, table_columns, sigma_report.setting('table_rows', table_rows), pages=table_page_count, name=table_name, sort=table_sort) %}{% do blocks.append(b) %}{% endfor %}
{% elif table_columns %}
  {% do blocks.append(sigma_report.table(source, table_columns, name=table_name, rows=table_rows, h=table_h, sort=table_sort, paginate=table_paginate)) %}
{% endif %}
{% do return(sigma_report.report_from_args(name, blocks, report_args)) %}
{% endmacro %}


{# A ranking report: one horizontal bar chart per dimension, largest first, under a KPI for the
   overall measure. Who is on top, by any measure - teams, products, regions, accounts.

     sigma_report.simple_leaderboard(
       name='Team standings',
       source=sigma_report.from_ref('scores'),
       dimensions=['team', 'region'],
       measure='Sum([Points])', measure_name='Points',
     )

   A thin layer over the same public macros as `simple_dashboard`; `report_args` as there. #}
{% macro simple_leaderboard(name, source, dimensions, measure, measure_name=none, subtitle=none, measure_format=none, bar_h=none, report_args={}) %}
{% set blocks = sigma_report.report_header(name, subtitle) %}
{% do blocks.append(sigma_report.kpi(source, measure, name=measure_name or 'Total', format=measure_format, key='leaderboard-total')) %}
{% for dimension in dimensions %}
  {% do blocks.append(sigma_report.bar_chart(
    source, dimension, sigma_report.field(measure, name=measure_name, format=measure_format),
    name=(measure_name or 'Total') ~ ' by ' ~ sigma_report.titleize(dimension), horizontal=true, labels=true, h=bar_h
  )) %}
{% endfor %}
{% do return(sigma_report.report_from_args(name, blocks, report_args)) %}
{% endmacro %}
