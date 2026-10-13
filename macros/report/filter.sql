{# Restricts a finished report to the given values of one source column, so one general model can feed
   a report scoped to a single entity (a customer, an API key, ...) without hard-coding that scope in the
   model. Reports have no controls, so the scope is a fixed filter on each element.

     {% set spec = sigma_report.simple_dashboard(...) %}
     {% set spec = sigma_report.filter_by_value(spec, 'region', ['West']) %}
     {{ sigma_report.materialize(spec) }}

   To every element built on a warehouse table it adds a hidden column for `column` (a bare lowercase
   name is title-cased the way Sigma shows it; anything else is used as written) and a `list` filter on
   that column. Elements with no warehouse source (text, dividers) and elements built on another element
   are left alone: the latter inherit the filter from the element they are built on. Fails when no
   element could be filtered, so a report is never silently left unscoped. The spec is updated in place
   and returned. #}
{% macro filter_by_value(spec, column, values, mode='include') %}
{% if spec is not mapping or spec.get('contents') is not mapping or spec['contents'].get('elements') is none %}
  {% do sigma_report.fail('filter_by_value', "expected a finished report spec (from report() or a simple_* macro), got " ~ spec) %}
{% endif %}
{% if column is not string or not column %}
  {% do sigma_report.fail('filter_by_value', "column must be a non-empty string, got " ~ column) %}
{% endif %}
{% if values is string or values is not sequence or values | length == 0 %}
  {% do sigma_report.fail('filter_by_value', "values must be a non-empty list, got " ~ values) %}
{% endif %}
{% if mode not in ['include', 'exclude'] %}
  {% do sigma_report.fail('filter_by_value', "mode must be 'include' or 'exclude', got '" ~ mode ~ "'") %}
{% endif %}
{% set label = sigma_report.titleize(column) %}
{% set filtered = namespace(count=0) %}
{% for el in spec['contents']['elements'] %}
  {% set source = el.get('source') %}
  {% if source is mapping and source.get('kind') == 'warehouse-table' %}
    {% set column_id = sigma_report.freeze_id(el['id'] ~ ':filter:' ~ column) %}
    {% if 'columns' not in el %}{% do el.update({'columns': []}) %}{% endif %}
    {% for existing in el['columns'] if existing['id'] == column_id %}
      {% do sigma_report.fail('filter_by_value', "element '" ~ el['id'] ~ "' is already filtered on '" ~ column ~ "'") %}
    {% endfor %}
    {% do el['columns'].append({"id": column_id, "formula": '[' ~ source['path'][-1] ~ '/' ~ label ~ ']', "hidden": true}) %}
    {% set filters = el.get('filters') or [] %}
    {% do filters.append({
      "id": sigma_report.freeze_id(el['id'] ~ ':filter-list:' ~ column),
      "columnId": column_id,
      "kind": "list",
      "mode": mode,
      "values": values,
    }) %}
    {% do el.update({"filters": filters}) %}
    {% set filtered.count = filtered.count + 1 %}
  {% endif %}
{% endfor %}
{% if filtered.count == 0 %}
  {% do sigma_report.fail('filter_by_value', "no element is built on a warehouse table, so there is nothing to filter") %}
{% endif %}
{% do return(spec) %}
{% endmacro %}
