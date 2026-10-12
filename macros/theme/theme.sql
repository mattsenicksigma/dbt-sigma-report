{# Design tokens. Every component that needs a color asks for a token ('primary', 'muted', ...) instead
   of hard-coding a hex, so one project var re-skins every report.

   A theme is a `base` (the neutral scale: canvas, ink, body, muted, hairline, fill, series_grey) plus
   a `hue` (the accent scale: primary, tint, edge, series, series_mid), plus a few fixed status
   colors. The presets are Sigma's own design-system scales (the same ones the Sigma plugin's
   workbook-building skill uses), and the defaults - base `Neutral`, hue `Blue` - are Sigma's look.

   Precedence, lowest to highest:
     1. these defaults
     2. the `sigma_report_theme` project var (dbt_project.yml -> vars)
     3. the `theme=` argument of `sigma_report.report()`

   Each level is deep-merged over the previous one, so changing `hue` keeps everything else, and
   `colors:` overrides any single token on top of the chosen scales:

     vars:
       sigma_report_theme:
         hue: Emerald                 # swap the accent scale
         colors: {primary: "#0b6e4f"} # ...or pin one token to your brand color
         categorical: ["#0b6e4f", "#f2a900", "#3d5a80"]   # series palette for multi-color charts
         fonts: {text: Inter, data: Inter}                #}


