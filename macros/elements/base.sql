{# Shared scaffolding for every element macro.

   An element is a plain dict in Sigma's own element shape (`id`, `kind`, `columns`, ...) plus a few
   private `_`-prefixed keys the layout engine reads and `sigma_report.report()` strips:

     _h        height in pixels (every element macro takes `h=` and has a sensible default)
     _key      the identity the id was derived from (for duplicate-id error messages)
     _source   the source the element reads from, so other elements can be built on top of it

   Width is deliberately *not* a property of an element: reports are laid out by `row()`, which
   divides the page's content width between the elements in it. The same chart therefore works as a
   full-width figure or as one half of a pair without being rebuilt.

   Element ids come from the element's kind plus its `key` (or, failing that, `name`). Two elements of
   the same kind sharing a name therefore need distinct `key=`s - `report()` raises if they don't,
   rather than letting Sigma silently merge them. #}
{% macro new_element(kind, where, key, name, h) %}
{% set identity = key or name %}
{% if not identity %}
  {% do sigma_report.fail(where, "set `name=` or `key=` so the element gets a stable id.") %}
{% endif %}
{% if h is not number or h <= 0 %}
  {% do sigma_report.fail(where, "h must be a positive number of pixels, got " ~ h) %}
{% endif %}
{% do return({
  "id": sigma_report.freeze_id('element:' ~ kind ~ ':' ~ identity),
  "kind": kind,
  "_key": kind ~ ':' ~ identity,
  "_h": h,
}) %}
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


{# Marks a table or pivot table as paginated: Sigma's "Expand table rows", where the element grows to
   hold all its rows at render time and continues onto further pages. It is a property of the element's
   place in the layout (`flow="paginated"`), not of the element, so it is kept as a private key the
   layout reads. `h` stays as the height reserved when the page is laid out. #}
{% macro apply_flow(el, paginate) %}
{% if paginate %}
  {% do el.update({"_flow": "paginated"}) %}
{% endif %}
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
