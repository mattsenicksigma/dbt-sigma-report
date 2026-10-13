{# Actions: what happens when someone clicks a button, selects a table row or changes a control.

   Sigma's request schema for `POST /v2/reports` takes an `actions` array on buttons, tables, controls,
   charts, KPIs and more (the same `Actions` schema as workbooks). Each action is a *sequence*: an id, one
   trigger and a list of effects that run in order. This file builds those pieces; nothing here talks to
   Sigma, so, like the rest of the package, it is pure compile-time JSON.

   Whether a *rendered, paginated* report runs them is Sigma's call, not this package's. The schema accepts
   them (checked by scripts/validate_against_sigma_schema.py); confirm behavior on a real report with
   `export_reports.py --push --dry-run`, then in the UI.

     {% set refresh = sigma_report.button('Refresh', key='refresh', actions=[
          sigma_report.action('on-click', [sigma_report.refresh_element(orders)]),
        ]) %}

   or onto any element that already exists:

     {% do sigma_report.with_actions(orders, [
          sigma_report.action('on-select', [sigma_report.set_control_value('region-control', 'West')]),
        ]) %}

   Effects that have no builder here (call-api, insert-rows, update-rows, send-embed-event, if-else, ...)
   go through `effect(name, {...})`, which takes Sigma's own fields. #}


{# Triggers Sigma accepts as a bare string. A trigger can also be a mapping (an `on-select` scoped to one
   column, or with a `condition`), which is passed through as written. #}
{% macro action_triggers() %}
{% do return(['on-click', 'on-select', 'on-primary-cta-click', 'on-secondary-cta-click', 'on-close', 'on-change', 'on-submit', 'on-reset']) %}
{% endmacro %}


{# An element, page or control given as a macro result (a dict with an `id`) or as a bare id string. #}
{% macro _ref(value, where, what) %}
{% if value is mapping and value['id'] %}
  {% do return(value['id']) %}
{% elif value is string and value %}
  {% do return(value) %}
{% endif %}
{% do sigma_report.fail(where, what ~ " must be an element / page built by a sigma_report macro, or an id string, got " ~ value) %}
{% endmacro %}


{# A button. `appearance`: filled / outline / text. `align`: left / center / right / stretch. #}
{% macro button(text, actions=[], key=none, h=40, appearance='filled', align='left', size='medium', radius='round') %}
{% set el = sigma_report.new_element('button', 'button', key, text, h) %}
{% if appearance not in ['filled', 'outline', 'text'] %}
  {% do sigma_report.fail('button', "appearance must be 'filled', 'outline' or 'text', got '" ~ appearance ~ "'.") %}
{% endif %}
{% if align not in ['left', 'center', 'right', 'stretch'] %}
  {% do sigma_report.fail('button', "align must be 'left', 'center', 'right' or 'stretch', got '" ~ align ~ "'.") %}
{% endif %}
{% if size not in ['small', 'medium', 'large'] %}
  {% do sigma_report.fail('button', "size must be 'small', 'medium' or 'large', got '" ~ size ~ "'.") %}
{% endif %}
{% if radius not in ['square', 'round', 'pill'] %}
  {% do sigma_report.fail('button', "radius must be 'square', 'round' or 'pill', got '" ~ radius ~ "'.") %}
{% endif %}
{% do el.update({"text": text, "appearance": appearance, "align": align, "size": size, "borderRadius": radius}) %}
{% if appearance == 'filled' %}
  {% do el.update({"fillColor": sigma_report.color_ref('primary')}) %}
{% endif %}
{% if actions %}
  {% do sigma_report.with_actions(el, actions) %}
{% endif %}
{% do return(el) %}
{% endmacro %}


{# One action sequence: `trigger` (see action_triggers) and the effects to run, in order. `key` keeps the
   action's id stable if you reorder a list of them; it defaults to the position. #}
{% macro action(trigger, effects, key=none) %}
{% if trigger is string %}
  {% if trigger not in sigma_report.action_triggers() %}
    {% do sigma_report.fail('action', "unknown trigger '" ~ trigger ~ "'. Use one of " ~ sigma_report.action_triggers() | join(', ') ~ ", or a mapping.") %}
  {% endif %}
{% elif trigger is not mapping or 'on' not in trigger %}
  {% do sigma_report.fail('action', "a trigger is a string or a mapping with an 'on' key, got " ~ trigger) %}
{% endif %}
{% if effects is string or effects is mapping or effects is not iterable or effects | length == 0 %}
  {% do sigma_report.fail('action', "effects must be a non-empty list of sigma_report effects.") %}
{% endif %}
{% for e in effects %}
  {% if e is not mapping or 'effect' not in e %}
    {% do sigma_report.fail('action', "each effect must be built by a sigma_report effect macro (a mapping with an 'effect' key), got " ~ e) %}
  {% endif %}
{% endfor %}
{% do return({"trigger": trigger, "effects": effects, "_key": key}) %}
{% endmacro %}


{# Attach actions to an element (any macro's result, or raw()). The element is updated in place and
   returned. Calling it twice appends. Ids come from the element's id, the trigger and the action's key or
   position, so they are stable across compiles. #}
{% macro with_actions(el, actions) %}
{% if el is not mapping or 'id' not in el %}
  {% do sigma_report.fail('with_actions', "expected an element built by a sigma_report macro, got " ~ el) %}
{% endif %}
{% if actions is string or actions is mapping or actions is not iterable %}
  {% do sigma_report.fail('with_actions', "actions must be a list of sigma_report.action(...) results.") %}
{% endif %}
{% set merged = [] %}
{% for existing in el.get('actions', []) %}{% do merged.append(existing) %}{% endfor %}
{% for a in actions %}
  {% if a is not mapping or 'trigger' not in a or 'effects' not in a %}
    {% do sigma_report.fail('with_actions', "each action must be built by sigma_report.action(...), got " ~ a) %}
  {% endif %}
  {% set on = a['trigger'] if a['trigger'] is string else a['trigger']['on'] %}
  {% set path = 'action:' ~ el['id'] ~ ':' ~ on ~ ':' ~ (a['_key'] or (merged | length)) %}
  {% do merged.append({"id": sigma_report.freeze_id(path), "trigger": a['trigger'], "effects": a['effects']}) %}
{% endfor %}
{% set ids = [] %}
{% for a in merged %}
  {% if a['id'] in ids %}
    {% do sigma_report.fail('with_actions', "two actions on '" ~ el['id'] ~ "' resolve to the same id. Give one of them a distinct `key=`.") %}
  {% endif %}
  {% do ids.append(a['id']) %}
{% endfor %}
{% do el.update({"actions": merged}) %}
{% do return(el) %}
{% endmacro %}


{# ---- effects ----------------------------------------------------------------------------------------- #}

{# Any effect, with Sigma's own fields: effect('call-api', {'connectorId': '...'}). #}
{% macro effect(name, properties={}) %}
{% if properties is not mapping %}
  {% do sigma_report.fail('effect', "properties must be a mapping of Sigma's own fields, got " ~ properties) %}
{% endif %}
{% if 'effect' in properties %}
  {% do sigma_report.fail('effect', "'effect' is the first argument; don't repeat it in properties.") %}
{% endif %}
{% set out = {"effect": name} %}
{% do out.update(properties) %}
{% do return(out) %}
{% endmacro %}


{# Set a control to a value. `control` is the control's id. `value` is a string, number or boolean (typed
   for you), a list of strings, or a Sigma value mapping used as written, e.g.
   {'type': 'date', 'value': '2026-01-01'}. #}
{% macro set_control_value(control, value) %}
{% set control_id = sigma_report._ref(control, 'set_control_value', 'control') %}
{% if value is mapping %}
  {% set typed = value %}
{% elif value is true or value is false %}
  {% set typed = {"type": "boolean", "value": value} %}
{% elif value is number %}
  {% set typed = {"type": "number", "value": value} %}
{% elif value is string %}
  {% set typed = {"type": "text", "value": value} %}
{% elif value is iterable %}
  {% set typed = {"type": "text-list", "value": value | list} %}
{% else %}
  {% do sigma_report.fail('set_control_value', "value must be a string, number, boolean, list or Sigma value mapping, got " ~ value) %}
{% endif %}
{% do return({"effect": "set-control-value", "control": control_id, "value": {"type": "constant", "value": typed}}) %}
{% endmacro %}


{# Clear one control. #}
{% macro clear_control(control) %}
{% do return({"effect": "clear-control", "scope": {"type": "control", "controlId": sigma_report._ref(control, 'clear_control', 'control')}}) %}
{% endmacro %}


{# Clear many controls at once: `scope` is 'workbook' (the whole report), 'page' (give `page=`, or omit for
   the current page) or 'container' (give `container=`). #}
{% macro clear_controls(scope='workbook', page=none, container=none) %}
{% if scope not in ['workbook', 'page', 'container'] %}
  {% do sigma_report.fail('clear_controls', "scope must be 'workbook', 'page' or 'container', got '" ~ scope ~ "'.") %}
{% endif %}
{% set target = {"type": scope} %}
{% if scope == 'page' and page is not none %}
  {% do target.update({"pageId": sigma_report._ref(page, 'clear_controls', 'page')}) %}
{% elif scope == 'container' %}
  {% if container is none %}
    {% do sigma_report.fail('clear_controls', "scope 'container' needs container=.") %}
  {% endif %}
  {% do target.update({"containerElementId": sigma_report._ref(container, 'clear_controls', 'container')}) %}
{% endif %}
{% do return({"effect": "clear-control", "scope": target}) %}
{% endmacro %}


{# Open a URL. `url` supports `{{formula}}` segments. `target`: '_blank' (new tab), '_self' or '_parent'. #}
{% macro open_url(url, target='_blank') %}
{% if target not in ['_blank', '_self', '_parent'] %}
  {% do sigma_report.fail('open_url', "target must be '_blank', '_self' or '_parent', got '" ~ target ~ "'.") %}
{% endif %}
{% do return({"effect": "open-url", "openTarget": target, "url": url}) %}
{% endmacro %}


{# Jump to a page or to an element on one. Pass exactly one of `page` / `element`. #}
{% macro navigate(page=none, element=none) %}
{% if (page is none) == (element is none) %}
  {% do sigma_report.fail('navigate', "pass exactly one of page= or element=.") %}
{% endif %}
{% if page is not none %}
  {% do return({"effect": "navigate", "target": {"type": "page", "page": sigma_report._ref(page, 'navigate', 'page')}}) %}
{% endif %}
{% do return({"effect": "navigate", "target": {"type": "element", "element": sigma_report._ref(element, 'navigate', 'element')}}) %}
{% endmacro %}


{# Re-run an element's query. #}
{% macro refresh_element(element) %}
{% do return({"effect": "refresh-element", "target": {"type": "element", "element": sigma_report._ref(element, 'refresh_element', 'element')}}) %}
{% endmacro %}


{# Download the report, one page or one element. `format`: csv / excel / json / pdf / png. Pass at most one
   of `page` / `element`; with neither, everything is exported. `layout` ('portrait' / 'landscape') and
   `page_size` (letter, legal, tabloid, a0-a4) apply to pdf. #}
{% macro download(format='pdf', page=none, element=none, layout='portrait', page_size='letter') %}
{% if format not in ['csv', 'excel', 'json', 'pdf', 'png'] %}
  {% do sigma_report.fail('download', "format must be csv, excel, json, pdf or png, got '" ~ format ~ "'.") %}
{% endif %}
{% if page is not none and element is not none %}
  {% do sigma_report.fail('download', "pass at most one of page= or element=.") %}
{% endif %}
{% if page is not none %}
  {% set source = {"type": "page", "page": sigma_report._ref(page, 'download', 'page')} %}
{% elif element is not none %}
  {% set source = {"type": "element", "element": sigma_report._ref(element, 'download', 'element')} %}
{% else %}
  {% set source = {"type": "all"} %}
{% endif %}
{% set fmt = {"type": format} %}
{% if format == 'pdf' %}
  {% if layout not in ['portrait', 'landscape'] %}
    {% do sigma_report.fail('download', "layout must be 'portrait' or 'landscape', got '" ~ layout ~ "'.") %}
  {% endif %}
  {% if page_size not in ['letter', 'legal', 'tabloid', 'a0', 'a1', 'a2', 'a3', 'a4'] %}
    {% do sigma_report.fail('download', "page_size must be letter, legal, tabloid or a0-a4, got '" ~ page_size ~ "'.") %}
  {% endif %}
  {% do fmt.update({"layout": layout, "pageSize": page_size}) %}
{% endif %}
{% do return({"effect": "export", "channel": "download", "source": source, "format": fmt}) %}
{% endmacro %}
