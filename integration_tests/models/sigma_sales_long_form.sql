{# Heights that depend on content: a title long enough to wrap, a paragraph in a narrow cell, a table sized by
   how many rows it shows, and a table that takes the rest of its page. #}
{% set orders = sigma_report.from_ref('stg_orders') %}

{% set narrow_note = sigma_report.text(
    'Revenue is summed over every order in the period. Orders without a region are counted under "Other" and are included in the totals shown on this page.',
    key='narrow-note') %}
{% set wide_note = sigma_report.text('Short note.', key='wide-note') %}

{% set spec = sigma_report.report(
    name='Sales long form',
    pages=[
      sigma_report.page('Overview', [
        sigma_report.report_header(
          'Quarterly sales performance review for the whole of the North American and European regions',
          'Prepared for the finance and revenue operations leadership teams'),
        sigma_report.row([narrow_note, sigma_report.kpi(orders, 'Sum([Amount])', name='Revenue')], widths=[1, 2]),
        wide_note,
        sigma_report.table(orders, ['order_id', 'order_date', 'region', 'amount'], name='Top orders',
                           key='top-orders', rows=5, sort=[('amount', 'desc')]),
      ]),
      sigma_report.page('Full list', [
        sigma_report.heading('Every order'),
        sigma_report.table(orders, ['order_id', 'order_date', 'region', 'segment', 'amount'], name='All orders',
                           key='all-orders', h='fill', sort=[('order_date', 'desc')]),
      ]),
    ],
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
