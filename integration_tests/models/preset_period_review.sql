{% set spec = sigma_report.simple_period_review(
    name='Monthly review',
    source=sigma_report.from_ref('stg_orders'),
    date_field='order_date',
    period='month',
    kpis=[
        {'value': 'Sum([Amount])', 'name': 'Revenue', 'format': sigma_report.format_currency()},
        {'value': 'Count()', 'name': 'Orders'},
    ],
    breakdowns=['region', 'segment'],
    notes=['Revenue moved with West', 'Action: review SMB pricing'],
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
