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


{# Restricts one element to rows from the last `days` days of a date column, relative to the day the
   report renders. Reports have no controls, so a "last 7 days" chart cannot be a filter someone sets:
   it is part of the element.

     sigma_report.filter_last_days(sigma_report.bar_chart(...), 'activity_date', 7)

   The element gets a hidden 0/1 column (`If([Activity Date] >= DateAdd("day", -7, Today()), 1, 0)`, so
   `Today()` is evaluated by Sigma at render time and the report never goes stale) and a `number-range`
   filter keeping 1. The window is the `days` calendar days up to now: `last_days=1` is today and
   yesterday's boundary, so a source that lags a day shows yesterday. `column` is titled the way
   `filter_by_value`'s is. The element must be built on a warehouse table (an element built on another
   element inherits that element's filter instead), and the call fails rather than leave an element
   silently unscoped. The element is updated in place and returned. #}
{% macro filter_last_days(element, column, days) %}
{% if element is not mapping or element.get('source') is not mapping %}
  {% do sigma_report.fail('filter_last_days', "expected a chart, KPI or table element, got " ~ element) %}
{% endif %}
{% if column is not string or not column %}
  {% do sigma_report.fail('filter_last_days', "column must be a non-empty string, got " ~ column) %}
{% endif %}
{% if days is not number or days is sameas true or days is sameas false or days < 1 or days != days | int %}
  {% do sigma_report.fail('filter_last_days', "days must be a whole number of at least 1, got " ~ days) %}
{% endif %}
{% set source = element['source'] %}
{% if source.get('kind') != 'warehouse-table' %}
  {% do sigma_report.fail('filter_last_days', "element '" ~ element['id'] ~ "' is not built on a warehouse table, so there is no date column to filter. An element built on another element inherits that element's filter.") %}
{% endif %}
{% set column_id = sigma_report.freeze_id(element['id'] ~ ':last-days:' ~ column) %}
{% set filters = element.get('filters') or [] %}
{% for existing in filters if existing['columnId'] == column_id %}
  {% do sigma_report.fail('filter_last_days', "element '" ~ element['id'] ~ "' is already limited to the last days of '" ~ column ~ "'") %}
{% endfor %}
{% set ref = '[' ~ source['path'][-1] ~ '/' ~ sigma_report.titleize(column) ~ ']' %}
{% if 'columns' not in element %}{% do element.update({'columns': []}) %}{% endif %}
{% do element['columns'].append({
  "id": column_id,
  "formula": 'If(' ~ ref ~ ' >= DateAdd("day", -' ~ (days | int) ~ ', Today()), 1, 0)',
  "hidden": true,
}) %}
{% do filters.append({
  "id": sigma_report.freeze_id(element['id'] ~ ':last-days-filter:' ~ column),
  "columnId": column_id,
  "kind": "number-range",
  "min": 1,
  "max": 1,
}) %}
{% do element.update({"filters": filters}) %}
{% do return(element) %}
{% endmacro %}
