{# The rest of Sigma's chart family: combo, waterfall, box, funnel, gauge, treemap, sankey and the three
   maps, plus progress bars. They are built the same way as the basic charts - fields in, columns and
   channels out - so a formula or a bare column name works anywhere a field is expected, and the
   result takes part in layout, themes and `extend()` like any other element.

   Cartesian kinds (combo, waterfall, box) share `xy_chart` with bar and line. The others describe
   their channels - which Sigma property each field feeds, and in which shape - and share
   `channel_element`, so adding another kind is a few lines, not a new assembler. #}


{# Assembles an element whose data channels are described by `channels`, a list of mappings:

     {"prop": "stage", "fields": 'stage', "shape": "id"}      -> stage: {columnId}
     {"prop": "value", "fields": [..],   "shape": "list"}     -> value: [{columnId}, ...]
     {"prop": "yAxis", "fields": [..],   "shape": "ids"}      -> yAxis: {columnIds: [...]}

   A channel whose `fields` is none is skipped. `role` (default: the prop) is part of the column id, since
   Sigma allows a column on one channel only. `extra` is merged onto the element as is. #}
{% macro channel_element(kind, where, source, name, key, h, description, channels, style, extra) %}
{% set source = sigma_report.resolve_source(source, where) %}
{% set el = sigma_report.new_element(kind, where, key, name, h) %}
{% set cols = [] %}
{% do el.update({"source": source, "_source": source}) %}
{% for ch in channels if ch['fields'] is not none %}
  {% set ids = sigma_report.add_columns(cols, el['id'], ch['fields'], source, where, ch.get('role', ch['prop'])) %}
  {% if ch['shape'] == 'id' %}
    {% do el.update({ch['prop']: {"columnId": ids[0]}}) %}
  {% elif ch['shape'] == 'ids' %}
    {% do el.update({ch['prop']: {"columnIds": ids}}) %}
  {% else %}
    {% set refs = [] %}
    {% for column_id in ids %}{% do refs.append({"columnId": column_id}) %}{% endfor %}
    {% do el.update({ch['prop']: refs}) %}
  {% endif %}
{% endfor %}
{% do el.update({"columns": cols}) %}
{% for k in extra.keys() %}{% do el.update({k: extra[k]}) %}{% endfor %}
{% do sigma_report.apply_titles(el, name, description) %}
{% do el.update(sigma_report.compact({"style": sigma_report.card_style(style)})) %}
{% do return(el) %}
{% endmacro %}


{# Sigma's color shelf for a measure or category: `by: scale` (a gradient over a measure) or
   `by: category`. Returns the property value, with the column added to `el`. #}
{% macro color_channel(el, field, how, where) %}
{% if how not in ['scale', 'category'] %}
  {% do sigma_report.fail(where, "color_by must be 'scale' or 'category', got '" ~ how ~ "'.") %}
{% endif %}
{% set column_id = sigma_report.add_column(el['columns'], el['id'], field, el['_source'], where, 'color') %}
{% do return({"by": how, "column": column_id}) %}
{% endmacro %}


{# A combo chart: bars, lines, areas or points on one axis. `y` is a list of measures and `series_types`
   says how each is drawn - 'bar', 'line', 'area' or 'scatter' (default: all bars):

     sigma_report.combo_chart(orders, x='DateTrunc("month", [Order Date])',
                              y=['Sum([Amount])', 'Count()'], series_types=['bar', 'line'], name='...')

   Measures on very different scales (revenue and order count) need a second axis: `secondary=[1]` plots
   the second measure (0-based position in `y`) against it. #}
{% macro combo_chart(source, x, y, series_types=none, secondary=none, color=none, name=none, key=none, h=none, description=none, labels=false, legend=true, style=none) %}
{% set el = sigma_report.xy_chart('combo-chart', 'combo_chart', source, x, y, color, name, key, h, description, none, 'asc', none, labels, legend, none, style) %}
{% if secondary is not none %}
  {% set plain_ids = el['yAxis']['columnIds'] %}
  {% set on_second = [] %}
  {% for i in secondary %}
    {% if i is not number or i < 0 or i >= plain_ids | length %}
      {% do sigma_report.fail('combo_chart', "secondary lists 0-based positions in y (0 to " ~ ((plain_ids | length) - 1) ~ "), got " ~ i) %}
    {% endif %}
    {% do on_second.append(plain_ids[i]) %}
  {% endfor %}
  {% do el.update({"yAxis2": {"columnIds": on_second}}) %}
{% endif %}
{% if series_types is not none %}
  {% set ids = el['yAxis']['columnIds'] %}
  {% if series_types | length != ids | length %}
    {% do sigma_report.fail('combo_chart', "series_types has " ~ (series_types | length) ~ " entries but y has " ~ (ids | length) ~ " measures.") %}
  {% endif %}
  {% set typed = [] %}
  {% for column_id in ids %}
    {% if series_types[loop.index0] not in ['bar', 'line', 'area', 'scatter'] %}
      {% do sigma_report.fail('combo_chart', "series type must be bar, line, area or scatter, got '" ~ series_types[loop.index0] ~ "'.") %}
    {% endif %}
    {% do typed.append({"columnId": column_id, "type": series_types[loop.index0]}) %}
  {% endfor %}
  {% do el['yAxis'].update({"columnIds": typed}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A waterfall chart: `x` is the step, `y` the measure that rises and falls. #}
{% macro waterfall_chart(source, x, y, name=none, key=none, h=none, description=none, legend=true, style=none) %}
{% do return(sigma_report.xy_chart('waterfall-chart', 'waterfall_chart', source, x, y, none, name, key, h, description, none, 'asc', none, false, legend, none, style)) %}
{% endmacro %}


{# A box plot of `y` (a measure per row, so Sigma can compute quartiles), optionally grouped by `x`. #}
{% macro box_chart(source, y, x=none, name=none, key=none, h=none, description=none, legend=true, style=none) %}
{% do return(sigma_report.xy_chart('box-chart', 'box_chart', source, x, y, none, name, key, h, description, none, 'asc', none, false, legend, none, style)) %}
{% endmacro %}


{# A funnel: `stage` is the step (a dimension), `value` the measure at each step. #}
{% macro funnel_chart(source, stage, value, name=none, key=none, h=none, description=none, style=none) %}
{% do return(sigma_report.channel_element('funnel-chart', 'funnel_chart', source, name, key, sigma_report.setting('chart_h', h), description, [
  {"prop": "stage", "fields": stage, "shape": "id"},
  {"prop": "series", "fields": value, "shape": "id", "role": "value"},
], style, {})) %}
{% endmacro %}


{# A gauge of `value`, optionally against `minimum`, `maximum` and a `target` (each a field or formula,
   so `'0'` or `'Sum([Quota])'` both work). Compact by default (`gauge_h`). #}
{% macro gauge_chart(source, value, minimum=none, maximum=none, target=none, name=none, key=none, h=none, description=none, style=none) %}
{% do return(sigma_report.channel_element('gauge-chart', 'gauge_chart', source, name, key, sigma_report.setting('gauge_h', h), description, [
  {"prop": "value", "fields": value, "shape": "id"},
  {"prop": "minimum", "fields": minimum, "shape": "id"},
  {"prop": "maximum", "fields": maximum, "shape": "id"},
  {"prop": "target", "fields": target, "shape": "id"},
], style, {})) %}
{% endmacro %}


{# A treemap: tiles sized by `value` (one measure or a list), grouped by `category`, optionally nested by
   `split_by` and colored by a field (`color_by`: 'scale' for a measure, 'category' for a dimension). #}
{% macro treemap_chart(source, category, value, split_by=none, color=none, color_by='scale', name=none, key=none, h=none, description=none, style=none) %}
{% set el = sigma_report.channel_element('treemap-chart', 'treemap_chart', source, name, key, sigma_report.setting('chart_h', h), description, [
  {"prop": "category", "fields": category, "shape": "id"},
  {"prop": "value", "fields": value, "shape": "list"},
  {"prop": "splitBy", "fields": split_by, "shape": "id", "role": "split"},
], style, {}) %}
{% if color is not none %}
  {% do el.update({"color": sigma_report.color_channel(el, color, color_by, 'treemap_chart')}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A sankey diagram: `stages` is the ordered list of dimensions the flow passes through, `value` the
   measure that sizes each flow. #}
{% macro sankey_chart(source, stages, value, name=none, key=none, h=none, description=none, style=none) %}
{% if stages is string or stages | length < 2 %}
  {% do sigma_report.fail('sankey_chart', "stages is a list of at least two dimensions, got " ~ stages) %}
{% endif %}
{% do return(sigma_report.channel_element('sankey-chart', 'sankey_chart', source, name, key, sigma_report.setting('chart_h', h), description, [
  {"prop": "stages", "fields": stages, "shape": "list", "role": "stage"},
  {"prop": "value", "fields": value, "shape": "id"},
], style, {})) %}
{% endmacro %}


{# A map of points: `latitude` and `longitude` fields, optionally sized by a measure and colored by a field
   (`color_by` as for treemap). #}
{% macro point_map(source, latitude, longitude, size=none, color=none, color_by='category', name=none, key=none, h=none, description=none, style=none) %}
{% set el = sigma_report.channel_element('point-map', 'point_map', source, name, key, sigma_report.setting('map_h', h), description, [
  {"prop": "latitude", "fields": latitude, "shape": "id"},
  {"prop": "longitude", "fields": longitude, "shape": "id"},
  {"prop": "size", "fields": size, "shape": "id"},
], style, {}) %}
{% if color is not none %}
  {% do el.update({"color": sigma_report.color_channel(el, color, color_by, 'point_map')}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A filled map of regions: `region` is a field of region names or codes, `region_type` says what they
   are (country, us-state, us-county, us-zipcode, us-cbsa), and `color` shades each region by a measure
   (`color_by='scale'`) or category. #}
{% macro region_map(source, region, region_type, color=none, color_by='scale', name=none, key=none, h=none, description=none, style=none) %}
{% if region_type not in ['country', 'us-state', 'us-county', 'us-zipcode', 'us-cbsa'] %}
  {% do sigma_report.fail('region_map', "region_type must be country, us-state, us-county, us-zipcode or us-cbsa, got '" ~ region_type ~ "'.") %}
{% endif %}
{% set el = sigma_report.channel_element('region-map', 'region_map', source, name, key, sigma_report.setting('map_h', h), description, [
  {"prop": "region", "fields": region, "shape": "id"},
], style, {}) %}
{% do el['region'].update({"regionType": region_type}) %}
{% if color is not none %}
  {% do el.update({"color": sigma_report.color_channel(el, color, color_by, 'region_map')}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A map of geographic shapes: `geography` is a geography-typed field. #}
{% macro geography_map(source, geography, color=none, color_by='scale', name=none, key=none, h=none, description=none, style=none) %}
{% set el = sigma_report.channel_element('geography-map', 'geography_map', source, name, key, sigma_report.setting('map_h', h), description, [
  {"prop": "geography", "fields": geography, "shape": "id"},
], style, {}) %}
{% if color is not none %}
  {% do el.update({"color": sigma_report.color_channel(el, color, color_by, 'geography_map')}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A progress bar or ring - a single value against a range, no source needed. `value`, `min` and `max`
   are Sigma formulas (strings, so `'42'` or `'Sum([Sales])'`); `mode` is 'percent' (the value relative to
   min and max, the default) or 'value'. #}
{% macro progress(value, key, min=none, max=none, mode='percent', shape='bar', h=none) %}
{% if mode not in ['percent', 'value'] %}
  {% do sigma_report.fail('progress', "mode must be 'percent' or 'value', got '" ~ mode ~ "'.") %}
{% endif %}
{% if shape not in ['bar', 'ring'] %}
  {% do sigma_report.fail('progress', "shape must be 'bar' or 'ring', got '" ~ shape ~ "'.") %}
{% endif %}
{% set el = sigma_report.new_element('progress', 'progress', key, none, sigma_report.setting('gauge_h', h)) %}
{% do el.update(sigma_report.compact({"value": value | string, "min": min | string if min is not none else none, "max": max | string if max is not none else none, "mode": mode, "shape": shape})) %}
{% do return(el) %}
{% endmacro %}


{# A button, from Sigma's own properties: `text` plus anything in `options` (fillColor, size, actions, ...),
   checked against the button schema. #}
{% macro button(text, key, options={}, h=none) %}
{% do sigma_report.check_properties('button', options, 'button') %}
{% set el = sigma_report.new_element('button', 'button', key, none, h if h is not none else 40) %}
{% do el.update({"text": text}) %}
{% for k in options.keys() %}{% do el.update({k: options[k]}) %}{% endfor %}
{% do return(el) %}
{% endmacro %}


{# An embedded page by URL. #}
{% macro embed(url, key, h=none) %}
{% set el = sigma_report.new_element('embed', 'embed', key, none, sigma_report.setting('chart_h', h)) %}
{% do el.update({"url": url}) %}
{% do return(el) %}
{% endmacro %}
