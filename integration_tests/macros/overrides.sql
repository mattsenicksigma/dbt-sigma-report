{# The documented way to change where reports look for dbt nodes: a `default__relation_path` in the user's
   own project, which `dispatch:` in dbt_project.yml puts ahead of the package's (see
   `sigma_report.relation_path`). Here, dbt sources live in a different database than the models, which
   `dbt parse` cannot know. #}
{% macro default__relation_path(kind, name, database=none, schema=none, identifier=none) %}
{% if kind == 'source' %}
  {% do return([database or 'raw_database', schema or target.schema, identifier or name]) %}
{% endif %}
{% do return([database or target.database, schema or target.schema, identifier or name]) %}
{% endmacro %}
