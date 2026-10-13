{# Actions and a schedule: a button with a refresh / navigate / download sequence, an action added to an
   existing table, and a scheduled PDF that only goes out when the table has rows. #}
{% set orders = sigma_report.from_ref('stg_orders') %}

{% set detail = sigma_report.table(orders, ['order_id', 'order_date', 'region', 'amount'], name='Orders', h=240) %}
{% set notes = sigma_report.page('Notes', [sigma_report.text('Notes go here.', key='notes-body')]) %}

{% set actions_bar = sigma_report.row([
    sigma_report.button('Refresh orders', key='refresh', h=40, actions=[
        sigma_report.action('on-click', [
            sigma_report.refresh_element(detail),
            sigma_report.navigate(page=notes),
        ]),
    ]),
    sigma_report.button('Download PDF', key='download', appearance='outline', actions=[
        sigma_report.action('on-click', [sigma_report.download('pdf', layout='landscape', page_size='a4')]),
    ]),
    sigma_report.button('Reset filters', key='reset', appearance='text', align='right', actions=[
        sigma_report.action('on-click', [
            sigma_report.clear_controls('page'),
            sigma_report.set_control_value('region-control', 'West'),
            sigma_report.open_url('https://example.com/help'),
        ], key='reset-sequence'),
    ]),
]) %}

{# an action on an element that already exists, and an effect with no builder #}
{% do sigma_report.with_actions(detail, [
    sigma_report.action('on-select', [sigma_report.effect('call-api', {'connectorId': '<your-connector-id>'})]),
]) %}

{% set spec = sigma_report.report(
    name='Actions report',
    pages=[
      sigma_report.page('Summary', [actions_bar, sigma_report.heading('Orders'), detail], key='Summary'),
      notes,
    ],
    schedules=[
      sigma_report.schedule('Weekly orders', cron='0 8 * * 1', timezone='America/New_York',
          to=['finance@example.com', {'teamId': '<your-team-id>'}], message='Orders this week.',
          layout='landscape', only_if_not_empty=detail),
      sigma_report.schedule('Monthly orders', cron='0 6 1 * *', to=['finance@example.com'],
          options={'attachmentSettings': {'zipAttachments': true}}),
    ],
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
