{# Layout: turns a page's blocks into pixel positions, and the positions into the XML string Sigma
   expects in a report's `contents.layout`.

   Reports are *paginated documents*, not responsive canvases: every element has an absolute x / y /
   width / height in pixels, measured from the top-left of the page's content area (inside the
   margin). A workbook's 24-column grid does not exist here.

   Placement is a vertical flow. A page is a list of blocks; a block is either

     * an element, which takes the full content width, or
     * a `row(...)`, which divides the content width between several elements (equally, or by weight)
       and is as tall as its tallest element.

   Blocks are stacked top to bottom with a fixed `gap` between them. When the next block would not fit
   on the page, the page either fails (the default, so an overflow is never silent) or, with
   `paginate=true`, continues on a new physical page that repeats the headers and footers. #}


{# A horizontal band of elements sharing the page width.

     sigma_report.row([revenue_kpi, orders_kpi, margin_kpi])
     sigma_report.row([by_region, by_month], widths=[2, 1])

   `widths` are relative weights (default: equal). Every element in the row is stretched to the
   height of the tallest, so a row is always a clean rectangle. `gap` is the space between the
   elements in pixels; it defaults to the report's gap. `pad` reserves that much trailing weight as
   empty space, which is how `grid()` keeps a short last row the same cell width as the rows above it.
   A row may hold elements, `stack(...)`s and lists of them (the composites return lists), but not
   other rows. #}
{% macro row(elements, widths=none, gap=none, pad=0) %}
{% set items = sigma_report.flatten(elements) %}
{% if not items %}
  {% do sigma_report.fail('row', "a row needs at least one element.") %}
{% endif %}
{% set weights = [] %}
{% if widths is none %}
  {% for item in items %}{% do weights.append(1) %}{% endfor %}
{% else %}
  {% for w in widths %}{% do weights.append(w) %}{% endfor %}
{% endif %}
{% if weights | length != items | length %}
  {% do sigma_report.fail('row', "widths has " ~ (weights | length) ~ " entries but the row has " ~ (items | length) ~ " elements.") %}
{% endif %}
{% set tallest = namespace(h=0) %}
{% for item in items %}
  {% if item is not mapping or ('id' not in item and '_stack' not in item) %}
    {% do sigma_report.fail('row', "a row holds elements built by sigma_report macros (or stack(...)s), got " ~ item) %}
  {% endif %}
  {% if item.get('_fill') %}
    {% do sigma_report.fail('row', "h='fill' only works on an element placed directly on a page, not inside a row.") %}
  {% endif %}
  {% if weights[loop.index0] is not number or weights[loop.index0] <= 0 %}
    {% do sigma_report.fail('row', "widths must be positive numbers, got " ~ weights[loop.index0]) %}
  {% endif %}
  {% if item['_h'] > tallest.h %}{% set tallest.h = item['_h'] %}{% endif %}
{% endfor %}
{% do return({"_row": items, "_widths": weights, "_gap": gap, "_pad": pad, "_h": tallest.h}) %}
{% endmacro %}


{# A vertical group of elements that occupies a single cell of a row - two KPIs beside a chart, say:

     sigma_report.row([sigma_report.stack([revenue, orders]), trend_chart], widths=[1, 2])

   The elements keep their own heights; `gap` (pixels, default 16) separates them, so the stack is as
   tall as the sum of its elements plus the gaps. A stack holds elements only - not rows or stacks. #}
{% macro stack(elements, gap=16) %}
{% set items = sigma_report.flatten(elements) %}
{% if not items %}
  {% do sigma_report.fail('stack', "a stack needs at least one element.") %}
{% endif %}
{% set total = namespace(h=gap * (items | length - 1)) %}
{% for item in items %}
  {% if item is not mapping or 'id' not in item %}
    {% do sigma_report.fail('stack', "a stack holds elements built by sigma_report macros, got " ~ item) %}
  {% endif %}
  {% if item.get('_fill') %}
    {% do sigma_report.fail('stack', "h='fill' only works on an element placed directly on a page, not inside a stack.") %}
  {% endif %}
  {% set total.h = total.h + item['_h'] %}
{% endfor %}
{% do return({"_stack": items, "_gap": gap, "_h": total.h}) %}
{% endmacro %}


{# The page size in pixels (96 per inch) for a preset name or a {width, height} mapping. `orientation`
   ('portrait' / 'landscape') is applied when given; none keeps the preset's natural shape. `letter`
   and `a4` are the sizes Sigma's own examples default to. #}
{% macro page_dimensions(page_size, orientation) %}
{% set presets = {
  "letter":  {"width": 816,  "height": 1056},
  "legal":   {"width": 816,  "height": 1344},
  "tabloid": {"width": 1056, "height": 1632},
  "a4":      {"width": 794,  "height": 1123},
  "a3":      {"width": 1123, "height": 1587},
  "screen":  {"width": 1280, "height": 720},
} %}
{% if page_size is mapping %}
  {% set size = page_size %}
  {% if size.get('width') is not number or size.get('height') is not number %}
    {% do sigma_report.fail('report', "a custom page_size needs numeric `width` and `height` in pixels, got " ~ page_size) %}
  {% endif %}
{% elif page_size in presets %}
  {% set size = presets[page_size] %}
{% else %}
  {% do sigma_report.fail('report', "unknown page_size '" ~ page_size ~ "' - use one of " ~ (presets.keys() | list | sort) ~ " or {width: px, height: px}.") %}
{% endif %}
{% if orientation is none %}
  {% do return({"width": size['width'], "height": size['height']}) %}
{% endif %}
{% if orientation not in ['portrait', 'landscape'] %}
  {% do sigma_report.fail('report', "orientation must be 'portrait' or 'landscape', got '" ~ orientation ~ "'.") %}
{% endif %}
{% set long_side = [size['width'], size['height']] | max %}
{% set short_side = [size['width'], size['height']] | min %}
{% if orientation == 'landscape' %}
  {% do return({"width": long_side, "height": short_side}) %}
{% endif %}
{% do return({"width": short_side, "height": long_side}) %}
{% endmacro %}


{# The pixel width of each cell of a row, in order. Widths are whole pixels; the last cell absorbs the
   rounding so a row without `pad` spans the content width exactly. #}
{% macro row_cell_widths(block, content_w, gap) %}
{% set row_gap = block['_gap'] if block['_gap'] is not none else gap %}
{% set pad = block['_pad'] %}
{% set n = (block['_row'] | length) + (1 if pad > 0 else 0) %}
{% set usable = content_w - row_gap * (n - 1) %}
{% set total = namespace(weight=pad) %}
{% for w in block['_widths'] %}{% set total.weight = total.weight + w %}{% endfor %}
{% set cursor = namespace(x=0) %}
{% set widths = [] %}
{% for el in block['_row'] %}
  {% if loop.last and pad <= 0 %}
    {% set width = content_w - cursor.x %}
  {% else %}
    {% set width = (usable * block['_widths'][loop.index0] / total.weight) | int %}
  {% endif %}
  {% do widths.append(width) %}
  {% set cursor.x = cursor.x + width + row_gap %}
{% endfor %}
{% do return(widths) %}
{% endmacro %}


{# Settles the heights that depend on width: text sized from its content (`_auto`). Elements are updated
   in place; a row becomes as tall as its tallest cell and a stack as tall as its elements plus gaps. This
   is why heights are resolved here, in the flow, rather than when the element is built - at build time
   nobody knows how wide the cell will be. #}
{% macro resolve_block(block, content_w, gap) %}
{% if '_row' in block %}
  {% set widths = sigma_report.row_cell_widths(block, content_w, gap) %}
  {% set tallest = namespace(h=0) %}
  {% for el in block['_row'] %}
    {% set cell_w = widths[loop.index0] %}
    {% if '_stack' in el %}
      {% set total = namespace(h=el['_gap'] * ((el['_stack'] | length) - 1)) %}
      {% for inner in el['_stack'] %}
        {% if inner.get('_auto') %}
          {% do inner.update({"_h": sigma_report.text_height(inner['_auto'], cell_w)}) %}
        {% endif %}
        {% set total.h = total.h + inner['_h'] %}
      {% endfor %}
      {% do el.update({"_h": total.h}) %}
    {% elif el.get('_auto') %}
      {% do el.update({"_h": sigma_report.text_height(el['_auto'], cell_w)}) %}
    {% endif %}
    {% if el['_h'] > tallest.h %}{% set tallest.h = el['_h'] %}{% endif %}
  {% endfor %}
  {% do block.update({"_h": tallest.h}) %}
{% elif block.get('_auto') %}
  {% do block.update({"_h": sigma_report.text_height(block['_auto'], content_w)}) %}
{% endif %}
{% endmacro %}


{# Places one block (an element or a row) at vertical offset `y`. A page's blocks are elements and
   rows; a row's cells are elements and stacks. Returns a list of placements:
   {element, x, y, width, height}. Widths are whole pixels; the last element in a row absorbs the
   rounding so a row always spans the content width exactly. #}
{% macro place_block(block, y, content_w, gap) %}
{% set placed = [] %}
{% if '_row' in block %}
  {% set row_gap = block['_gap'] if block['_gap'] is not none else gap %}
  {% set widths = sigma_report.row_cell_widths(block, content_w, gap) %}
  {% set cursor = namespace(x=0) %}
  {% for el in block['_row'] %}
    {% set width = widths[loop.index0] %}
    {% if '_stack' in el %}
      {# a stack's elements keep their heights and sit one under another in the cell #}
      {% set top = namespace(y=y) %}
      {% for inner in el['_stack'] %}
        {% do placed.append({"element": inner, "x": cursor.x, "y": top.y, "width": width, "height": inner['_h']}) %}
        {% set top.y = top.y + inner['_h'] + el['_gap'] %}
      {% endfor %}
    {% else %}
      {% do placed.append({"element": el, "x": cursor.x, "y": y, "width": width, "height": block['_h']}) %}
    {% endif %}
    {% set cursor.x = cursor.x + width + row_gap %}
  {% endfor %}
{% else %}
  {% do placed.append({"element": block, "x": 0, "y": y, "width": content_w, "height": block['_h']}) %}
{% endif %}
{% do return(placed) %}
{% endmacro %}


{# Stacks blocks top to bottom inside a `content_w` x `content_h` area.

   Returns a list of physical pages, each {"placements": [...], "used": pixels_of_height_used}. With
   `paginate=false`, content that does not fit raises an error that says by how much, so an overflow
   is a build failure rather than a clipped page. With `paginate=true` the flow continues on a new
   page; a single block taller than a whole page is always an error, since it could never fit. #}
{% macro flow(blocks, content_w, content_h, gap, paginate, where) %}
{% set pages = [] %}
{% set state = namespace(current=[], y=0) %}
{% for block in blocks %}
  {% if block is not mapping or ('id' not in block and '_row' not in block) %}
    {% do sigma_report.fail(where, "blocks are elements or rows; a stack(...) belongs inside a row(...), got " ~ block) %}
  {% endif %}
  {% do sigma_report.resolve_block(block, content_w, gap) %}
  {# an h='fill' element needs at least `_fill_min` pixels; it then takes everything below it #}
  {% set fill = block.get('_fill') %}
  {% set h = block['_fill_min'] if fill else block['_h'] %}
  {% if h > content_h %}
    {% do sigma_report.fail(where, "a block is " ~ h ~ "px tall but the page's content area is only " ~ content_h ~ "px. Lower its `h=`, or use a larger page_size / smaller margin.") %}
  {% endif %}
  {% set needed = state.y + (gap if state.current else 0) + h %}
  {% if needed > content_h %}
    {% if not paginate %}
      {% do sigma_report.fail(where, "content overflows the page by " ~ (needed - content_h) ~ "px (" ~ needed ~ "px of " ~ content_h ~ "px). Pass paginate=true to continue on a new page, or shrink the content.") %}
    {% endif %}
    {% do pages.append({"placements": state.current, "used": state.y}) %}
    {% set state.current = [] %}
    {% set state.y = 0 %}
  {% endif %}
  {% set top = state.y + (gap if state.current else 0) %}
  {% if fill %}
    {% do block.update({"_h": content_h - top}) %}
    {% set h = content_h - top %}
  {% endif %}
  {% for p in sigma_report.place_block(block, top, content_w, gap) %}
    {% do state.current.append(p) %}
  {% endfor %}
  {% set state.y = top + h %}
{% endfor %}
{% do pages.append({"placements": state.current, "used": state.y}) %}
{% do return(pages) %}
{% endmacro %}


{# `<Element .../>` lines for a list of placements. Coordinates are integers. #}
{% macro placements_xml(placements, indent) %}
{% set pad = '  ' * indent %}
{% set lines = [] %}
{% for p in placements %}
  {% do lines.append(pad ~ '<Element elementId="' ~ p['element']['id'] ~ '" x="' ~ p['x'] ~ '" y="' ~ p['y'] ~ '" width="' ~ p['width'] ~ '" height="' ~ p['height'] ~ '"/>') %}
{% endfor %}
{% do return(lines | join('\n')) %}
{% endmacro %}


{# A <Page> root. An empty page is self-closing, as in Sigma's own examples. #}
{% macro page_xml(page_id, placements) %}
{% if not placements %}
  {% do return('<Page id="' ~ page_id ~ '"/>') %}
{% endif %}
{% do return('<Page id="' ~ page_id ~ '">\n' ~ sigma_report.placements_xml(placements, 1) ~ '\n</Page>') %}
{% endmacro %}


{# A <Panel> root (type is `header` or `footer`). #}
{% macro panel_xml(panel_id, panel_type, placements) %}
{% do return('<Panel id="' ~ panel_id ~ '" type="' ~ panel_type ~ '">\n' ~ sigma_report.placements_xml(placements, 1) ~ '\n</Panel>') %}
{% endmacro %}
