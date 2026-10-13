{# Layout: turns a page's blocks into pixel positions, and the positions into the XML string Sigma
   expects in a report's `contents.layout`.

   Reports are *paginated documents*, not responsive canvases: every element has an absolute x / y /
   width / height in pixels, measured from the top-left of the page's content area (inside the
   margin). A workbook's 24-column grid does not exist here, so this package supplies a layout model
   and compiles it down to those pixels.

   The model is a small tree. A **block** is one of

     element      a chart, table, text, ...
     row(...)     children side by side, sharing the width (equally or by weight)
     stack(...)   children one above another, sharing the height
     at(...)      an element pinned at an absolute position, outside the flow

   and rows and stacks nest in each other to any depth, so any grid-like arrangement can be written
   directly. Sizing follows two rules.

     * Width flows down: a row divides its width between its children by weight; a stack gives every
       child its full width.
     * Height is measured up, then shared out: each block has a *natural* height (an element's `h`;
       text sized from its content and width; a row = its tallest child; a stack = its children plus
       gaps). A block may also be *flexible* (`flex()`, or `h='fill'`): it takes a share of whatever
       height is left over, by weight. A flexible block on a page takes the rest of the page.

   A page stacks its top-level blocks with `gap` between them. When the next block would not fit, the
   page either fails (the default, so an overflow is never silent) or, with `paginate=true`, continues
   on a new physical page that repeats the headers and footers. #}


