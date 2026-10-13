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
   `# ` / `## ` / `### ` headings use the `h1_size` / `h2_size` / `h3_size` settings (36 / 28 / 22px) and
   everything else `body_size` (14px). Blank lines separate paragraphs. #}
{% macro text_parts(body) %}
{% set parts = [] %}
{% for line in body.split('\n') %}
  {% set stripped = line.strip() %}
  {% if stripped %}
    {% set size = sigma_report.setting('h1_size') if stripped.startswith('# ') else (sigma_report.setting('h2_size') if stripped.startswith('## ') else (sigma_report.setting('h3_size') if stripped.startswith('### ') else sigma_report.setting('body_size'))) %}
    {% do parts.append({"text": sigma_report.visible_text(stripped.lstrip('#').strip()), "size": size}) %}
  {% endif %}
{% endfor %}
{% do return(parts) %}
{% endmacro %}


{# How tall `parts` need to be when drawn `width` pixels wide: characters per line from the font size
   (a character is about `char_width` em wide), lines per paragraph, `line_height` times the font size per
   line, `text_padding` around. An estimate, deliberately a bit generous - clipped text is worse than a
   little white space. All three are project settings, so a theme with a wider font can recalibrate. #}
{% macro text_height(parts, width) %}
{% set pad = sigma_report.setting('text_padding') %}
{% set char_w = sigma_report.setting('char_width') %}
{% set line_h = sigma_report.setting('line_height') %}
{% set avail = [width - 2 * pad, 40] | max %}
{% set total = namespace(h=2 * pad + 6 * ((parts | length) - 1)) %}
{% for part in parts %}
  {% set per_line = [(avail / (part['size'] * char_w)) | int, 1] | max %}
  {% set chars = [part['text'] | length, 1] | max %}
  {% set lines = ((chars + per_line - 1) / per_line) | int %}
  {% set total.h = total.h + ((lines * part['size'] * line_h) + 0.999) | int %}
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


{# A report title: bold text (`title_size`, 28px) with an optional muted subtitle (`body_size`). (A
   markdown `# ` heading is far larger in Sigma's default theme and clips a long title in a fixed box.)
   Sized from its content, so a long title wraps onto a second line and the rest of the page moves
   down; pass `h=` to fix it. #}
{% macro title(text, subtitle=none, key=none, h=none) %}
{% set size = sigma_report.setting('title_size') %}
{% set body = '<span style="font-size: ' ~ size ~ 'px">**' ~ text ~ '**</span>' %}
{% set parts = [{"text": text, "size": size}] %}
{% if subtitle %}
  {% set body = body ~ '\n\n<span style="color: ' ~ sigma_report.color_ref('muted') ~ '">' ~ subtitle ~ '</span>' %}
  {% do parts.append({"text": subtitle, "size": sigma_report.setting('body_size')}) %}
{% endif %}
{% set el = sigma_report.new_element('text', 'title', key or ('title:' ~ text), none, h if h is not none else 1) %}
{% do el.update({"body": body, "verticalAlign": "center"}) %}
{% if h is none %}
  {% do el.update({"_auto": parts}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A section heading, one step below `title`: bold `heading_size` (20px). Sized from its content like
   `title`. #}
{% macro heading(text, key=none, h=none) %}
{% set size = sigma_report.setting('heading_size') %}
{% set el = sigma_report.new_element('text', 'heading', key or ('heading:' ~ text), none, h if h is not none else 1) %}
{% do el.update({"body": '<span style="font-size: ' ~ size ~ 'px">**' ~ text ~ '**</span>', "verticalAlign": "center"}) %}
{% if h is none %}
  {% do el.update({"_auto": [{"text": text, "size": size}]}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# A rule between sections. Give repeated dividers distinct keys. #}
{% macro divider(key='divider', direction='horizontal', h=none) %}
{% set el = sigma_report.new_element('divider', 'divider', key, none, sigma_report.setting('divider_h', h)) %}
{% do el.update({
  "direction": direction,
  "style": {"color": sigma_report.color_ref('hairline'), "width": 1, "strokeStyle": "solid"},
}) %}
{% do return(el) %}
{% endmacro %}


{# An image from a URL (a logo, say). `fit` is Sigma's `contain` / `cover` / `scale-down` / `stretch`. #}
{% macro image(url, key=none, alt=none, h=none, fit='contain') %}
{% set el = sigma_report.new_element('image', 'image', key, url, sigma_report.setting('image_h', h)) %}
{% do el.update({"source": {"kind": "url", "url": url}, "style": {"fit": fit}}) %}
{% if alt is not none %}
  {% do el.update({"alt": alt}) %}
{% endif %}
{% do return(el) %}
{% endmacro %}
