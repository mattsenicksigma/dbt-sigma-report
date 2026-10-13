{# Text, headings, dividers and images: the non-data elements. #}


{# A markdown text element. `body` supports Sigma's markdown plus inline HTML spans and `{{formula}}`
   segments. `key` gives it a stable id; it defaults to the body text. #}
{% macro text(body, key=none, h=28, align='top') %}
{% set el = sigma_report.new_element('text', 'text', key, body, h) %}
{% do el.update({"body": body, "verticalAlign": align}) %}
{% do return(el) %}
{% endmacro %}


{# A page number: Sigma's dynamic text with the current page and the page count, for a footer.
   `format` uses `{page}` and `{total}`, so '{page} of {total}' (the default) or 'Page {page}'. It is a
   text element, so give it a narrow cell: `report(page_numbers=true)` does that for you. #}
{% macro page_number(format='{page} of {total}', key='page-number', h=24) %}
{% if format is not string or ('{page}' not in format and '{total}' not in format) %}
  {% do sigma_report.fail('page_number', "format must be a string using {page} and/or {total}, got " ~ format) %}
{% endif %}
{% set body = format.replace('{page}', '{{CurrentPageNumber()}}').replace('{total}', '{{TotalPageCount()}}') %}
{% do return(sigma_report.text('<p class="p-small">' ~ body ~ '</p>', key=key, h=h)) %}
{% endmacro %}


{# A report title: a level-1 heading with an optional muted subtitle underneath. #}
{% macro title(text, subtitle=none, key=none, h=64) %}
{% set body = '# ' ~ text %}
{% if subtitle %}
  {% set body = body ~ '\n\n<span style="color: ' ~ sigma_report.color_ref('muted') ~ '">' ~ subtitle ~ '</span>' %}
{% endif %}
{% do return(sigma_report.text(body, key=key or ('title:' ~ text), h=h, align='center')) %}
{% endmacro %}


{# A section heading, one step below `title`. #}
{% macro heading(text, key=none, h=32) %}
{% do return(sigma_report.text('### ' ~ text, key=key or ('heading:' ~ text), h=h, align='center')) %}
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
