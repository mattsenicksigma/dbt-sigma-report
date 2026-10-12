{# A KPI tile.

     sigma_report.kpi(source=orders, value='Sum([Amount])', name='Revenue',
                      format=sigma_report.format_currency())

   Context for the number (a KPI with nothing to compare against tells the reader little) comes from
   one of two places:

     compare_to='Sum([Target])'          compare against another measure ("vs plan")
     timeline='order_date', period='month'
                                         the value becomes the latest period's, compared with the one
                                         before; `timeline` is truncated to `period` for you

   `format` is a sigma_report.format_*() result applied to the value. `trend=true` (with a timeline)
   shows a sparkline under the number. `direction` says which way is good: 'higher', 'lower' or 'none'. #}
{% macro kpi(source, value, name=none, key=none, h=96, format=none, compare_to=none, compare_label=none, timeline=none, period='month', trend=false, direction='higher', description=none, style=none) %}
{% set source = sigma_report.resolve_source(source, 'kpi') %}
{% set value_field = sigma_report.normalize_field(value, source, 'kpi') %}
{% set title = name or value_field.get('name') %}
{% set el = sigma_report.new_element('kpi-chart', 'kpi', key, title or value_field['formula'], h) %}
{% set cols = [] %}
{% if format is not none %}
  {% do value_field.update({"format": format}) %}
{% endif %}
{% set value_id = sigma_report.add_column(cols, el['id'], value_field, source, 'kpi', 'value') %}
{% do el.update({"source": source, "columns": cols, "_source": source}) %}
{% do el.update({"value": {
  "columnId": value_id,
  "color": sigma_report.color_ref('ink'),
  "fontWeight": "bold",
}}) %}
{% if title %}
  {% do el.update({"name": {
    "text": title,
    "color": sigma_report.color_ref('muted'),
    "fontWeight": "normal",
    "fontSize": 14,
  }}) %}
{% endif %}
{% set comparison = {
  "direction": direction,
  "colorGood": sigma_report.color_ref('success'),
  "colorBad": sigma_report.color_ref('danger'),
  "labelColor": sigma_report.color_ref('muted'),
} %}
{% if compare_to is not none %}
  {% do el.update({"comparisonColumn": {"columnId": sigma_report.add_column(cols, el['id'], compare_to, source, 'kpi', 'comparison')}}) %}
  {% do comparison.update({"display": "percentage", "label": compare_label or "plan"}) %}
  {% do el.update({"comparison": comparison}) %}
{% elif timeline is not none %}
  {% set bucket = sigma_report.field(
    'DateTrunc("' ~ period ~ '", ' ~ sigma_report.formula_for(timeline, source) ~ ')',
    name='Trend ' ~ period
  ) %}
  {% do el.update({
    "timeline": {"columnId": sigma_report.add_column(cols, el['id'], bucket, source, 'kpi', 'timeline')},
    "periodComparison": period,
  }) %}
  {% do comparison.update({"display": "percentage"}) %}
  {% do el.update({"comparison": comparison}) %}
  {% if trend %}
    {% do el.update({"trend": {"shape": "area", "areaStyle": "gradient", "valueColor": sigma_report.color_ref('primary')}}) %}
  {% else %}
    {% do el.update({"trend": {"visibility": "hidden"}}) %}
  {% endif %}
{% endif %}
{% if description is not none %}
  {% do el.update({"description": {"text": description, "color": sigma_report.color_ref('muted'), "position": "below"}}) %}
{% endif %}
{% do el.update({"layout": {"anchor": "left", "verticalAnchor": "top"}}) %}
{% do el.update(sigma_report.compact({"style": sigma_report.card_style(style)})) %}
{% do return(el) %}
{% endmacro %}
