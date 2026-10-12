{# Small helpers shared by every layer. Nothing here knows about Sigma. #}


{# `snake_case` / `kebab-case` / `lowercase` -> `Title Case`, the way Sigma title-cases warehouse
   columns. Anything that already contains an uppercase letter is returned untouched, so 'ARR' and
   'Order ID' survive. #}
{% macro titleize(value) %}
{% set value = value | string %}
{% if value != value | lower %}
  {% do return(value) %}
{% endif %}
{% do return(value.replace('_', ' ').replace('-', ' ').title()) %}
{% endmacro %}


{# Drops keys whose value is none, so optional Sigma fields are omitted rather than emitted as null. #}
{% macro compact(mapping) %}
{% set out = {} %}
{% for k in mapping.keys() %}
  {% if mapping[k] is not none %}
    {% do out.update({k: mapping[k]}) %}
  {% endif %}
{% endfor %}
{% do return(out) %}
{% endmacro %}


{# Recursive dict merge: keys in `override` win; nested mappings merge rather than replace. #}
{% macro deep_merge(base, override) %}
{% set out = {} %}
{% for k in base.keys() %}
  {% do out.update({k: base[k]}) %}
{% endfor %}
{% for k in override.keys() %}
  {% if k in out and out[k] is mapping and override[k] is mapping %}
    {% do out.update({k: sigma_report.deep_merge(out[k], override[k])}) %}
  {% else %}
    {% do out.update({k: override[k]}) %}
  {% endif %}
{% endfor %}
{% do return(out) %}
{% endmacro %}


{# One level of flattening: [a, [b, c], d] -> [a, b, c, d]. Mappings are leaves. Lets every macro that
   takes "elements" accept single elements and lists of elements interchangeably. #}
{% macro flatten(items) %}
{% set out = [] %}
{% for item in items %}
  {% if item is mapping %}
    {% do out.append(item) %}
  {% else %}
    {% for inner in item %}
      {% do out.append(inner) %}
    {% endfor %}
  {% endif %}
{% endfor %}
{% do return(out) %}
{% endmacro %}


{# Raises a compiler error prefixed with the calling macro's name. Every validation in the package goes
   through here so messages read consistently. `execute` is deliberately not checked: specs are
   composed at parse time, and a malformed spec must fail `dbt parse`, not slip into the manifest. #}
{% macro fail(where, message) %}
{% do exceptions.raise_compiler_error('sigma_report.' ~ where ~ ': ' ~ message) %}
{% endmacro %}


{# Recursively drops every `_`-prefixed key: the package's private layout / bookkeeping fields (`_w`,
   `_h`, `_source`, ...), so only real Sigma fields reach the manifest. #}
{% macro strip_private(value) %}
{% if value is mapping %}
  {% set out = {} %}
  {% for k in value.keys() %}
    {% if not k.startswith('_') %}
      {% do out.update({k: sigma_report.strip_private(value[k])}) %}
    {% endif %}
  {% endfor %}
  {% do return(out) %}
{% elif value is sequence and value is not string %}
  {% set out = [] %}
  {% for item in value %}
    {% do out.append(sigma_report.strip_private(item)) %}
  {% endfor %}
  {% do return(out) %}
{% endif %}
{% do return(value) %}
{% endmacro %}
