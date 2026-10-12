{# A report fed by a table in a Sigma data model rather than straight from the warehouse. The data model
   itself is `sigma_sales_model`, composed with the companion `sigma_data_models` package; this
   report finds its Sigma id through the `sigma_data_model_ids` project var. #}
{% set spec = sigma_report.simple_dashboard(
    name='Sales from a data model',
    source=sigma_report.from_data_model('sigma_sales_model', 'orders', identifier='stg_orders'),
    kpis=[{'value': 'Sum([Amount])', 'name': 'Revenue'}],
    charts=[{'type': 'bar', 'x': 'region', 'y': 'Sum([Amount])', 'name': 'Revenue by region'}],
) %}

{{ sigma_report.materialize(spec) }}

select 1 as report
