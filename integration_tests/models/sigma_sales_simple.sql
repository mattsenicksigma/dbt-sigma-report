{# The shortest possible report: one source, one KPI, one chart. #}
{% set spec = sigma_report.simple_dashboard(
    name='Sales simple',
    source=sigma_report.from_ref('stg_orders'),
    kpis=[{'value': 'Sum([Amount])', 'name': 'Revenue'}],
    charts=[{'type': 'bar', 'x': 'region', 'y': 'Sum([Amount])', 'name': 'Revenue by region'}],
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
