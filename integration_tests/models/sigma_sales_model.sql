{# The data model the report above reads from, composed with the companion package. #}
{% set sigma_data_model = sigma_data_models.model(
    name='Sales model',
    tables=[
      sigma_data_models.table('orders', 'stg_orders',
        columns=['order_id', 'order_date', 'region', 'segment', 'amount', 'target_amount']),
    ],
) %}

{{ sigma_data_models.materialize(sigma_data_model) }}

select 1 as data_model
