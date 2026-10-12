{# A report over a dbt source (and, via the project's `relation_path` override in
   integration_tests/macros/overrides.sql, a database other than the target's). #}
{% set spec = sigma_report.simple_dashboard(
    name='Orders from a source',
    source=sigma_report.from_source('raw', 'orders', schema='raw_data'),
    kpis=[{'value': 'Count()', 'name': 'Orders'}],
    charts=[{'type': 'pie', 'category': 'segment', 'value': 'Count()', 'name': 'Orders by segment'}],
    report_args={'page_size': 'screen', 'margin': 32},
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
