{# Invalid input must fail at `dbt parse` with a message that names the macro and the problem. Each macro
   here makes exactly one bad call; integration_tests/negative_cases.txt lists the text each must raise,
   and scripts/run_integration_tests_duckdb.sh runs them with `dbt run-operation` and checks the two files
   agree one to one. #}

{% macro _src() %}
{% do return(sigma_report.warehouse_table(['db', 'schema', 'orders'], connection_id='conn')) %}
{% endmacro %}


{% macro _filterable_spec() %}
{% do return(sigma_report.simple_dashboard(name='n', source=sigma_report_integration_tests._src(), kpis=[{'value': 'Count()', 'name': 'Orders'}])) %}
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
{% macro assert_filter_empty_values_rejected() %}{% do sigma_report.filter_by_value(sigma_report_integration_tests._filterable_spec(), 'region', []) %}{% endmacro %}
{% macro assert_filter_bad_mode_rejected() %}{% do sigma_report.filter_by_value(sigma_report_integration_tests._filterable_spec(), 'region', ['West'], mode='maybe') %}{% endmacro %}
{% macro assert_filter_nothing_to_filter_rejected() %}{% do sigma_report.filter_by_value(sigma_report.report(name='n', pages=[sigma_report.page('p', [sigma_report.divider()])]), 'region', ['West']) %}{% endmacro %}
{% macro assert_filter_twice_rejected() %}{% do sigma_report.filter_by_value(sigma_report.filter_by_value(sigma_report_integration_tests._filterable_spec(), 'region', ['West']), 'region', ['East']) %}{% endmacro %}
{% macro assert_last_days_without_date_column_rejected() %}{% do sigma_report.simple_dashboard(name='n', source=sigma_report_integration_tests._src(), kpis=[{'value': 'Count()', 'name': 'Orders', 'last_days': 7}]) %}{% endmacro %}
{% macro assert_last_days_zero_rejected() %}{% do sigma_report.filter_last_days(sigma_report.kpi(sigma_report_integration_tests._src(), 'Count()', name='n'), 'order_date', 0) %}{% endmacro %}
{% macro assert_last_days_fractional_rejected() %}{% do sigma_report.filter_last_days(sigma_report.kpi(sigma_report_integration_tests._src(), 'Count()', name='n'), 'order_date', 7.5) %}{% endmacro %}
{% macro assert_last_days_twice_rejected() %}{% do sigma_report.filter_last_days(sigma_report.filter_last_days(sigma_report.kpi(sigma_report_integration_tests._src(), 'Count()', name='n'), 'order_date', 7), 'order_date', 3) %}{% endmacro %}
{% macro assert_last_days_non_warehouse_rejected() %}{% do sigma_report.filter_last_days(sigma_report.divider(), 'order_date', 7) %}{% endmacro %}
{% macro assert_table_and_pivot_rejected() %}{% do sigma_report.simple_dashboard(name='n', source=sigma_report_integration_tests._src(), table_columns=['region'], table_pivot={'rows': ['region'], 'values': ['Count()']}) %}{% endmacro %}
{% macro assert_raw_protected_key_rejected() %}{% do sigma_report.raw('embed', 'e', {'kind': 'text'}) %}{% endmacro %}
{% macro assert_unknown_chart_type_rejected() %}{% do sigma_report.chart_from_spec(sigma_report_integration_tests._src(), {'type': 'radar'}) %}{% endmacro %}
{% macro assert_chart_spec_without_type_rejected() %}{% do sigma_report.chart_from_spec(sigma_report_integration_tests._src(), {'x': 'a'}) %}{% endmacro %}
{% macro assert_kpi_spec_without_value_rejected() %}{% do sigma_report.kpi_from_spec(sigma_report_integration_tests._src(), {'name': 'n'}) %}{% endmacro %}

{# ---- layout ---- #}
{% macro assert_empty_row_rejected() %}{% do sigma_report.row([]) %}{% endmacro %}
{% macro assert_row_widths_mismatch_rejected() %}{% do sigma_report.row([sigma_report.divider(), sigma_report.divider('d2')], widths=[1]) %}{% endmacro %}
{% macro assert_row_bad_width_rejected() %}{% do sigma_report.row([sigma_report.divider()], widths=[0]) %}{% endmacro %}
{% macro assert_empty_stack_rejected() %}{% do sigma_report.stack([]) %}{% endmacro %}
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
{# ---- heights ---- #}
{% macro assert_bad_height_word_rejected() %}{% do sigma_report.divider('d', h='tall') %}{% endmacro %}
{% macro assert_zero_table_rows_rejected() %}{% do sigma_report.table(sigma_report_integration_tests._src(), ['a'], name='n', rows=0) %}{% endmacro %}
{% macro assert_fill_without_room_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a', h=900), sigma_report.table(sigma_report_integration_tests._src(), ['a'], name='n', h='fill')])]) %}
{% endmacro %}
{# ---- flexible layout ---- #}
{% macro assert_bad_flex_weight_rejected() %}{% do sigma_report.flex(sigma_report.divider('d'), weight=0) %}{% endmacro %}
{% macro assert_flex_non_block_rejected() %}{% do sigma_report.flex('text') %}{% endmacro %}
{% macro assert_at_in_row_rejected() %}{% do sigma_report.row([sigma_report.at(sigma_report.divider('d'), 0, 0, 10, 10)]) %}{% endmacro %}
{% macro assert_at_in_stack_rejected() %}{% do sigma_report.stack([sigma_report.at(sigma_report.divider('d'), 0, 0, 10, 10)]) %}{% endmacro %}
{% macro assert_at_of_row_rejected() %}{% do sigma_report.at(sigma_report.row([sigma_report.divider('d')]), 0, 0, 10, 10) %}{% endmacro %}
{% macro assert_at_bad_size_rejected() %}{% do sigma_report.at(sigma_report.divider('d'), 0, 0, 0, 10) %}{% endmacro %}
{% macro assert_at_outside_page_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.at(sigma_report.divider('d'), 700, 0, 100, 10)])]) %}
{% endmacro %}
{% macro assert_break_in_row_rejected() %}{% do sigma_report.row([sigma_report.page_break()]) %}{% endmacro %}
{% macro assert_break_without_paginate_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a'), sigma_report.page_break(), sigma_report.divider('b')])]) %}
{% endmacro %}

{# ---- table windows ---- #}
{% macro assert_bad_window_rejected() %}{% do sigma_report.table(sigma_report_integration_tests._src(), ['a'], name='n', sort=['a'], window=[5, 2]) %}{% endmacro %}
{% macro assert_window_without_sort_rejected() %}{% do sigma_report.table(sigma_report_integration_tests._src(), ['a'], name='n', window=[1, 5]) %}{% endmacro %}
{% macro assert_table_pages_without_count_rejected() %}{% do sigma_report.table_pages(sigma_report_integration_tests._src(), ['a'], 10, name='n', sort=['a']) %}{% endmacro %}
{% macro assert_table_pages_both_counts_rejected() %}{% do sigma_report.table_pages(sigma_report_integration_tests._src(), ['a'], 10, pages=2, total_rows=20, name='n', sort=['a']) %}{% endmacro %}
{% macro assert_table_pages_unnamed_rejected() %}{% do sigma_report.table_pages(sigma_report_integration_tests._src(), ['a'], 10, pages=2, sort=['a']) %}{% endmacro %}

{# ---- raw / extend are checked against Sigma's schema ---- #}
{% macro assert_raw_unknown_kind_rejected() %}{% do sigma_report.raw('hologram', 'k', {}) %}{% endmacro %}
{% macro assert_raw_missing_required_rejected() %}{% do sigma_report.raw('embed', 'k', {}) %}{% endmacro %}
{% macro assert_raw_unknown_property_rejected() %}{% do sigma_report.raw('embed', 'k', {'url': 'https://example.com', 'urll': 'x'}) %}{% endmacro %}
{% macro assert_extend_unknown_property_rejected() %}{% do sigma_report.extend(sigma_report.divider('d'), {'colour': 'red'}) %}{% endmacro %}

{# ---- typed charts ---- #}
{% macro assert_combo_series_mismatch_rejected() %}{% do sigma_report.combo_chart(sigma_report_integration_tests._src(), 'a', ['Count()', 'Sum([b])'], series_types=['bar'], name='n') %}{% endmacro %}
{% macro assert_combo_bad_series_type_rejected() %}{% do sigma_report.combo_chart(sigma_report_integration_tests._src(), 'a', ['Count()'], series_types=['bars'], name='n') %}{% endmacro %}
{% macro assert_combo_bad_secondary_rejected() %}{% do sigma_report.combo_chart(sigma_report_integration_tests._src(), 'a', ['Count()'], secondary=[3], name='n') %}{% endmacro %}
{% macro assert_region_map_bad_type_rejected() %}{% do sigma_report.region_map(sigma_report_integration_tests._src(), 'a', 'planet', name='n') %}{% endmacro %}
{% macro assert_sankey_one_stage_rejected() %}{% do sigma_report.sankey_chart(sigma_report_integration_tests._src(), ['a'], 'Count()', name='n') %}{% endmacro %}
{% macro assert_bad_color_by_rejected() %}{% do sigma_report.treemap_chart(sigma_report_integration_tests._src(), 'a', 'Count()', color='b', color_by='rainbow', name='n') %}{% endmacro %}
{% macro assert_progress_bad_mode_rejected() %}{% do sigma_report.progress('1', 'p', mode='half') %}{% endmacro %}

{# ---- settings ---- #}
{% macro assert_unknown_setting_rejected() %}{% do sigma_report.settings() %}{% endmacro %}
{% macro assert_no_room_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a')])], margin=600) %}
{% endmacro %}

{# ---- presets ---- #}
{% macro assert_preset_without_kpis_rejected() %}{% do sigma_report.simple_executive_summary('r', sigma_report_integration_tests._src(), []) %}{% endmacro %}
{% macro assert_statement_without_columns_rejected() %}{% do sigma_report.simple_statement('r', sigma_report_integration_tests._src(), []) %}{% endmacro %}
{% macro assert_bad_facts_rejected() %}{% do sigma_report.facts_line(['owner']) %}{% endmacro %}

{# ---- pagination and page numbers ---- #}
{% macro assert_paginated_in_row_rejected() %}{% do sigma_report.row([sigma_report.table(sigma_report_integration_tests._src(), ['a'], name='t', paginate=true)]) %}{% endmacro %}
{% macro assert_paginated_in_stack_rejected() %}{% do sigma_report.stack([sigma_report.table(sigma_report_integration_tests._src(), ['a'], name='t', paginate=true)]) %}{% endmacro %}
{% macro assert_paginated_not_last_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.table(sigma_report_integration_tests._src(), ['a'], name='t', paginate=true), sigma_report.divider('after')])]) %}
{% endmacro %}
{% macro assert_paginated_in_footer_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a')])], footer=[sigma_report.table(sigma_report_integration_tests._src(), ['a'], name='t', paginate=true)]) %}
{% endmacro %}
{% macro assert_page_numbers_with_footer_row_rejected() %}
{% do sigma_report.report('r', [sigma_report.page('p', [sigma_report.divider('a')])], footer=[sigma_report.row([sigma_report.divider('f')])], page_numbers=true) %}
{% endmacro %}
{% macro assert_bad_page_number_format_rejected() %}{% do sigma_report.page_number('nothing to see') %}{% endmacro %}
{% macro assert_statement_footer_conflict_rejected() %}
{% do sigma_report.simple_statement('r', sigma_report_integration_tests._src(), ['a'], footer_note='n', report_args={'footer': [sigma_report.divider('f')]}) %}
{% endmacro %}
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
