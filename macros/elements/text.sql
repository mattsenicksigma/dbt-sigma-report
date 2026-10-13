{# Text, headings, dividers and images: the non-data elements. #}


{# The visible characters of a line of markdown: HTML tags are dropped, so a `<span style=...>` wrapper does
   not count towards how much room the text needs. #}
{% macro visible_text(line) %}
{% set out = namespace(text='') %}
{% for chunk in line.split('<') %}
  {% if loop.first %}
    {% set out.text = out.text ~ chunk %}
  {% elif '>' in chunk %}
    {% set out.text = out.text ~ chunk.split('>', 1)[1] %}
  {% endif %}
{% endfor %}
{% do return(out.text) %}
{% endmacro %}


{# The paragraphs of a markdown body with the font size each is drawn at, for estimating height:
   `# ` / `## ` / `### ` headings are 36 / 28 / 22px; everything else is 14px. Blank lines separate
   paragraphs. #}
{% macro text_parts(body) %}
{% set parts = [] %}
{% for line in body.split('\n') %}
  {% set stripped = line.strip() %}
  {% if stripped %}
    {% set size = 36 if stripped.startswith('# ') else (28 if stripped.startswith('## ') else (22 if stripped.startswith('### ') else 14)) %}
    {% do parts.append({"text": sigma_report.visible_text(stripped.lstrip('#').strip()), "size": size}) %}
  {% endif %}
{% endfor %}
{% do return(parts) %}
{% endmacro %}


{# How tall `parts` need to be when drawn `width` pixels wide: characters per line from the font size
   (a character is about 0.55 em wide), lines per paragraph, 1.35 line height, a little padding. An
   estimate, deliberately a bit generous - clipped text is worse than a little white space. #}
{% macro text_height(parts, width) %}
{% set pad = 6 %}
{% set avail = [width - 2 * pad, 40] | max %}
{% set total = namespace(h=2 * pad + 6 * ((parts | length) - 1)) %}
{% for part in parts %}
  {% set per_line = [(avail / (part['size'] * 0.55)) | int, 1] | max %}
  {% set chars = [part['text'] | length, 1] | max %}
  {% set lines = ((chars + per_line - 1) / per_line) | int %}
  {% set total.h = total.h + ((lines * part['size'] * 1.35) + 0.999) | int %}
{% endfor %}
{% do return(total.h | int) %}
{% endmacro %}


{# A markdown text element. `body` supports Sigma's markdown plus inline HTML spans and `{{formula}}`
   segments. `key` gives it a stable id; it defaults to the body text.

   `h` is a height in pixels, `'fill'`, or none (the default): none sizes the text from its content and
   the width it is laid out at, so a long paragraph in a narrow cell gets the room it needs. #}
{% macro text(body, key=none, h=none, align='top') %}
{% set el = sigma_report.new_element('text', 'text', key, body, h if h is not none else 1) %}
{% do el.update({"body": body, "verticalAlign": align}) %}
{% if h is none %}
  {% do el.update({"_auto": sigma_report.text_parts(body)}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A report title: bold 28px text with an optional muted 14px subtitle. (A markdown `# ` heading is far
   larger in Sigma's default theme and clips a long title in a fixed box.) Sized from its content, so a
   long title wraps onto a second line and the rest of the page moves down; pass `h=` to fix it. #}
{% macro title(text, subtitle=none, key=none, h=none) %}
{% set body = '<span style="font-size: 28px">**' ~ text ~ '**</span>' %}
{% set parts = [{"text": text, "size": 28}] %}
{% if subtitle %}
  {% set body = body ~ '\n\n<span style="color: ' ~ sigma_report.color_ref('muted') ~ '">' ~ subtitle ~ '</span>' %}
  {% do parts.append({"text": subtitle, "size": 14}) %}
{% endif %}
{% set el = sigma_report.new_element('text', 'title', key or ('title:' ~ text), none, h if h is not none else 1) %}
{% do el.update({"body": body, "verticalAlign": "center"}) %}
{% if h is none %}
  {% do el.update({"_auto": parts}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A section heading, one step below `title`: bold 20px. Sized from its content like `title`. #}
{% macro heading(text, key=none, h=none) %}
{% set el = sigma_report.new_element('text', 'heading', key or ('heading:' ~ text), none, h if h is not none else 1) %}
{% do el.update({"body": '<span style="font-size: 20px">**' ~ text ~ '**</span>', "verticalAlign": "center"}) %}
{% if h is none %}
  {% do el.update({"_auto": [{"text": text, "size": 20}]}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A rule between sections. Give repeated dividers distinct keys. #}
{% macro divider(key='divider', direction='horizontal', h=12) %}
{% set el = sigma_report.new_element('divider', 'divider', key, none, h) %}
{% do el.update({
  "direction": direction,
  "style": {"color": sigma_report.color_ref('hairline'), "width": 1, "strokeStyle": "solid"},
}) %}
{% do return(el) %}
{% endmacro %}


{# An image from a URL (a logo, say). `fit` is Sigma's `contain` / `cover` / `scale-down` / `stretch`. #}
{% macro image(url, key=none, alt=none, h=64, fit='contain') %}
{% set el = sigma_report.new_element('image', 'image', key, url, h) %}
{% do el.update({"source": {"kind": "url", "url": url}, "style": {"fit": fit}}) %}
{% if alt is not none %}
  {% do el.update({"alt": alt}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}
