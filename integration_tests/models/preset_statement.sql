{% set spec = sigma_report.simple_statement(
    name='Customer statement',
    source=sigma_report.from_ref('stg_orders'),
    facts=[['Statement', 'ST-2026-10'], ['Customer', 'Example Co'], ['Due', '2026-11-15']],
    columns=['order_id', 'order_date', 'region', 'amount'],
    rows_sort=[('order_date', 'asc')],
    totals=[{'value': 'Sum([Amount])', 'name': 'Total due', 'format': sigma_report.format_currency(2)}],
    footer_note='Payment terms: net 30.',
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
