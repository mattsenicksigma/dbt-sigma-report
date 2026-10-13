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

   A table in a Sigma report does not paginate: it is a window onto the first rows of its sort order,
   as many as its height allows, with the total row count in a summary bar. So the useful question is
   "how many rows do I show": `rows` (default 10) sets the height from that. Alternatively pass `h=` in
   pixels to fix the height, or `h='fill'` to take whatever is left of the page below it (it must sit
   directly on a page, not in a row). Sort the table to choose which rows appear. #}
{% macro table(source, columns, name=none, key=none, rows=10, h=none, sort=[], description=none, style=none) %}
{% set source = sigma_report.resolve_source(source, 'table') %}
{% if not columns %}
  {% do sigma_report.fail('table', "columns is required - list the fields the table should show.") %}
{% endif %}
{% set el = sigma_report.new_element('table', 'table', key, name, h if h is not none else sigma_report.table_height(rows, name is not none)) %}
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
