{# A dashboard where some elements cover only the last 7 days (last_days + date_column) and the detail is a pivot of totals. #}
{% set spec = sigma_report.simple_dashboard(
    name='Recent sales',
    source=sigma_report.from_ref('stg_orders'),
    date_column='order_date',
    kpis=[
      {'value': 'Sum([Amount])', 'name': 'Revenue'},
      {'value': 'Sum([Amount])', 'name': 'Revenue past week', 'last_days': 7},
    ],
    charts=[
      {'type': 'line', 'x': 'order_date', 'y': 'Sum([Amount])', 'name': 'Revenue by day'},
      {'type': 'bar', 'x': 'region', 'y': 'Sum([Amount])', 'name': 'Revenue by region (week)', 'last_days': 7},
    ],
    table_pivot={'rows': ['region', 'segment'], 'values': ['Sum([Amount])', 'Count()'], 'name': 'Week by region and segment', 'last_days': 7, 'h': 'fill'},
) %}
{% set spec = sigma_report.filter_by_value(spec, 'region', ['West', 'East']) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