{# Neutral scales, ordered [canvas, ink, body, muted, hairline, fill, series_grey]. #}
{% macro base_palettes() %}
{% do return({
  "Neutral": ["#fafafa", "#0a0a0a", "#525252", "#737373", "#e5e5e5", "#f5f5f5", "#d4d4d4"],
  "Stone":   ["#fafaf9", "#0c0a09", "#57534d", "#79716b", "#e7e5e4", "#f5f5f4", "#d6d3d1"],
  "Zinc":    ["#fafafa", "#09090b", "#52525c", "#71717b", "#e4e4e7", "#f4f4f5", "#d4d4d8"],
  "Slate":   ["#f8fafc", "#020618", "#45556c", "#62748e", "#e2e8f0", "#f1f5f9", "#cad5e2"],
}) %}
{% endmacro %}


{# Accent scales, ordered [primary, tint, edge, series, series_mid]. #}
{% macro hue_palettes() %}
{% do return({
  "Neutral": ["#171717", "#e5e5e5", "#d4d4d4", "#525252", "#a1a1a1"],
  "Blue":    ["#1447e6", "#dbeafe", "#bedbff", "#155dfc", "#51a2ff"],
  "Indigo":  ["#432dd7", "#e0e7ff", "#c6d2ff", "#4f39f6", "#7c86ff"],
  "Violet":  ["#7008e7", "#ede9fe", "#ddd6ff", "#7f22fe", "#a684ff"],
  "Emerald": ["#007a55", "#d0fae5", "#a4f4cf", "#009966", "#00d492"],
  "Teal":    ["#00786f", "#cbfbf1", "#96f7e4", "#009689", "#00d5be"],
  "Green":   ["#008236", "#dcfce7", "#b9f8cf", "#00a63e", "#05df72"],
  "Rose":    ["#c70036", "#ffe4e6", "#ffccd3", "#ec003f", "#ff637e"],
  "Orange":  ["#ca3500", "#ffedd4", "#ffd6a7", "#f54900", "#ff8904"],
  "Amber":   ["#bb4d00", "#fef3c6", "#fee685", "#e17100", "#ffb900"],
}) %}
{% endmacro %}


{% macro default_theme() %}
{% do return({
  "name": "Light",
  "base": "Neutral",
  "hue": "Blue",
  "colors": {},
  "categorical": "superbloom",
  "sequential": none,
  "diverging": none,
  "fonts": {"text": "Inter", "data": "Inter"},
  "border_radius": "round",
  "cards": true,
}) %}
{% endmacro %}


{# The merged theme settings (before token expansion). `override` layers a per-report theme on top of
   the project var. #}
{% macro theme_config(override={}) %}
{% set merged = sigma_report.deep_merge(sigma_report.default_theme(), var('sigma_report_theme', {})) %}
{% do return(sigma_report.deep_merge(merged, override)) %}
{% endmacro %}


{# The fully-resolved theme: `colors` holds every token as a hex string. Raises on an unknown base or
   hue, so a typo in `dbt_project.yml` fails loudly instead of silently falling back to a default. #}
{% macro theme(override={}) %}
{% set t = sigma_report.theme_config(override) %}
{% set bases = sigma_report.base_palettes() %}
{% set hues = sigma_report.hue_palettes() %}
{% if t['base'] not in bases %}
  {% do sigma_report.fail('theme', "unknown base '" ~ t['base'] ~ "' - choose one of " ~ (bases.keys() | list | sort)) %}
{% endif %}
{% if t['hue'] not in hues %}
  {% do sigma_report.fail('theme', "unknown hue '" ~ t['hue'] ~ "' - choose one of " ~ (hues.keys() | list | sort)) %}
{% endif %}
{% set b = bases[t['base']] %}
{% set h = hues[t['hue']] %}
{% set tokens = {
  "canvas": b[0], "ink": b[1], "body": b[2], "muted": b[3], "hairline": b[4], "fill": b[5], "series_grey": b[6],
  "primary": h[0], "tint": h[1], "edge": h[2], "series": h[3], "series_mid": h[4],
  "surface": "#ffffff",
  "success": "#008236", "success_fill": "#dcfce7",
  "danger": "#c10007", "danger_fill": "#ffe2e2",
  "warning": "#bb4d00", "warning_fill": "#fef3c6",
} %}
{% do tokens.update(t['colors']) %}
{% do return(sigma_report.deep_merge(t, {"colors": tokens})) %}
{% endmacro %}


{# Resolves a design token to a hex string. Raises on an unknown token (a typo would otherwise silently
   emit `none` into the spec). A value that already looks like a hex color is passed through, so
   components can accept either a token or a literal. #}
{% macro color(token, override={}) %}
{% if token is none %}
  {% do return(none) %}
{% endif %}
{% if token.startswith('#') %}
  {% do return(token) %}
{% endif %}
{% set colors = sigma_report.theme(override)['colors'] %}
{% if token not in colors %}
  {% do sigma_report.fail('color', "unknown color token '" ~ token ~ "' - must be a hex value or one of " ~ (colors.keys() | list | sort)) %}
{% endif %}
{% do return(colors[token]) %}
{% endmacro %}


{# A late-bound color: element macros emit `__color:primary__` instead of a hex, and `report()` swaps
   every such marker for the color in the *final* theme (project var + the report's own `theme=`).
   That is why a report-level theme override recolors elements that were built before `report()` was
   called. The token is validated now, so a typo fails at the line that wrote it. #}
{% macro color_ref(token) %}
{% if token is none %}
  {% do return(none) %}
{% endif %}
{% if token.startswith('#') %}
  {% do return(token) %}
{% endif %}
{% do sigma_report.color(token) %}
{% do return('__color:' ~ token ~ '__') %}
{% endmacro %}


{# Replaces every `__color:<token>__` marker anywhere in `value` with that token's hex in `colors`. #}
{% macro resolve_colors(value, colors) %}
{% if value is mapping %}
  {% set out = {} %}
  {% for k in value.keys() %}
    {% do out.update({k: sigma_report.resolve_colors(value[k], colors)}) %}
  {% endfor %}
  {% do return(out) %}
{% elif value is string %}
  {% if '__color:' in value %}
    {% set resolved = namespace(text=value) %}
    {% for token in colors.keys() %}
      {% set resolved.text = resolved.text.replace('__color:' ~ token ~ '__', colors[token]) %}
    {% endfor %}
    {% do return(resolved.text) %}
  {% endif %}
  {% do return(value) %}
{% elif value is sequence %}
  {% set out = [] %}
  {% for item in value %}
    {% do out.append(sigma_report.resolve_colors(item, colors)) %}
  {% endfor %}
  {% do return(out) %}
{% endif %}
{% do return(value) %}
{% endmacro %}


{# The theme as the `settings` block of a report's `contents`. Only what the theme actually sets is
   emitted (a `none` font or sequential scheme is left off so Sigma's default applies). #}
{% macro theme_settings(override={}) %}
{% set t = sigma_report.theme(override) %}
{% set c = t['colors'] %}
{% set overrides = {
  "colors": {
    "text": c['ink'],
    "highlight": c['primary'],
    "surface": c['surface'],
    "success": c['success'],
    "warning": c['warning'],
    "danger": c['danger'],
  },
  "categoricalScheme": t['categorical'],
  "colorOverrides": [{"name": "backgroundCanvas", "color": c['canvas']}],
  "borderRadius": t['border_radius'],
} %}
{% if t['sequential'] %}
  {% do overrides.update({"sequentialScheme": t['sequential']}) %}
{% endif %}
{% if t['diverging'] %}
  {% do overrides.update({"divergingScheme": t['diverging']}) %}
{% endif %}
{% set fonts = sigma_report.compact({"textFont": t['fonts']['text'], "dataFont": t['fonts']['data']}) %}
{% if fonts %}
  {% do overrides.update({"fonts": fonts}) %}
{% endif %}
{% do return({"theme": {"name": t['name'], "overrides": overrides}}) %}
{% endmacro %}
