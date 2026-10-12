{# A table element.

     sigma_report.table(
       source=sigma_report.from_ref('orders'),
       name='Orders',
       columns=['order_id', 'order_date', sigma_report.field('Sum([Amount])', name='Revenue')],
       sort=[('order_date', 'desc')],
     )

   `columns` are fields (see field.sql) shown in the order given. `sort` items are a field, or a
   (field, 'asc'|'desc') pair. Charts and KPIs can use the returned table as their `source`, which is
   how "one table, several views of it" reports are built.

   Reports are paginated and a table's row count is not known at compile time, so `h` is the height
   you reserve for it on the page. #}
{% macro table(source, columns, name=none, key=none, h=300, sort=[], description=none, style=none) %}
{% set source = sigma_report.resolve_source(source, 'table') %}
{% if not columns %}
  {% do sigma_report.fail('table', "columns is required - list the fields the table should show.") %}
{% endif %}
{% set el = sigma_report.new_element('table', 'table', key, name, h) %}
{% set cols = [] %}
{% set order = sigma_report.add_columns(cols, el['id'], columns, source, 'table') %}
{% do el.update({"source": source, "columns": cols, "order": order}) %}
{% set sorts = [] %}
{% for item in sort %}
  {% set sort_field = item if item is string or item is mapping else item[0] %}
  {% set sort_dir = 'asc' if (item is string or item is mapping) else item[1] %}
  {% do sorts.append({
    "columnId": sigma_report.add_column(cols, el['id'], sort_field, source, 'table'),
    "direction": sigma_report.direction(sort_dir, 'table'),
  }) %}
{% endfor %}
{% if sorts %}
  {% do el.update({"sort": sorts}) %}
{% endif %}
{% do sigma_report.apply_titles(el, name, description) %}
{% do el.update(sigma_report.compact({"style": sigma_report.card_style(style)})) %}
{% do el.update({"_source": source}) %}
{% do return(el) %}
{% endmacro %}


{# A pivot table.

     sigma_report.pivot_table(source=orders, rows='region', cols='segment',
                              values='Sum([Amount])', name='Revenue by region and segment')

   `rows` and `cols` are one field or a list of fields (each becomes a grouping level); `values` is
   one measure or a list of them. Either `rows` or `cols` may be omitted. #}
{% macro pivot_table(source, values, rows=none, cols=none, name=none, key=none, h=300, description=none, style=none) %}
{% set source = sigma_report.resolve_source(source, 'pivot_table') %}
{% if rows is none and cols is none %}
  {% do sigma_report.fail('pivot_table', "give at least one of `rows` or `cols`.") %}
{% endif %}
{% set el = sigma_report.new_element('pivot-table', 'pivot_table', key, name, h) %}
{% set columns = [] %}
{% set value_ids = sigma_report.add_columns(columns, el['id'], values, source, 'pivot_table', 'values') %}
{% do el.update({"source": source, "columns": columns, "values": value_ids, "_source": source}) %}
{% if rows is not none %}
  {% set row_levels = [] %}
  {% for column_id in sigma_report.add_columns(columns, el['id'], rows, source, 'pivot_table', 'rows') %}
    {% do row_levels.append({"columnId": column_id}) %}
  {% endfor %}
  {% do el.update({"rowsBy": row_levels}) %}
{% endif %}
{% if cols is not none %}
  {% set col_levels = [] %}
  {% for column_id in sigma_report.add_columns(columns, el['id'], cols, source, 'pivot_table', 'cols') %}
    {% do col_levels.append({"columnId": column_id}) %}
  {% endfor %}
  {% do el.update({"columnsBy": col_levels}) %}
{% endif %}
{% do sigma_report.apply_titles(el, name, description) %}
{% do el.update(sigma_report.compact({"style": sigma_report.card_style(style)})) %}
{% do return(el) %}
{% endmacro %}
