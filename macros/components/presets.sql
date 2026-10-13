{# Report presets: whole documents from data alone, in the same style as `simple_dashboard`. Each is
   written with the public macros only (`report_header`, `section`, `kpi_row`, `kpi_from_spec`,
   `chart_from_spec`, `grid`, `report_from_args`), so when one nearly fits you can copy it and change
   it. All of them paginate and take `report_args` (any `sigma_report.report()` argument). #}


{# One line of label / value facts - an account's owner and renewal date, an invoice's number and due
   date. `facts` is a list of [label, value] pairs, shown in order as "**Label** value". Values are
   written into the report as given (they are text, not formulas). #}
{% macro facts_line(facts, key='facts') %}
{% set parts = [] %}
{% for pair in facts %}
  {% if pair is not sequence or pair is string or pair | length != 2 %}
    {% do sigma_report.fail('facts_line', "facts is a list of [label, value] pairs, got " ~ pair) %}
  {% endif %}
  {% do parts.append('**' ~ pair[0] ~ '** ' ~ pair[1]) %}
{% endfor %}
{% do return(sigma_report.text(parts | join('  ·  '), key=key)) %}
{% endmacro %}


{# A bulleted text block. `lines` is a string or a list of strings; the element is as tall as the
   number of lines needs (a bullet that wraps onto a second line is not counted: raise `h`). #}
{% macro bullet_list(lines, key, h=none) %}
{% set items = [lines] if lines is string else lines %}
{% set body = [] %}
{% for line in items %}{% do body.append('- ' ~ line) %}{% endfor %}
{% do return(sigma_report.text(body | join('\n'), key=key, h=h or (24 * (items | length) + 8))) %}
{% endmacro %}


{# KPI mappings with the preset's defaults filled in under whatever the caller wrote. #}
{% macro _kpis_with(source, specs, defaults, where) %}
{% if not specs %}
  {% do sigma_report.fail(where, "kpis is required - give at least one KPI mapping, e.g. {'value': 'Sum([Amount])', 'name': 'Revenue'}.") %}
{% endif %}
{% set tiles = [] %}
{% for spec in specs %}
  {% if spec is mapping %}
    {% set merged = {} %}
    {% do merged.update(defaults) %}
    {% do merged.update(spec) %}
    {% do tiles.append(sigma_report.kpi_from_spec(source, merged)) %}
  {% else %}
    {% do tiles.append(sigma_report.kpi_from_spec(source, spec)) %}
  {% endif %}
{% endfor %}
{% do return(tiles) %}
{% endmacro %}


{# A one-page executive summary: the headline numbers, one chart, and the story in a few bullets.

     sigma_report.simple_executive_summary(
       name='Q3 summary',
       source=sigma_report.from_ref('stg_orders'),
       kpis=[{'value': 'Sum([Amount])', 'name': 'Revenue', 'compare_to': 'Sum([Target Amount])'},
             {'value': 'Count()', 'name': 'Orders'}],
       chart={'type': 'line', 'x': 'DateTrunc("month", [Order Date])', 'y': 'Sum([Amount])', 'name': 'Revenue by month'},
       highlights=['West grew fastest', 'SMB is below plan'],
     )

   `kpis` (required) are mappings as for `simple_dashboard`; keep it to three or four. `chart` is one
   chart mapping, shown full width. `highlights` is a string or list of strings, shown as bullets under
   a "Highlights" heading; write them in dbt (they are text), for example from a var. #}
{% macro simple_executive_summary(name, source, kpis, chart=none, highlights=none, highlights_heading='Highlights', subtitle=none, chart_h=280, report_args={}) %}
{% set blocks = sigma_report.report_header(name, subtitle) %}
{% do blocks.append(sigma_report.kpi_row(sigma_report._kpis_with(source, kpis, {'h': 104}, 'simple_executive_summary'))) %}
{% if chart is not none %}
  {% set spec = {'h': chart_h} %}
  {% do spec.update(chart) %}
  {% do blocks.append(sigma_report.chart_from_spec(source, spec)) %}
{% endif %}
{% if highlights %}
  {% for b in sigma_report.section(highlights_heading, [sigma_report.bullet_list(highlights, key='highlights')]) %}{% do blocks.append(b) %}{% endfor %}
{% endif %}
{% do return(sigma_report.report_from_args(name, blocks, report_args)) %}
{% endmacro %}


{# A recurring period review (weekly, monthly, quarterly): every KPI is the latest period against the
   one before it, with a sparkline; under them a trend of the first KPI and the same measure broken
   down by each dimension; then the notes and actions for the meeting.

     sigma_report.simple_period_review(
       name='Monthly business review',
       source=sigma_report.from_ref('stg_orders'),
       date_field='order_date', period='month',
       kpis=[{'value': 'Sum([Amount])', 'name': 'Revenue', 'format': sigma_report.format_currency()},
             {'value': 'Count()', 'name': 'Orders'}],
       breakdowns=['region', 'segment'],
       notes=['Revenue up on West', 'Action: review SMB pricing'],
     )

   `date_field` is the date every KPI is compared over and the trend chart's axis; `period` is any
   Sigma DateTrunc unit (day, week, month, quarter, year). A KPI mapping may override `timeline`,
   `period`, `trend` and any other key. `breakdowns` are dimension fields; each becomes a ranked bar
   chart of the first KPI's measure, two to a row. `notes` is a string or list of strings. #}
{% macro simple_period_review(name, source, date_field, kpis, period='month', breakdowns=[], notes=none, notes_heading='Notes and actions', subtitle=none, trend_h=260, chart_h=260, report_args={}) %}
{% set source = sigma_report.resolve_source(source, 'simple_period_review') %}
{% set tiles = sigma_report._kpis_with(source, kpis, {'timeline': date_field, 'period': period, 'trend': true}, 'simple_period_review') %}
{% set lead = kpis[0] %}
{% if lead is not mapping or 'value' not in lead %}
  {% do sigma_report.fail('simple_period_review', "a KPI spec is a mapping with at least `value`, got " ~ lead) %}
{% endif %}
{% set measure = sigma_report.field(lead['value'], name=lead.get('name'), format=lead.get('format')) %}
{% set measure_name = lead.get('name') or lead['value'] %}
{% set bucket = sigma_report.field(
  'DateTrunc("' ~ period ~ '", ' ~ sigma_report.formula_for(date_field, source) ~ ')',
  name=sigma_report.titleize(period)
) %}
{% set blocks = sigma_report.report_header(name, subtitle) %}
{% do blocks.append(sigma_report.kpi_row(tiles)) %}
{% do blocks.append(sigma_report.line_chart(source, bucket, measure, name=measure_name ~ ' by ' ~ period, h=trend_h, legend=false)) %}
{% if breakdowns %}
  {% set figures = [] %}
  {% for dimension in breakdowns %}
    {% do figures.append(sigma_report.bar_chart(source, dimension, measure, name=measure_name ~ ' by ' ~ sigma_report.titleize(dimension), horizontal=true, labels=true, h=chart_h, legend=false)) %}
  {% endfor %}
  {% for b in sigma_report.section('Breakdown', sigma_report.grid(figures, per_row=2)) %}{% do blocks.append(b) %}{% endfor %}
{% endif %}
{% if notes %}
  {% for b in sigma_report.section(notes_heading, [sigma_report.bullet_list(notes, key='notes')]) %}{% do blocks.append(b) %}{% endfor %}
{% endif %}
{% do return(sigma_report.report_from_args(name, blocks, report_args)) %}
{% endmacro %}


{# A statement or invoice: who and when, what is owed, and the line items. The case where a paginated
   report is the right object and a workbook is not.

     sigma_report.simple_statement(
       name='Statement',
       source=sigma_report.from_ref('acme_orders'),
       facts=[['Statement', 'ST-2026-10'], ['Customer', 'Acme'], ['Due', '2026-11-15']],
       columns=['order_id', 'order_date', 'region', sigma_report.field('Sum([Amount])', name='Amount')],
       totals=[{'value': 'Sum([Amount])', 'name': 'Total due', 'format': sigma_report.format_currency(2)}],
       footer_note='Payment terms: net 30.',
     )

   `columns` (required) are the line-item table's fields. The table is *paginated*: it grows to hold
   every row when the report renders and continues onto further pages, so a statement can be any
   length. Because the package cannot know how far it will grow, it is the last thing on its page; the
   totals therefore sit above it (amount due first, as on most invoices) and `footer_note` goes in the
   page footer, which repeats on every page next to a "page of pages" number (`page_numbers` is on
   unless `report_args` says otherwise). `rows_h` is the height the table starts with. `facts` is a
   list of [label, value] pairs shown above the totals; `totals` are KPI mappings. #}
{% macro simple_statement(name, source, columns, facts=[], totals=[], footer_note=none, rows_name='Line items', rows_h=420, rows_sort=[], subtitle=none, report_args={}) %}
{% if not columns %}
  {% do sigma_report.fail('simple_statement', "columns is required - list the fields the line-item table should show.") %}
{% endif %}
{% if footer_note and report_args.get('footer') %}
  {% do sigma_report.fail('simple_statement', "footer_note and report_args.footer both set - put the note in your own footer, or drop one of them.") %}
{% endif %}
{% set blocks = sigma_report.report_header(name, subtitle) %}
{% if facts %}
  {% do blocks.append(sigma_report.facts_line(facts, key='statement-facts')) %}
{% endif %}
{% if totals %}
  {% do blocks.append(sigma_report.kpi_row(sigma_report._kpis_with(source, totals, {'h': 80}, 'simple_statement'))) %}
{% endif %}
{% do blocks.append(sigma_report.table(source, columns, name=rows_name, h=rows_h, sort=rows_sort, paginate=true)) %}
{% set args = {'page_numbers': true} %}
{% do args.update(report_args) %}
{% if footer_note %}
  {% do args.update({'footer': [sigma_report.text(footer_note, key='statement-note')]}) %}
{% endif %}
{% do return(sigma_report.report_from_args(name, blocks, args)) %}
{% endmacro %}
