{# Data sources: where an element gets its rows. A source is a plain dict in Sigma's own `source` shape
   plus a private `_name` (the prefix Sigma uses in `[NAME/Column]` formulas). Private keys start with
   `_` and are stripped by `sigma_report.report()` before the spec is emitted.

   Five kinds are supported, mirroring how Sigma reports are actually fed:

     warehouse_table   a table in the warehouse, by its physical path
     from_ref          a dbt model / seed / snapshot (calls `ref()`, so the report sits downstream of it)
     from_source       a dbt source (calls `source()`)
     data_model        a table inside a Sigma data model (see `sigma_data_models`)
     element           another element in the same report (a chart built on a table)

   Every element macro accepts any of these as `source=`, or an element dict directly (which is
   shorthand for `sigma_report.element(that_element)`). #}


{# A warehouse table addressed by its physical path. `path` is [database, schema, table]. #}
{% macro warehouse_table(path, connection_id=none) %}
{% set connection_id = connection_id or var('sigma_connection_id', none) %}
{% if not connection_id %}
  {% do sigma_report.fail('warehouse_table', "connection_id is required but was not set. Pass connection_id=, or set the `sigma_connection_id` project var in dbt_project.yml.") %}
{% endif %}
{% if path | length != 3 %}
  {% do sigma_report.fail('warehouse_table', "path must be [database, schema, table], got " ~ path) %}
{% endif %}
{% do return({
  "kind": "warehouse-table",
  "connectionId": connection_id,
  "path": path,
  "_name": path[-1],
}) %}
{% endmacro %}


{# The physical [database, schema, table] a dbt node lives at. This is the one place the package decides
   where your models are built, so it is the one place to override.

   A report is composed at parse time, and at parse time `ref()` / `source()` cannot resolve other
   nodes' relations, so the path is derived from `target` plus whatever the caller passes. If your
   project builds models into custom schemas (a `generate_schema_name` override, `+schema:`), either
   pass `schema=` per call or override this macro once in your own project:

     # dbt_project.yml
     dispatch:
       - macro_namespace: sigma_report
         search_order: ['my_project', 'sigma_report']

     -- macros/sigma_report_overrides.sql  (the name must be exactly `default__relation_path`)
     {% macro default__relation_path(kind, name, database=none, schema=none, identifier=none) %}
       {% do return([database or target.database, schema or 'analytics', identifier or name]) %}
     {% endmacro %}

   `kind` is 'ref' or 'source' (for a source, `name` is 'source_name.table_name'). The other arguments
   are exactly what the caller passed, possibly none. #}
{% macro relation_path(kind, name, database=none, schema=none, identifier=none) %}
{% do return(adapter.dispatch('relation_path', 'sigma_report')(kind, name, database, schema, identifier)) %}
{% endmacro %}


{% macro default__relation_path(kind, name, database=none, schema=none, identifier=none) %}
{% do return([database or target.database, schema or target.schema, identifier or name]) %}
{% endmacro %}


{# A dbt model (or seed / snapshot) as a warehouse table. Calls `ref()` so the report model shows up
   downstream of it in the DAG, in `dbt ls -s +report_model`, and in dbt docs lineage. #}
{% macro from_ref(model_name, database=none, schema=none, identifier=none, connection_id=none) %}
{% do ref(model_name) %}
{% do return(sigma_report.warehouse_table(
  sigma_report.relation_path('ref', model_name, database, schema, identifier),
  connection_id
)) %}
{% endmacro %}


{# A dbt source as a warehouse table. Calls `source()` for lineage. The table's physical schema is the
   source's schema, which `source()` cannot report at parse time, so pass `schema=` (and `database=`)
   when it differs from the target - or override `relation_path` once. #}
{% macro from_source(source_name, table_name, database=none, schema=none, identifier=none, connection_id=none) %}
{% do source(source_name, table_name) %}
{% do return(sigma_report.warehouse_table(
  sigma_report.relation_path('source', source_name ~ '.' ~ table_name, database, schema, identifier or table_name),
  connection_id
)) %}
{% endmacro %}


{# A table inside a Sigma data model.

     data_model_id  the Sigma data model's id; falls back to `var('sigma_data_model_ids')[dbt_model]`
     table_key      the `key` the table was given in `sigma_data_models.table(...)`

   `database` / `schema` / `identifier` must match what was passed to that `sigma_data_models.table()`
   call (same defaults: target database + schema, identifier = table_key) because the table's element
   id is derived from them - the same derivation `sigma_data_models` uses, so the ids agree without
   any coordination between the two packages.

   Columns are referenced as `[Table Name/Column]`, where Table Name is the table's display name in
   the data model: `sigma_data_models` defaults it to the title-cased `key` ('orders' -> 'Orders'). If
   the table was given a custom `display_name=`, pass the same as `table_name=`. #}
{% macro data_model(data_model_id, table_key, identifier=none, database=none, schema=none, table_name=none) %}
{% set database = database or target.database %}
{% set schema = schema or target.schema %}
{% set identifier = identifier or table_key %}
{% set scope = table_key ~ '@' ~ ((database ~ '.' ~ schema ~ '.' ~ identifier) | lower) %}
{% do return({
  "kind": "data-model",
  "dataModelId": data_model_id,
  "elementId": sigma_report.freeze_id('table:' ~ scope, 32),
  "_name": table_name or sigma_report.titleize(table_key),
}) %}
{% endmacro %}


{# `data_model` for a dbt model built with `sigma_data_models.materialize()`: `ref()`s that model for
   lineage, and looks its Sigma data model id up in the `sigma_data_model_ids` project var (a
   {dbt_model_name: sigma_data_model_id} mapping), since the id only exists once the data model has
   been created in Sigma. An id that has not been recorded yet is emitted as an obvious
   `unresolved:<model>` placeholder - the export script refuses to push those. #}
{% macro from_data_model(model_name, table_key, data_model_id=none, identifier=none, database=none, schema=none, table_name=none) %}
{% do ref(model_name) %}
{% set resolved_id = data_model_id or var('sigma_data_model_ids', {}).get(model_name) or ('unresolved:' ~ model_name) %}
{% do return(sigma_report.data_model(resolved_id, table_key, identifier, database, schema, table_name)) %}
{% endmacro %}


{# Another element in the same report as a source - a chart or KPI built on a table that is already on
   the page. Elements are already dicts, so this is mostly a readability aid. #}
{% macro element(el) %}
{% if el is not mapping or 'id' not in el %}
  {% do sigma_report.fail('element', "expected an element built by a sigma_report macro (a dict with an `id`), got " ~ el) %}
{% endif %}
{# `_name` and `_columns` (the parent's live column list) let a child element refer to the parent's
   columns the way Sigma does - see field.sql. #}
{% do return({
  "kind": "table",
  "elementId": el['id'],
  "_name": (el.get('_source') or {}).get('_name'),
  "_columns": el.get('columns', []),
}) %}
{% endmacro %}


{# Normalizes anything a caller might pass as `source=` into a source dict. #}
{% macro resolve_source(source, where) %}
{% if source is not mapping %}
  {% do sigma_report.fail(where, "source must be a sigma_report source or element, got " ~ source) %}
{% endif %}
{% if 'elementId' in source or 'connectionId' in source or 'dataModelId' in source %}
  {% do return(source) %}
{% endif %}
{% if 'id' in source and 'kind' in source %}
  {% do return(sigma_report.element(source)) %}
{% endif %}
{% do sigma_report.fail(where, "source must be a sigma_report source or element, got " ~ source) %}
{% endmacro %}
