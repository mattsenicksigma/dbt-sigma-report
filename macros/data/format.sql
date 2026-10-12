{# Column display formats, in Sigma's `format` shape (`kind: number | datetime`, d3 format strings).
   Pass the result as `format=` to `sigma_report.field(...)`. #}


{# Any number format. `pattern` is a d3 format string (`,.0f`, `.1%`, `.2s`). #}
{% macro format_number(pattern=',.0f', prefix=none, suffix=none, null_as=none) %}
{% do return(sigma_report.compact({
  "kind": "number",
  "formatString": pattern,
  "prefix": prefix,
  "suffix": suffix,
  "displayNullAs": null_as,
})) %}
{% endmacro %}


{# 1,234,567 #}
{% macro format_integer() %}
{% do return(sigma_report.format_number(',.0f')) %}
{% endmacro %}


{# $1,234 (or $1,234.50 with decimals=2). Pass `symbol` for another currency. #}
{% macro format_currency(decimals=0, symbol='$') %}
{% do return(sigma_report.format_number(',.' ~ decimals ~ 'f', prefix=symbol)) %}
{% endmacro %}


{# 12.3% - the value is a fraction (0.123), as d3's `%` format expects. #}
{% macro format_percent(decimals=1) %}
{% do return(sigma_report.format_number('.' ~ decimals ~ '%')) %}
{% endmacro %}


{# 1.2k / 3.4M: compact SI notation for big KPI numbers. #}
{% macro format_compact(decimals=1) %}
{% do return(sigma_report.format_number('.' ~ decimals ~ 's')) %}
{% endmacro %}


{# A date or timestamp, as a d3 time format string (`%b %d, %Y`). #}
{% macro format_date(pattern='%b %d, %Y') %}
{% do return({"kind": "datetime", "formatString": pattern}) %}
{% endmacro %}
