{# page_numbers=true next to a footer of your own: the footer's elements share the footer row with the
   number, which sits at the right. #}
{% set spec = sigma_report.report(
    'Footer page numbers',
    [sigma_report.page('Summary', [
        sigma_report.report_header('Footer page numbers'),
        sigma_report.kpi(sigma_report.from_ref('stg_orders'), 'Count()', name='Orders'),
    ])],
    footer=[sigma_report.text('Confidential', key='footer-note')],
    page_numbers=true,
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
