{% set spec = sigma_report.simple_leaderboard(
    name='Regional standings',
    source=sigma_report.from_ref('stg_orders'),
    dimensions=['region', 'segment'],
    measure='Sum([Amount])',
    measure_name='Revenue',
    measure_format=sigma_report.format_currency(),
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
