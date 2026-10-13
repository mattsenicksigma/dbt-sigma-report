{% set spec = sigma_report.simple_executive_summary(
    name='Executive summary',
    source=sigma_report.from_ref('stg_orders'),
    subtitle='Bookings against plan',
    kpis=[
        {'value': 'Sum([Amount])', 'name': 'Revenue', 'format': sigma_report.format_currency(), 'compare_to': 'Sum([Target Amount])', 'compare_label': 'plan'},
        {'value': 'Count()', 'name': 'Orders'},
        {'value': 'Avg([Amount])', 'name': 'Average order', 'format': sigma_report.format_currency()},
    ],
    chart={'type': 'line', 'x': 'DateTrunc("month", [Order Date])', 'y': 'Sum([Amount])', 'name': 'Revenue by month', 'legend': false},
    highlights=['Enterprise carries most of the revenue', 'SMB is running below plan'],
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
