/*
  dim_shipper
  ───────────
  One row per unique shipper.
*/

with shippers as (

    select distinct shipper_name
    from {{ ref('int_shipments') }}
    where shipper_name is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['shipper_name']) }} as SHIPPER_SK,
    shipper_name                                             as SHIPPER_NAME

from shippers
