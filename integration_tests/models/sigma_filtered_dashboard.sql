{# A dashboard scoped to one region with filter_by_value: the model stays general, the report is not. #}
{% set spec = sigma_report.simple_dashboard(
    name='West region sales',
    source=sigma_report.from_ref('stg_orders'),
    kpis=[{'value': 'Sum([Amount])', 'name': 'Revenue'}],
    charts=[{'type': 'bar', 'x': 'segment', 'y': 'Sum([Amount])', 'name': 'Revenue by segment'}],
    table_columns=['order_id', 'region', 'amount'],
) %}
{% set spec = sigma_report.filter_by_value(spec, 'region', ['West']) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
