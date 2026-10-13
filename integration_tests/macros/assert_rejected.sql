{# Invalid input must fail at `dbt parse` with a message that names the macro and the problem. Each macro
   here makes exactly one bad call; integration_tests/negative_cases.txt lists the text each must raise,
   and scripts/run_integration_tests_duckdb.sh runs them with `dbt run-operation` and checks the two files
   agree one to one. #}

{% macro _src() %}
{% do return(sigma_report.warehouse_table(['db', 'schema', 'orders'], connection_id='conn')) %}
{% endmacro %}


{# ---- theme ---- #}
{% macro assert_unknown_hue_rejected() %}{% do sigma_report.theme({'hue': 'Chartreuse'}) %}{% endmacro %}
{% macro assert_unknown_base_rejected() %}{% do sigma_report.theme({'base': 'Marble'}) %}{% endmacro %}
{% macro assert_unknown_color_token_rejected() %}{% do sigma_report.color('prymary') %}{% endmacro %}

{# ---- sources ---- #}
{% macro assert_missing_connection_rejected() %}{% do sigma_report.warehouse_table(['db', 'schema', 'orders']) %}{% endmacro %}
{% macro assert_short_path_rejected() %}{% do sigma_report.warehouse_table(['schema', 'orders'], connection_id='conn') %}{% endmacro %}
{% macro assert_bad_source_rejected() %}{% do sigma_report.kpi('stg_orders', 'Count()', name='n') %}{% endmacro %}
{% macro assert_bad_element_source_rejected() %}{% do sigma_report.element({'kind': 'table'}) %}{% endmacro %}

{# ---- fields ---- #}
{% macro assert_bad_field_rejected() %}{% do sigma_report.bar_chart(sigma_report_integration_tests._src(), 5, 'Count()', name='n') %}{% endmacro %}

{# ---- elements ---- #}
{% macro assert_unnamed_element_rejected() %}{% do sigma_report.bar_chart(sigma_report_integration_tests._src(), 'region', 'Count()') %}{% endmacro %}
{% macro assert_bad_height_rejected() %}{% do sigma_report.bar_chart(sigma_report_integration_tests._src(), 'region', 'Count()', name='n', h=0) %}{% endmacro %}
{% macro assert_bad_sort_direction_rejected() %}{% do sigma_report.bar_chart(sigma_report_integration_tests._src(), 'region', 'Count()', name='n', sort_direction='sideways') %}{% endmacro %}
{% macro assert_table_without_columns_rejected() %}{% do sigma_report.table(sigma_report_integration_tests._src(), [], name='n') %}{% endmacro %}
{% macro assert_pivot_without_axes_rejected() %}{% do sigma_report.pivot_table(sigma_report_integration_tests._src(), 'Count()', name='n') %}{% endmacro %}
{% macro assert_extend_protected_key_rejected() %}{% do sigma_report.extend(sigma_report.divider(), {'id': 'x'}) %}{% endmacro %}
{% macro assert_extend_non_element_rejected() %}{% do sigma_report.extend({'a': 1}, {'b': 2}) %}{% endmacro %}
{% macro assert_raw_protected_key_rejected() %}{% do sigma_report.raw('embed', 'e', {'kind': 'text'}) %}{% endmacro %}
{% macro assert_unknown_chart_type_rejected() %}{% do sigma_report.chart_from_spec(sigma_report_integration_tests._src(), {'type': 'radar'}) %}{% endmacro %}
{% macro assert_chart_spec_without_type_rejected() %}{% do sigma_report.chart_from_spec(sigma_report_integration_tests._src(), {'x': 'a'}) %}{% endmacro %}
{% macro assert_kpi_spec_without_value_rejected() %}{% do sigma_report.kpi_from_spec(sigma_report_integration_tests._src(), {'name': 'n'}) %}{% endmacro %}

{# ---- layout ---- #}
{% macro assert_empty_row_rejected() %}{% do sigma_report.row([]) %}{% endmacro %}
{% macro assert_row_widths_mismatch_rejected() %}{% do sigma_report.row([sigma_report.divider(), sigma_report.divider('d2')], widths=[1]) %}{% endmacro %}
{% macro assert_row_bad_width_rejected() %}{% do sigma_report.row([sigma_report.divider()], widths=[0]) %}{% endmacro %}
{% macro assert_nested_row_rejected() %}{% do sigma_report.row([sigma_report.row([sigma_report.divider()])]) %}{% endmacro %}
{% macro assert_empty_stack_rejected() %}{% do sigma_report.stack([]) %}{% endmacro %}
{% macro assert_stack_of_row_rejected() %}{% do sigma_report.stack([sigma_report.row([sigma_report.divider()])]) %}{% endmacro %}
{% macro assert_loose_stack_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.stack([sigma_report.divider('a')])])]) %}
{% endmacro %}
{% macro assert_unknown_page_size_rejected() %}{% do sigma_report.page_dimensions('postcard', none) %}{% endmacro %}
{% macro assert_bad_custom_page_size_rejected() %}{% do sigma_report.page_dimensions({'width': 800}, none) %}{% endmacro %}
{% macro assert_bad_orientation_rejected() %}{% do sigma_report.page_dimensions('letter', 'diagonal') %}{% endmacro %}

{# ---- report ---- #}
{% macro assert_empty_report_rejected() %}{% do sigma_report.report('r', []) %}{% endmacro %}
{% macro assert_empty_page_rejected() %}{% do sigma_report.page('p', []) %}{% endmacro %}
{% macro assert_duplicate_page_names_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a')], key='one'), sigma_report.page('p', [sigma_report.divider('b')], key='two')]) %}
{% endmacro %}
{% macro assert_duplicate_element_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('same'), sigma_report.divider('same')])]) %}
{% endmacro %}
{% macro assert_page_overflow_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a', h=600), sigma_report.divider('b', h=600)])]) %}
{% endmacro %}
{% macro assert_block_taller_than_page_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a', h=5000)], paginate=true)]) %}
{% endmacro %}
{% macro assert_no_room_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a')])], margin=600) %}
{% endmacro %}

{# ---- presets ---- #}
{% macro assert_preset_without_kpis_rejected() %}{% do sigma_report.simple_executive_summary('r', sigma_report_integration_tests._src(), []) %}{% endmacro %}
{% macro assert_statement_without_columns_rejected() %}{% do sigma_report.simple_statement('r', sigma_report_integration_tests._src(), []) %}{% endmacro %}
{% macro assert_bad_facts_rejected() %}{% do sigma_report.facts_line(['owner']) %}{% endmacro %}

{# ---- actions and schedules ---- #}
{% macro assert_unknown_trigger_rejected() %}{% do sigma_report.action('on-hover', [sigma_report.refresh_element('e')]) %}{% endmacro %}
{% macro assert_action_without_effects_rejected() %}{% do sigma_report.action('on-click', []) %}{% endmacro %}
{% macro assert_action_bad_effect_rejected() %}{% do sigma_report.action('on-click', ['refresh']) %}{% endmacro %}
{% macro assert_with_actions_non_element_rejected() %}{% do sigma_report.with_actions({'a': 1}, []) %}{% endmacro %}
{% macro assert_duplicate_actions_rejected() %}{% set b = sigma_report.button('Go', key='go') %}{% set fx = [sigma_report.open_url('https://example.com')] %}{% do sigma_report.with_actions(b, [sigma_report.action('on-click', fx, key='k')]) %}{% do sigma_report.with_actions(b, [sigma_report.action('on-click', fx, key='k')]) %}{% endmacro %}
{% macro assert_bad_button_appearance_rejected() %}{% do sigma_report.button('Go', appearance='glossy') %}{% endmacro %}
{% macro assert_navigate_needs_one_target_rejected() %}{% do sigma_report.navigate() %}{% endmacro %}
{% macro assert_bad_effect_reference_rejected() %}{% do sigma_report.refresh_element(5) %}{% endmacro %}
{% macro assert_bad_download_format_rejected() %}{% do sigma_report.download('docx') %}{% endmacro %}
{% macro assert_bad_cron_rejected() %}{% do sigma_report.schedule('s', cron='weekly', to=['a@example.com']) %}{% endmacro %}
{% macro assert_schedule_without_recipients_rejected() %}{% do sigma_report.schedule('s', cron='0 8 * * 1', to=[]) %}{% endmacro %}
{% macro assert_bad_recipient_rejected() %}{% do sigma_report.schedule('s', cron='0 8 * * 1', to=['nobody']) %}{% endmacro %}
{% macro assert_two_schedule_conditions_rejected() %}{% do sigma_report.schedule('s', cron='0 8 * * 1', to=['a@example.com'], only_if_empty='e', only_if_not_empty='e') %}{% endmacro %}
{% macro assert_duplicate_schedule_names_rejected() %}{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider()])], schedules=[sigma_report.schedule('s', cron='0 8 * * 1', to=['a@example.com']), sigma_report.schedule('s', cron='0 9 * * 1', to=['a@example.com'])]) %}{% endmacro %}
