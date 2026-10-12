{# A full simple_dashboard: title, KPI band, four charts in two rows, and a detail table. #}
{% set spec = sigma_report.simple_dashboard(
    name='Sales at a glance',
    subtitle='Bookings and orders, year to date',
    source=sigma_report.from_ref('stg_orders'),
    kpis=[
      {'value': 'Sum([Amount])', 'name': 'Revenue', 'format': sigma_report.format_currency()},
      {'value': 'Count()', 'name': 'Orders', 'format': sigma_report.format_integer()},
      {'value': 'Sum([Amount])', 'name': 'Revenue vs plan', 'compare_to': 'Sum([Target Amount])',
       'format': sigma_report.format_currency(), 'key': 'revenue-vs-plan'},
    ],
    charts=[
      {'type': 'bar', 'x': 'region', 'y': 'Sum([Amount])', 'name': 'Revenue by region'},
      {'type': 'donut', 'category': 'segment', 'value': 'Sum([Amount])', 'name': 'Revenue by segment'},
      {'type': 'line', 'x': 'DateTrunc("month", [Order Date])', 'y': 'Sum([Amount])', 'name': 'Revenue by month'},
      {'type': 'area', 'x': 'DateTrunc("month", [Order Date])', 'y': 'Count()', 'color': 'segment', 'name': 'Orders by month'},
    ],
    table_columns=['order_id', 'order_date', 'region', 'segment', 'amount'],
    table_sort=[('order_date', 'desc')],
    report_args={'description': 'Compiled by dbt-sigma-report'},
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
