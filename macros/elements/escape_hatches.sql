{# Escape hatches: the package models the common cases, and Sigma's schema has hundreds of options
   beyond them. These two macros make sure a missing option is never a dead end.

   extend(el, options)
       Deep-merges raw Sigma properties onto an element you built with a normal macro. Nested mappings
       merge (so you can add one key to `xAxis` without restating the rest); anything else replaces.
       The element is updated in place *and* returned.

         {% set chart = sigma_report.extend(
              sigma_report.bar_chart(orders, 'region', 'Count()', name='Orders'),
              {'barStyle': {'cornerRadius': 'round'}, 'gap': {'width': 'small'}}) %}

   raw(kind, key, properties, h)
       An element of any Sigma kind this package has no macro for yet (gauge-chart, combo-chart,
       funnel-chart, embed, report-repeated-container, ...). `properties` are Sigma's own fields, used as
       written; the element still takes part in layout, duplicate-id checks and private-key stripping
       like any other.

         {% set gauge = sigma_report.raw('gauge-chart', 'sla', {...}, h=200) %}

   Raw properties are not validated by this package (it cannot know every kind's rules). Run
   scripts/validate_against_sigma_schema.py to check them against Sigma's published schema. #}
{% macro extend(el, options) %}
{% if el is not mapping or 'id' not in el %}
  {% do sigma_report.fail('extend', "expected an element built by a sigma_report macro, got " ~ el) %}
{% endif %}
{% for k in options.keys() %}
  {% if k.startswith('_') or k in ['id', 'kind'] %}
    {% do sigma_report.fail('extend', "'" ~ k ~ "' can't be overridden - it is managed by the package.") %}
  {% endif %}
  {% if k in el and el[k] is mapping and options[k] is mapping %}
    {% do el.update({k: sigma_report.deep_merge(el[k], options[k])}) %}
  {% else %}
    {% do el.update({k: options[k]}) %}
  {% endif %}
{% endfor %}
{% do return(el) %}
{% endmacro %}


{% macro raw(kind, key, properties={}, h=120) %}
{% set el = sigma_report.new_element(kind, 'raw', key, none, h) %}
{% for k in properties.keys() %}
  {% if k.startswith('_') or k in ['id', 'kind'] %}
    {% do sigma_report.fail('raw', "'" ~ k ~ "' can't be set - it is managed by the package.") %}
  {% endif %}
{% endfor %}
{% do el.update(properties) %}
{% do return(el) %}
{% endmacro %}
