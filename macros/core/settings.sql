{# Project-level settings: every size and calibration constant the package would otherwise hard-code.

   Override any of them from `dbt_project.yml`; keys you leave out keep the defaults:

     vars:
       sigma_report_settings:
         chart_h: 300            # default height of a chart, px
         margin: 40
         gap: 12
         page_size: a4
         title_size: 32          # px
         table_row_h: 24         # recalibrate if your theme / font draws taller rows
         char_width: 0.6         # em per character, for estimating text height

   A per-call argument (`h=`, `margin=`, ...) always wins over the project setting, which wins over the
   package default. The unit is pixels unless stated, at 96 per inch. Unknown keys fail at `dbt parse`, so a
   typo cannot silently do nothing. #}
{% macro default_settings() %}
{% do return({
  "page_size": "letter",
  "margin": 48,
  "gap": 16,
  "header_height": 48,
  "footer_height": 32,
  "kpi_h": 96,
  "chart_h": 260,
  "pivot_h": 300,
  "map_h": 320,
  "gauge_h": 180,
  "divider_h": 12,
  "image_h": 64,
  "table_rows": 10,
  "table_row_h": 20,
  "table_chrome": 130,
  "table_chrome_untitled": 92,
  "title_size": 28,
  "heading_size": 20,
  "body_size": 14,
  "h1_size": 36,
  "h2_size": 28,
  "h3_size": 22,
  "char_width": 0.55,
  "line_height": 1.35,
  "text_padding": 6,
}) %}
{% endmacro %}


{# The effective settings: package defaults, deep-merged with the `sigma_report_settings` project var. #}
{% macro settings() %}
{% set base = sigma_report.default_settings() %}
{% set override = var('sigma_report_settings', {}) %}
{% for key in override.keys() %}
  {% if key not in base %}
    {% do sigma_report.fail('settings', "unknown key '" ~ key ~ "' in the sigma_report_settings var - known keys: " ~ (base.keys() | list | sort)) %}
  {% endif %}
{% endfor %}
{% do return(sigma_report.deep_merge(base, override)) %}
{% endmacro %}


{# One setting by name. `value` (when not none) wins: this is how an argument that defaults to the project
   setting is written - `h if h is not none else sigma_report.setting('chart_h')` becomes
   `sigma_report.setting('chart_h', h)`. #}
{% macro setting(name, value=none) %}
{% if value is not none %}
  {% do return(value) %}
{% endif %}
{% set all = sigma_report.settings() %}
{% if name not in all %}
  {% do sigma_report.fail('setting', "unknown setting '" ~ name ~ "'.") %}
{% endif %}
{% do return(all[name]) %}
{% endmacro %}
