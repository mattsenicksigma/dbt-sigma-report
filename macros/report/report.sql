{# A page: a name and the blocks (elements and rows) stacked on it. Blocks can be passed individually or
   as lists (the composite macros such as `report_header` return lists); lists are flattened one level
   so they can be mixed freely.

   `paginate=true` lets the page continue onto further physical pages when its content is taller than
   one page ("Name", "Name (2)", ...). Without it an overflow fails the build. #}
{% macro page(name, blocks, key=none, paginate=false) %}
{% if not blocks %}
  {% do sigma_report.fail('page', "page '" ~ name ~ "' has no elements.") %}
{% endif %}
{% do return({
  "id": sigma_report.freeze_id('page:' ~ (key or name)),
  "name": name,
  "_key": key or name,
  "_blocks": sigma_report.flatten(blocks),
  "_paginate": paginate,
}) %}
{% endmacro %}


{# Every element a list of placements puts on the page, in order. #}
{% macro placed_elements(placements) %}
{% set out = [] %}
{% for p in placements %}
  {% do out.append(p['element']) %}
{% endfor %}
{% do return(out) %}
{% endmacro %}


{# The top-level macro: assembles pages into a report in Sigma's code representation
   (https://help.sigmacomputing.com/docs/manage-reports-as-code), as the request body of
   `POST /v2/reports`:

     {name, folderId, description, contents: {schemaVersion, kind, pages, elements, panels,
                                              settings, config, layout}}

     name         report name in Sigma
     pages        list of sigma_report.page(...)
     theme        optional per-report overrides on top of the project theme (see theme.sql)
     folder_id    Sigma folder to create the report in; defaults to the `sigma_folder_id` project var
     report_id    an existing report to update instead of creating a new one (the export script
                  replaces its contents; omit on first create)
     description  free-text description
     page_size    'letter' (default), 'legal', 'tabloid', 'a4', 'a3', 'screen', or {width: px, height: px}
     orientation  'portrait' / 'landscape'; none keeps the preset's own shape
     margin       page margin in pixels
     gap          vertical space between blocks, in pixels
     header       elements / rows for the header panel, repeated on every page (none = no header)
     footer       elements / rows for the footer panel
     header_height, footer_height   panel heights in pixels
     schedules    list of sigma_report.schedule(...): scheduled PDF exports. Carried on the spec beside
                  `contents` and applied by the export script after the report is pushed

   Header and footer space is subtracted from the content area, so panel content can never overlap
   page content.

   Everything is validated here, at parse time: an empty page, a duplicate page name, an element used
   twice, or content that does not fit its page fails `dbt parse` rather than reaching Sigma. #}
{% macro report(name, pages, theme={}, folder_id=none, report_id=none, description=none, page_size='letter', orientation=none, margin=48, gap=16, header=none, footer=none, header_height=48, footer_height=32, schedules=[]) %}
{% if not pages %}
  {% do sigma_report.fail('report', "pages must not be empty.") %}
{% endif %}
{% set dims = sigma_report.page_dimensions(page_size, orientation) %}
{% set content_w = dims['width'] - 2 * margin %}
{% set panel_space = (header_height if header else 0) + (footer_height if footer else 0) %}
{% set content_h = dims['height'] - 2 * margin - panel_space %}
{% if content_w <= 0 or content_h <= 0 %}
  {% do sigma_report.fail('report', "margin " ~ margin ~ "px and the header/footer leave no room on a " ~ dims['width'] ~ "x" ~ dims['height'] ~ "px page.") %}
{% endif %}

{% set page_stubs = [] %}
{% set layout_roots = [] %}
{% set elements = [] %}
{% set seen_ids = {} %}
{% set page_names = [] %}

{# header and footer panels: laid out once, then attached to every physical page #}
{% set panel_defs = [] %}
{% for spec in [{"type": "header", "blocks": header, "height": header_height}, {"type": "footer", "blocks": footer, "height": footer_height}] if spec['blocks'] %}
  {% set blocks = sigma_report.flatten(spec['blocks']) %}
  {% set panel_pages = sigma_report.flow(blocks, content_w, spec['height'], gap, false, spec['type']) %}
  {% do panel_defs.append({
    "id": sigma_report.freeze_id('panel:' ~ spec['type']),
    "type": spec['type'],
    "height": spec['height'],
    "placements": panel_pages[0]['placements'],
  }) %}
{% endfor %}

{% for p in pages %}
  {% set physical = sigma_report.flow(p['_blocks'], content_w, content_h, gap, p['_paginate'], "page '" ~ p['name'] ~ "'") %}
  {% for sheet in physical %}
    {% set page_id = p['id'] if loop.first else sigma_report.freeze_id('page:' ~ p['_key'] ~ ':' ~ loop.index) %}
    {% set page_name = p['name'] if loop.first else p['name'] ~ ' (' ~ loop.index ~ ')' %}
    {% if page_name in page_names %}
      {% do sigma_report.fail('report', "duplicate page name '" ~ page_name ~ "' - page names must be unique.") %}
    {% endif %}
    {% do page_names.append(page_name) %}
    {% do page_stubs.append({"id": page_id, "name": page_name}) %}
    {% do layout_roots.append(sigma_report.page_xml(page_id, sheet['placements'])) %}
    {% for el in sigma_report.placed_elements(sheet['placements']) %}
      {% if el['id'] in seen_ids %}
        {% do sigma_report.fail('report', "'" ~ el['_key'] ~ "' and '" ~ seen_ids[el['id']] ~ "' resolve to the same element id (an element can be placed once). Give one of them a distinct `key=`.") %}
      {% endif %}
      {% do seen_ids.update({el['id']: el['_key']}) %}
      {% do elements.append(el) %}
    {% endfor %}
  {% endfor %}
{% endfor %}

{% set panels = [] %}
{% for panel in panel_defs %}
  {% set config = {"height": panel['height']} %}
  {% set ids = [] %}
  {% for stub in page_stubs %}{% do ids.append(stub['id']) %}{% endfor %}
  {% do panels.append({"id": panel['id'], "type": panel['type'], "title": panel['type'] | title, "config": config, "pages": ids}) %}
  {% do layout_roots.append(sigma_report.panel_xml(panel['id'], panel['type'], panel['placements'])) %}
  {% for el in sigma_report.placed_elements(panel['placements']) %}
    {% if el['id'] in seen_ids %}
      {% do sigma_report.fail('report', "'" ~ el['_key'] ~ "' and '" ~ seen_ids[el['id']] ~ "' resolve to the same element id (an element can be placed once). Give one of them a distinct `key=`.") %}
    {% endif %}
    {% do seen_ids.update({el['id']: el['_key']}) %}
    {% do elements.append(el) %}
  {% endfor %}
{% endfor %}

{% set colors = sigma_report.theme(theme)['colors'] %}
{% set contents = {
  "schemaVersion": 1,
  "kind": "report",
  "pages": page_stubs,
  "elements": sigma_report.resolve_colors(sigma_report.strip_private(elements), colors),
  "settings": sigma_report.theme_settings(theme),
  "config": {"margin": margin, "pageWidth": dims['width'], "pageHeight": dims['height']},
  "layout": '<?xml version="1.0" encoding="utf-8"?>\n' ~ (layout_roots | join('\n')) ~ '\n',
} %}
{% if panels %}
  {% do contents.update({"panels": panels}) %}
{% endif %}
{% set spec = {"name": name, "contents": contents} %}
{% set folder = folder_id or var('sigma_folder_id', none) %}
{% if folder %}
  {% do spec.update({"folderId": folder}) %}
{% endif %}
{% if report_id %}
  {% do spec.update({"reportId": report_id}) %}
{% endif %}
{% if schedules %}
  {% set titles = [] %}
  {% for s in schedules %}
    {% if s is not mapping or 'configV2' not in s %}
      {% do sigma_report.fail('report', "schedules must be built by sigma_report.schedule(...), got " ~ s) %}
    {% endif %}
    {% if s['configV2']['title'] in titles %}
      {% do sigma_report.fail('report', "two schedules are named '" ~ s['configV2']['title'] ~ "' - schedule names must be unique.") %}
    {% endif %}
    {% do titles.append(s['configV2']['title']) %}
  {% endfor %}
  {% do spec.update({"schedules": schedules}) %}
{% endif %}
{% if description %}
  {% do spec.update({"description": description}) %}
{% endif %}
{% do return(spec) %}
{% endmacro %}


{# Attaches a composed spec to the calling dbt model's `meta`, where it lands in manifest.json on
   `dbt parse` / `dbt compile`. The model body still has to be valid SQL; a one-line `select 1` is
   conventional. `materialized` defaults to `view` (the cheapest object every adapter supports); use
   `ephemeral` to avoid creating anything in the warehouse. #}
{% macro materialize(spec, materialized='view') %}
{{ config(materialized=materialized, meta={'sigma_report': spec}) }}
{% endmacro %}
