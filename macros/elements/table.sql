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
   directly on a page, not in a row). Sort the table to choose which rows appear.

   `paginate=true` is Sigma's "Expand table rows": the table grows to hold every row when the report
   renders and continues onto further pages (up to 10,000 rows, vertically only), so no row count is
   needed. The cost is that nothing is known at compile time about how far it will grow, so a paginated
   table must be the last block on its page (put what you want after it in the footer) and cannot sit in
   a `row`, `stack` or panel; `h` (or `rows`) is the height it starts with. Use `window` / `table_pages`
   instead when you want fixed page boundaries, content after the table, or a deterministic page count.

   `window=[first, last]` shows only rows `first` to `last` of the sort order (1-based, inclusive): the
   table gets a hidden `RowNumber()` column and a number-range filter on it, and `rows` defaults to the
   window's size. Stacking several windows is how a table runs over several pages - see `table_pages`.
   Windows need a deterministic `sort`, or the row numbers are arbitrary. #}
{% macro table(source, columns, name=none, key=none, rows=none, h=none, sort=[], window=none, description=none, style=none, paginate=false) %}
{% set source = sigma_report.resolve_source(source, 'table') %}
{% if not columns %}
  {% do sigma_report.fail('table', "columns is required - list the fields the table should show.") %}
{% endif %}
{% if window is not none and paginate %}
  {% do sigma_report.fail('table', "paginate=true expands the table to all its rows, so it cannot also be a window.") %}
{% endif %}
{% if window is not none %}
  {% if window | length != 2 or window[0] is not number or window[1] is not number or window[0] < 1 or window[1] < window[0] %}
    {% do sigma_report.fail('table', "window is [first, last] row numbers with 1 <= first <= last, got " ~ window) %}
  {% endif %}
  {% if not sort %}
    {% do sigma_report.fail('table', "a window needs a `sort`, otherwise its row numbers are arbitrary.") %}
  {% endif %}
  {% if rows is none %}
    {% set rows = window[1] - window[0] + 1 %}
  {% endif %}
{% endif %}
{% set el = sigma_report.new_element('table', 'table', key, name, h if h is not none else sigma_report.table_height(sigma_report.setting('table_rows', rows), name is not none)) %}
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
{% if window is not none %}
  {# a hidden row-number column (numbered in the table's sort order) with a range filter on it #}
  {% set rn_id = sigma_report.add_column(cols, el['id'], sigma_report.field('RowNumber()', name='Row'), source, 'table', 'window') %}
  {% for c in cols if c['id'] == rn_id %}{% do c.update({"hidden": true}) %}{% endfor %}
  {% do el.update({"filters": [{"id": sigma_report.freeze_id(el['id'] ~ ':window'), "columnId": rn_id, "kind": "number-range", "min": window[0], "max": window[1]}]}) %}
{% endif %}
{% do sigma_report.apply_titles(el, name, description) %}
{% do el.update(sigma_report.compact({"style": sigma_report.card_style(style)})) %}
{% do el.update({"_source": source}) %}
{% do sigma_report.apply_flow(el, paginate) %}
{% do return(el) %}
{% endmacro %}


{# A table that runs over several pages: a sequence of `table(window=...)` windows, one per page, with a
   page break between them (so it needs `paginate=true` on its page). Sigma does not paginate tables
   itself, so this is how "all the rows" is done - each page shows the next `rows_per_page` rows of the
   `sort` order, and each window's summary bar still shows the table's total.

     sigma_report.page('Orders', [
       sigma_report.table_pages(orders, ['order_id', 'region', 'amount'], rows_per_page=40, total_rows=200,
                                name='Orders', sort=[('order_id', 'asc')])
     ], paginate=true)

   The compiler cannot see the data, so say how many rows to cover: `pages=5` or `total_rows=200` (the
   pages needed to hold that many). Rows beyond that are not shown - leave headroom, since a short last
   page is only blank space. Choose `rows_per_page` to fill a page: about
   `(content height - table_chrome) / table_row_h`, e.g. 40 on Letter with the default margin. Returns a
   list of blocks; pass it straight to `page()`. #}
{% macro table_pages(source, columns, rows_per_page, pages=none, total_rows=none, name=none, key=none, sort=[], description=none, style=none) %}
{% if rows_per_page is not number or rows_per_page < 1 %}
  {% do sigma_report.fail('table_pages', "rows_per_page must be a positive number, got " ~ rows_per_page) %}
{% endif %}
{% if (pages is none) == (total_rows is none) %}
  {% do sigma_report.fail('table_pages', "give exactly one of `pages` (how many windows) or `total_rows` (how many rows to cover).") %}
{% endif %}
{% set count = pages if pages is not none else ((total_rows + rows_per_page - 1) / rows_per_page) | int %}
{% if count is not number or count < 1 %}
  {% do sigma_report.fail('table_pages', "pages must be at least 1, got " ~ count) %}
{% endif %}
{% set identity = key or name %}
{% if not identity %}
  {% do sigma_report.fail('table_pages', "set `name=` or `key=` so each window gets a stable id.") %}
{% endif %}
{% set blocks = [] %}
{% for i in range(1, count + 1) %}
  {% if i > 1 %}{% do blocks.append(sigma_report.page_break()) %}{% endif %}
  {% set title = none if name is none else (name if count == 1 else name ~ ' (page ' ~ i ~ ' of ' ~ count ~ ')') %}
  {% do blocks.append(sigma_report.table(
    source, columns, name=title, key=identity ~ ':window:' ~ i, sort=sort, description=description, style=style,
    window=[(i - 1) * rows_per_page + 1, i * rows_per_page]
  )) %}
{% endfor %}
{% do return(blocks) %}
{% endmacro %}


{# A pivot table.

     sigma_report.pivot_table(source=orders, rows='region', cols='segment',
                              values='Sum([Amount])', name='Revenue by region and segment')

   `rows` and `cols` are one field or a list of fields (each becomes a grouping level); `values` is
   one measure or a list of them. Either `rows` or `cols` may be omitted. #}
{% macro pivot_table(source, values, rows=none, cols=none, name=none, key=none, h=none, description=none, style=none, paginate=false) %}
{% set source = sigma_report.resolve_source(source, 'pivot_table') %}
{% if rows is none and cols is none %}
  {% do sigma_report.fail('pivot_table', "give at least one of `rows` or `cols`.") %}
{% endif %}
{% set el = sigma_report.new_element('pivot-table', 'pivot_table', key, name, sigma_report.setting('pivot_h', h)) %}
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
{% do sigma_report.apply_flow(el, paginate) %}
{% do return(el) %}
{% endmacro %}
