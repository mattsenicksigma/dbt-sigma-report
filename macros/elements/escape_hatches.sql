{# Escape hatches: the package models the common cases, and Sigma's schema has hundreds of options
   beyond them. These macros make sure a missing option is never a dead end - and that using one is not
   a leap into unchecked JSON.

   extend(el, options)
       Deep-merges raw Sigma properties onto an element you built with a normal macro. Nested mappings
       merge (so you can add one key to `xAxis` without restating the rest); anything else replaces.
       The element is updated in place *and* returned. Every top-level key is checked against the
       properties Sigma allows for that element's kind, so a misspelling fails at `dbt parse`.

         {% set chart = sigma_report.extend(
              sigma_report.bar_chart(orders, 'region', 'Count()', name='Orders'),
              {'barStyle': {'cornerRadius': 'round'}, 'gap': {'width': 'small'}}) %}

   raw(kind, key, properties, h)
       An element of any Sigma kind this package has no macro for yet. `properties` are Sigma's own
       fields, used as written; the element still takes part in layout, duplicate-id checks and
       private-key stripping like any other. The kind must be one Sigma's report schema defines, every
       property Sigma requires for it must be present, and every property given must exist on it -
       all checked at `dbt parse` against `element_kinds()` (generated from the schema).

         {% set sla = sigma_report.raw('gauge-chart', 'sla', {'source': ..., 'columns': [...],
                                                               'value': {'columnId': ...}}) %}

   Raw properties' *values* are not checked here (the macros cannot know every rule);
   scripts/validate_against_sigma_schema.py checks them against Sigma's published schema in CI, and
   `export_reports.py --push --dry-run` against your organization. For the common kinds, prefer the typed
   macros (`gauge_chart`, `combo_chart`, ...) which build the columns for you. #}


{# What Sigma's schema says about an element kind: {"required": [...], "properties": [...]}. Raises on a
   kind it does not define, naming the ones it does. #}
{% macro kind_info(kind, where) %}
{% set all = sigma_report.element_kinds() %}
{% if kind not in all %}
  {% do sigma_report.fail(where, "'" ~ kind ~ "' is not an element kind in Sigma's report schema - it defines: " ~ (all.keys() | list | sort | join(', ')) ~ ".") %}
{% endif %}
{% do return({"required": all[kind]['required'].split(','), "properties": all[kind]['properties'].split(',')}) %}
{% endmacro %}


{# Raises on a property Sigma does not define for `kind`, and (with `require`) on a missing required one. #}
{% macro check_properties(kind, properties, where, require=false) %}
{% set info = sigma_report.kind_info(kind, where) %}
{% for k in properties.keys() %}
  {% if k not in info['properties'] %}
    {% do sigma_report.fail(where, "'" ~ k ~ "' is not a property of a " ~ kind ~ " - Sigma allows: " ~ (info['properties'] | join(', ')) ~ ".") %}
  {% endif %}
{% endfor %}
{% if require %}
  {% set needed = [] %}
  {% for r in info['required'] if r not in ['id', 'kind'] %}{% do needed.append(r) %}{% endfor %}
  {% for r in needed if r not in properties %}
    {% do sigma_report.fail(where, "a " ~ kind ~ " requires '" ~ r ~ "' (Sigma requires: " ~ (needed | join(', ')) ~ ").") %}
  {% endfor %}
{% endif %}
{% endmacro %}


{% macro extend(el, options) %}
{% if el is not mapping or 'id' not in el %}
  {% do sigma_report.fail('extend', "expected an element built by a sigma_report macro, got " ~ el) %}
{% endif %}
{% for k in options.keys() %}
  {% if k.startswith('_') or k in ['id', 'kind'] %}
    {% do sigma_report.fail('extend', "'" ~ k ~ "' can't be overridden - it is managed by the package.") %}
  {% endif %}
{% endfor %}
{% do sigma_report.check_properties(el['kind'], options, 'extend') %}
{% for k in options.keys() %}
  {% if k in el and el[k] is mapping and options[k] is mapping %}
    {% do el.update({k: sigma_report.deep_merge(el[k], options[k])}) %}
  {% else %}
    {% do el.update({k: options[k]}) %}
  {% endif %}
{% endfor %}
{% do return(el) %}
{% endmacro %}


{% macro raw(kind, key, properties={}, h=none) %}
{% for k in properties.keys() %}
  {% if k.startswith('_') or k in ['id', 'kind'] %}
    {% do sigma_report.fail('raw', "'" ~ k ~ "' can't be set - it is managed by the package.") %}
  {% endif %}
{% endfor %}
{% do sigma_report.check_properties(kind, properties, 'raw', require=true) %}
{% set el = sigma_report.new_element(kind, 'raw', key, none, sigma_report.setting('chart_h', h)) %}
{% do el.update(properties) %}
{% do return(el) %}
{% endmacro %}
