{# simple_dashboard with show_title=false: no title, subtitle or rule above the KPIs. #}
{% set spec = sigma_report.simple_dashboard(
    name='Sales untitled',
    subtitle='Never shown',
    source=sigma_report.from_ref('stg_orders'),
    kpis=[{'value': 'Sum([Amount])', 'name': 'Revenue'}],
    charts=[{'type': 'bar', 'x': 'region', 'y': 'Sum([Amount])', 'name': 'Revenue by region'}],
    show_title=false,
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
