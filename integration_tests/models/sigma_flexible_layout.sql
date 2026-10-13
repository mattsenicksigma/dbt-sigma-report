{# What the layout and element set can do beyond a stack of rows: rows and stacks nested to any depth, flexible
   heights shared by weight, an element pinned with at(), a table that runs over several pages, and the
   rest of Sigma's chart family. Four pages. #}
{% set orders = sigma_report.from_ref('stg_orders') %}

{# ---- page 1: nesting ---- #}
{% set revenue = sigma_report.kpi(orders, 'Sum([Amount])', name='Revenue', key='fl-revenue') %}
{% set order_count = sigma_report.kpi(orders, 'Count()', name='Orders', key='fl-orders') %}
{% set vs_plan = sigma_report.kpi(orders, 'Sum([Amount])', name='Vs plan', key='fl-plan', compare_to='Sum([Target Amount])') %}
{% set by_region = sigma_report.bar_chart(orders, 'region', 'Sum([Amount])', name='By region', key='fl-region') %}
{% set by_month = sigma_report.line_chart(orders, 'DateTrunc("month", [Order Date])', 'Sum([Amount])', name='By month', key='fl-month') %}
{% set by_segment = sigma_report.donut_chart(orders, 'segment', 'Sum([Amount])', name='By segment', key='fl-segment') %}
{% set stamp = sigma_report.text('**DRAFT**', key='fl-stamp', h=28) %}

{# ---- page 2: flexible heights ---- #}
{% set big = sigma_report.combo_chart(orders, 'DateTrunc("month", [Order Date])', ['Sum([Amount])', 'Sum([Target Amount])'],
    series_types=['bar', 'line'], secondary=[1], name='Revenue and plan', key='fl-combo') %}
{% set small = sigma_report.treemap_chart(orders, 'region', 'Sum([Amount])', color='Sum([Target Amount])', name='Mix', key='fl-treemap') %}
{% set footnote = sigma_report.text('Heights above share the room left on the page 2:1.', key='fl-footnote') %}

{# ---- page 3: more of the chart family ---- #}
{% set waterfall = sigma_report.waterfall_chart(orders, 'region', 'Sum([Amount])', name='Waterfall', key='fl-waterfall') %}
{% set funnel = sigma_report.funnel_chart(orders, 'segment', 'Sum([Amount])', name='Funnel', key='fl-funnel') %}
{% set gauge = sigma_report.gauge_chart(orders, 'Sum([Amount])', minimum='0', maximum='Sum([Target Amount])', name='Attainment', key='fl-gauge') %}
{% set sankey = sigma_report.sankey_chart(orders, ['segment', 'region'], 'Sum([Amount])', name='Flow', key='fl-sankey') %}
{% set box = sigma_report.box_chart(orders, 'amount', x='segment', name='Order sizes', key='fl-box') %}
{% set regions = sigma_report.region_map(orders, 'region', 'us-state', color='Sum([Amount])', name='Regions', key='fl-regions') %}
{% set progress = sigma_report.progress('72', 'fl-progress', min='0', max='100') %}
{% set docs = sigma_report.embed('https://example.com/definitions', 'fl-embed', h=120) %}

{% set spec = sigma_report.report(
    name='Flexible layout',
    pages=[
      sigma_report.page('Nesting', [
        sigma_report.report_header('Rows and stacks nest', 'A stack of KPIs beside a row of charts, one of which is a stack'),
        sigma_report.at(stamp, x=520, y=0, width=200, height=28, overlap=true),
        sigma_report.row([
          sigma_report.stack([revenue, order_count, vs_plan]),
          sigma_report.row([by_region, sigma_report.stack([by_month, by_segment])], widths=[3, 2]),
        ], widths=[1, 3]),
      ]),
      sigma_report.page('Flexible', [
        sigma_report.heading('Heights share what is left'),
        sigma_report.stack([sigma_report.flex(big, weight=2), sigma_report.flex(small), footnote]),
      ]),
      sigma_report.page('Chart family', [
        sigma_report.grid([waterfall, funnel, gauge, sankey, box, regions, progress, docs], per_row=2),
      ], paginate=true),
      sigma_report.page('All orders', [
        sigma_report.heading('Every order, five to a page'),
        sigma_report.table_pages(orders, ['order_id', 'order_date', 'region', 'amount'], rows_per_page=5, total_rows=12,
                                 name='Orders', sort=[('order_id', 'asc')]),
      ], paginate=true),
    ],
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
