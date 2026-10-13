{# Paginated (expanded) tables: a table that ends its page, a pivot that ends its page, and the page
   number the report adds to the footer. Each paginated element is the last block on its page. #}
{% set orders = sigma_report.from_ref('stg_orders') %}

{% set spec = sigma_report.report(
    'Paginated tables',
    [
        sigma_report.page('Orders', [
            sigma_report.report_header('Every order'),
            sigma_report.table(orders, ['order_id', 'order_date', 'region', 'amount'], name='Orders', h=200, paginate=true),
        ]),
        sigma_report.page('Revenue', [
            sigma_report.heading('Revenue by region and segment'),
            sigma_report.pivot_table(orders, 'Sum([Amount])', rows='region', cols='segment', name='Revenue pivot', h=200, paginate=true),
        ]),
    ],
    page_numbers=true,
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
