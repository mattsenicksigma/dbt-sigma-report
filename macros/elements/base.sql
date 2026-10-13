{# Shared scaffolding for every element macro.

   An element is a plain dict in Sigma's own element shape (`id`, `kind`, `columns`, ...) plus a few
   private `_`-prefixed keys the layout engine reads and `sigma_report.report()` strips:

     _h        natural height in pixels (every element macro takes `h=`; the default comes from the
               project's `sigma_report_settings`)
     _auto     text to size the height from, once the width it is laid out at is known
     _flex     a flexible element: its weight when free space is shared out (see `flex()`)
     _min      the smallest a flexible element may be
     _key      the identity the id was derived from (for duplicate-id error messages)
     _source   the source the element reads from, so other elements can be built on top of it

   Width is deliberately *not* a property of an element: reports are laid out by `row()`, which
   divides the available width between its cells. The same chart therefore works as a full-width figure
   or as one cell of a pair without being rebuilt.

   `h` is a number of pixels, or `'fill'` (shorthand for `flex(el)`: take the space left over). Element
   ids come from the element's kind plus its `key` (or, failing that, `name`). Two elements of the same
   kind sharing a name therefore need distinct `key=`s - `report()` raises if they don't, rather than
   letting Sigma silently merge them. #}
{% macro new_element(kind, where, key, name, h) %}
{% set identity = key or name %}
{% if not identity %}
  {% do sigma_report.fail(where, "set `name=` or `key=` so the element gets a stable id.") %}
{% endif %}
{% set el = {
  "id": sigma_report.freeze_id('element:' ~ kind ~ ':' ~ identity),
  "kind": kind,
  "_key": kind ~ ':' ~ identity,
} %}
{% if h is string and h == 'fill' %}
  {% do el.update({"_h": 120, "_flex": 1, "_min": 120}) %}
  {% do return(el) %}
{% endif %}
{% if h is not number or h <= 0 %}
  {% do sigma_report.fail(where, "h must be a positive number of pixels, or 'fill', got " ~ h) %}
{% endif %}
{% do el.update({"_h": h}) %}
{% do return(el) %}
{% endmacro %}


{# The height of a table showing `rows` data rows, measured from Sigma's own PDF export of a pushed
   report (a 252px table showed 6 rows): about 130px for the title, header row and summary bar, plus
   20px per row. It is a measurement, not a contract - Sigma can change its table chrome, so the
   numbers are project settings (`table_row_h`, `table_chrome`, `table_chrome_untitled`).

   A Sigma table does not paginate and has no row limit setting: it is a window of as many rows as its
   height allows, with the total row count in its summary bar. So "how tall" means "how many rows";
   `table_pages` shows more rows by stacking several windows. #}
{% macro table_height(rows, titled=true) %}
{% if rows is not number or rows < 1 %}
  {% do sigma_report.fail('table', "rows must be a positive number of visible rows, got " ~ rows) %}
{% endif %}
{% set chrome = sigma_report.setting('table_chrome') if titled else sigma_report.setting('table_chrome_untitled') %}
{% do return((chrome + sigma_report.setting('table_row_h') * rows) | int) %}
{% endmacro %}


{# The default look of a data element (chart, table, KPI, pivot): a white card with a hairline border.
   Switch it off project-wide with `sigma_report_theme: {cards: false}`, or per element by passing
   `style=`. #}
{% macro card_style(style=none) %}
{% if style is not none %}
  {% do return(style) %}
{% endif %}
{% if not sigma_report.theme_config()['cards'] %}
  {% do return(none) %}
{% endif %}
{% do return({
  "backgroundColor": sigma_report.color_ref('surface'),
  "borderRadius": "round",
  "borderWidth": 1,
  "borderColor": sigma_report.color_ref('hairline'),
}) %}
{% endmacro %}


{# 'asc' / 'desc' (or the full words) -> Sigma's 'ascending' / 'descending'. #}
{% macro direction(value, where) %}
{% if value in ['asc', 'ascending'] %}
  {% do return('ascending') %}
{% elif value in ['desc', 'descending'] %}
  {% do return('descending') %}
{% endif %}
{% do sigma_report.fail(where, "sort direction must be 'asc' or 'desc', got '" ~ value ~ "'.") %}
{% endmacro %}


{# Title / description in the shapes Sigma accepts (a plain string for charts, tables and pivots). #}
{% macro apply_titles(el, name, description) %}
{% if name is not none %}
  {% do el.update({"name": name}) %}
{% endif %}
{% if description is not none %}
  {% do el.update({"description": description}) %}
{% endif %}
{% endmacro %}