{# A horizontal band of blocks sharing the width.

     sigma_report.row([revenue_kpi, orders_kpi, margin_kpi])
     sigma_report.row([by_region, by_month], widths=[2, 1])
     sigma_report.row([sigma_report.stack([kpi_a, kpi_b]), sigma_report.stack([chart_a, chart_b])])

   `widths` are relative weights (default: equal). Every child is stretched to the height of the row,
   so a row is always a clean rectangle. `gap` is the space between the children in pixels (default:
   the report's gap). `pad` reserves that much trailing weight as empty space, which is how `grid()`
   keeps a short last row the same cell width as the rows above it. Children are elements, rows and
   stacks, or lists of them (the composites return lists). #}
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
{% for item in items %}
  {% do sigma_report.check_block(item, 'row') %}
  {% if weights[loop.index0] is not number or weights[loop.index0] <= 0 %}
    {% do sigma_report.fail('row', "widths must be positive numbers, got " ~ weights[loop.index0]) %}
  {% endif %}
{% endfor %}
{% do return({"_row": items, "_widths": weights, "_gap": gap, "_pad": pad}) %}
{% endmacro %}


{# A vertical group of blocks - two KPIs above a chart, say:

     sigma_report.row([sigma_report.stack([revenue, orders]), trend_chart], widths=[1, 2])

   Children keep their natural heights, apart from flexible ones (`flex()`), which share what is left
   when the stack is given more room than it needs (as the cell of a taller row, or the flexible block
   on a page). `gap` (pixels) separates them; the default is the report's gap. #}
{% macro stack(elements, gap=none) %}
{% set items = sigma_report.flatten(elements) %}
{% if not items %}
  {% do sigma_report.fail('stack', "a stack needs at least one element.") %}
{% endif %}
{% for item in items %}
  {% do sigma_report.check_block(item, 'stack') %}
{% endfor %}
{% do return({"_stack": items, "_gap": gap}) %}
{% endmacro %}


{# Makes a block flexible: it takes a share of the leftover height, in proportion to `weight`.

     sigma_report.stack([sigma_report.flex(table, weight=2), sigma_report.flex(chart)])   -- 2/3 and 1/3
     sigma_report.flex(sigma_report.row([map, legend]), min=300)

   `min` is the least height the block may have (default: its natural height). Works on elements, rows
   and stacks; an element built with `h='fill'` is already flexible. The block is updated in place and
   returned. A block that contains a flexible child is flexible too, with weight 1, unless it is given
   its own. #}
{% macro flex(block, weight=1, min=none) %}
{% do sigma_report.check_block(block, 'flex') %}
{% if weight is not number or weight <= 0 %}
  {% do sigma_report.fail('flex', "weight must be a positive number, got " ~ weight) %}
{% endif %}
{% if min is not none and (min is not number or min < 0) %}
  {% do sigma_report.fail('flex', "min must be a number of pixels, got " ~ min) %}
{% endif %}
{% do block.update({"_flex": weight}) %}
{% if min is not none %}
  {% do block.update({"_min": min}) %}
{% endif %}
{% do return(block) %}
{% endmacro %}


{# Pins an element at an absolute position, outside the flow. Coordinates are pixels from the top-left of
   the content area, and the element may overlap flowed content (a watermark, a callout, a logo over a
   banner); say so with `overlap=true`, otherwise the geometry check treats an overlap as a mistake.
   It belongs to the page it is listed on and takes no room in the flow.

     sigma_report.at(logo, x=620, y=0, width=100, height=48)    #}
{% macro at(element, x, y, width, height, overlap=false) %}
{% if element is not mapping or 'id' not in element or element.get('_row') is not none or element.get('_stack') is not none %}
  {% do sigma_report.fail('at', "pins a single element built by a sigma_report macro, got " ~ element) %}
{% endif %}
{% for pair in [['x', x], ['y', y]] %}
  {% if pair[1] is not number or pair[1] < 0 %}
    {% do sigma_report.fail('at', pair[0] ~ " must be a number of pixels >= 0, got " ~ pair[1]) %}
  {% endif %}
{% endfor %}
{% for pair in [['width', width], ['height', height]] %}
  {% if pair[1] is not number or pair[1] <= 0 %}
    {% do sigma_report.fail('at', pair[0] ~ " must be a positive number of pixels, got " ~ pair[1]) %}
  {% endif %}
{% endfor %}
{% do return({"_abs": {"element": element, "x": x, "y": y, "width": width, "height": height, "overlap": overlap}}) %}
{% endmacro %}


{# Starts a new physical page here: everything after it goes onto the next page. Needs `paginate=true` on
   the page (otherwise there is no next page to go to), and does nothing if the page is still empty, so
   it never leaves a blank page. Page-level only - a break cannot sit inside a row or stack. #}
{% macro page_break() %}
{% do return({"_break": true}) %}
{% endmacro %}


{# Raises unless `block` can be a child of `where` (a row, a stack, or flex): an element, a row or a
   stack. `at()` pins to the page and `page_break()` is a page event, so neither can live inside. #}
{% macro check_block(block, where) %}
{% if block is not mapping %}
  {% do sigma_report.fail(where, "expected an element, row or stack built by sigma_report macros, got " ~ block) %}
{% endif %}
{% if '_abs' in block %}
  {% do sigma_report.fail(where, "at(...) pins an element to the page, so it cannot be inside a row or stack - list it on the page.") %}
{% endif %}
{% if '_break' in block %}
  {% do sigma_report.fail(where, "page_break() is a page-level event, so it cannot be inside a row or stack.") %}
{% endif %}
{% if 'id' not in block and '_row' not in block and '_stack' not in block %}
  {% do sigma_report.fail(where, "expected an element, row or stack built by sigma_report macros, got " ~ block) %}
{% endif %}
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
   rounding so a row without `pad` spans the width exactly. #}
{% macro row_cell_widths(block, width, gap) %}
{% set row_gap = block['_gap'] if block['_gap'] is not none else gap %}
{% set pad = block['_pad'] %}
{% set n = (block['_row'] | length) + (1 if pad > 0 else 0) %}
{% set usable = width - row_gap * (n - 1) %}
{% set total = namespace(weight=pad) %}
{% for w in block['_widths'] %}{% set total.weight = total.weight + w %}{% endfor %}
{% set cursor = namespace(x=0) %}
{% set widths = [] %}
{% for el in block['_row'] %}
  {% if loop.last and pad <= 0 %}
    {% set cell = width - cursor.x %}
  {% else %}
    {% set cell = (usable * block['_widths'][loop.index0] / total.weight) | int %}
  {% endif %}
  {% do widths.append(cell) %}
  {% set cursor.x = cursor.x + cell + row_gap %}
{% endfor %}
{% do return(widths) %}
{% endmacro %}


{# Measures a block laid out `width` pixels wide: {"h": its natural height, "flex": its flex weight}.
   A flex weight of 0 means fixed. Text is sized here, from its content and the width it will have, which
   is why measuring happens in the flow rather than when the element is built. Nothing is mutated. #}
{% macro measure(block, width, gap) %}
{% if '_row' in block %}
  {% set widths = sigma_report.row_cell_widths(block, width, gap) %}
  {% set acc = namespace(h=0, flexible=false) %}
  {% for child in block['_row'] %}
    {% set m = sigma_report.measure(child, widths[loop.index0], gap) %}
    {% if m['h'] > acc.h %}{% set acc.h = m['h'] %}{% endif %}
    {% if m['flex'] > 0 %}{% set acc.flexible = true %}{% endif %}
  {% endfor %}
  {% set own = block.get('_flex') %}
  {% set least = block.get('_min') %}
  {% do return({"h": [acc.h, least if least is not none else 0] | max, "flex": own if own is not none else (1 if acc.flexible else 0)}) %}
{% elif '_stack' in block %}
  {% set g = block['_gap'] if block['_gap'] is not none else gap %}
  {% set acc = namespace(h=g * ((block['_stack'] | length) - 1), flexible=false) %}
  {% for child in block['_stack'] %}
    {% set m = sigma_report.measure(child, width, gap) %}
    {% set acc.h = acc.h + m['h'] %}
    {% if m['flex'] > 0 %}{% set acc.flexible = true %}{% endif %}
  {% endfor %}
  {% set own = block.get('_flex') %}
  {% set least = block.get('_min') %}
  {% do return({"h": [acc.h, least if least is not none else 0] | max, "flex": own if own is not none else (1 if acc.flexible else 0)}) %}
{% endif %}
{% set natural = sigma_report.text_height(block['_auto'], width) if block.get('_auto') else block['_h'] %}
{% set least = block.get('_min') %}
{% do return({"h": [natural, least if least is not none else 0] | max, "flex": block.get('_flex') if block.get('_flex') is not none else 0}) %}
{% endmacro %}


{# Places a block in the box (x, y, width, height). Returns placements: [{element, x, y, width, height}].
   A row gives every child its cell's width and the whole height. A stack gives children their natural
   heights, and shares any extra height between its flexible children by weight (the last flexible child
   takes the rounding), so the stack always fills its box exactly when it has a flexible child. #}
{% macro place(block, x, y, width, height, gap) %}
{% set placed = [] %}
{% if '_row' in block %}
  {% set widths = sigma_report.row_cell_widths(block, width, gap) %}
  {% set row_gap = block['_gap'] if block['_gap'] is not none else gap %}
  {% set cursor = namespace(x=x) %}
  {% for child in block['_row'] %}
    {% for p in sigma_report.place(child, cursor.x, y, widths[loop.index0], height, gap) %}
      {% do placed.append(p) %}
    {% endfor %}
    {% set cursor.x = cursor.x + widths[loop.index0] + row_gap %}
  {% endfor %}
{% elif '_stack' in block %}
  {% set g = block['_gap'] if block['_gap'] is not none else gap %}
  {% set sizes = [] %}
  {% set weights = [] %}
  {% set natural = namespace(h=g * ((block['_stack'] | length) - 1), weight=0) %}
  {% for child in block['_stack'] %}
    {% set m = sigma_report.measure(child, width, gap) %}
    {% do sizes.append(m['h']) %}
    {% do weights.append(m['flex']) %}
    {% set natural.h = natural.h + m['h'] %}
    {% set natural.weight = natural.weight + m['flex'] %}
  {% endfor %}
  {% set share = namespace(extra=[height - natural.h, 0] | max, weight=natural.weight) %}
  {% set cursor = namespace(y=y) %}
  {% for child in block['_stack'] %}
    {% set h = sizes[loop.index0] %}
    {% if weights[loop.index0] > 0 and share.weight > 0 %}
      {% set mine = share.extra if weights[loop.index0] >= share.weight else (share.extra * weights[loop.index0] / share.weight) | int %}
      {% set h = h + mine %}
      {% set share.extra = share.extra - mine %}
      {% set share.weight = share.weight - weights[loop.index0] %}
    {% endif %}
    {% for p in sigma_report.place(child, x, cursor.y, width, h, gap) %}
      {% do placed.append(p) %}
    {% endfor %}
    {% set cursor.y = cursor.y + h + g %}
  {% endfor %}
{% else %}
  {% do placed.append({"element": block, "x": x, "y": y, "width": width, "height": height}) %}
{% endif %}
{% do return(placed) %}
{% endmacro %}


{# Stacks blocks top to bottom inside a `content_w` x `content_h` area.

   Returns a list of physical pages, each {"placements": [...], "used": pixels_of_height_used}. With
   `paginate=false`, content that does not fit raises an error that says by how much, so an overflow
   is a build failure rather than a clipped page. With `paginate=true` the flow continues on a new
   page; a single block taller than a whole page is always an error, since it could never fit. A
   flexible block takes all the height left on its page (at least its minimum, else it starts a new
   page). `at()` blocks do not take part in the flow: they are placed where they say, on the page they
   are listed on. #}
{% macro flow(blocks, content_w, content_h, gap, paginate, where) %}
{% set pages = [] %}
{% set state = namespace(current=[], y=0, flowed=0) %}
{% for block in blocks %}
  {% if block is not mapping or ('id' not in block and '_row' not in block and '_stack' not in block and '_abs' not in block and '_break' not in block) %}
    {% do sigma_report.fail(where, "blocks are elements, rows, stacks, at(...) or page_break(), got " ~ block) %}
  {% endif %}
  {% if '_break' in block %}
    {% if state.current %}
      {% if not paginate %}
        {% do sigma_report.fail(where, "page_break() needs paginate=true on the page - without it there is no next page to continue on.") %}
      {% endif %}
      {% do pages.append({"placements": state.current, "used": state.y}) %}
      {% set state.current = [] %}
      {% set state.y = 0 %}
      {% set state.flowed = 0 %}
    {% endif %}
  {% elif '_abs' in block %}
    {% set a = block['_abs'] %}
    {% if a['x'] + a['width'] > content_w or a['y'] + a['height'] > content_h %}
      {% do sigma_report.fail(where, "at(...) puts an element at x=" ~ a['x'] ~ ", y=" ~ a['y'] ~ " " ~ a['width'] ~ "x" ~ a['height'] ~ "px, outside the " ~ content_w ~ "x" ~ content_h ~ "px content area.") %}
    {% endif %}
    {% do state.current.append({"element": a['element'], "x": a['x'], "y": a['y'], "width": a['width'], "height": a['height'], "overlap": a['overlap']}) %}
  {% else %}
    {% set m = sigma_report.measure(block, content_w, gap) %}
    {% set flexible = m['flex'] > 0 %}
    {% set h = m['h'] %}
    {% if h > content_h %}
      {% do sigma_report.fail(where, "a block is " ~ h ~ "px tall but the page's content area is only " ~ content_h ~ "px. Lower its `h=`, or use a larger page_size / smaller margin.") %}
    {% endif %}
    {% set needed = state.y + (gap if state.flowed else 0) + h %}
    {% if needed > content_h %}
      {% if not paginate %}
        {% do sigma_report.fail(where, "content overflows the page by " ~ (needed - content_h) ~ "px (" ~ needed ~ "px of " ~ content_h ~ "px). Pass paginate=true to continue on a new page, or shrink the content.") %}
      {% endif %}
      {% do pages.append({"placements": state.current, "used": state.y}) %}
      {% set state.current = [] %}
      {% set state.y = 0 %}
      {% set state.flowed = 0 %}
    {% endif %}
    {% set top = state.y + (gap if state.flowed else 0) %}
    {% if flexible %}
      {% set h = content_h - top %}
    {% endif %}
    {% for p in sigma_report.place(block, 0, top, content_w, h, gap) %}
      {% do state.current.append(p) %}
    {% endfor %}
    {% set state.y = top + h %}
    {% set state.flowed = state.flowed + 1 %}
  {% endif %}
{% endfor %}
{% if state.current or not pages %}
  {% do pages.append({"placements": state.current, "used": state.y}) %}
{% endif %}
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
