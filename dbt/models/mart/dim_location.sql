/*
  dim_location
  ─────────────
  One row per unique city+state combination.
  Reused by fct_shipments twice: as pickup_location_sk and delivery_location_sk.
*/

with pickup_locations as (

    select distinct pickup_city as city, pickup_state as state
    from {{ ref('int_shipments') }}
    where pickup_city is not null and pickup_state is not null

),

delivery_locations as (

    select distinct delivery_city as city, delivery_state as state
    from {{ ref('int_shipments') }}
    where delivery_city is not null and delivery_state is not null

),

all_locations as (

    select city, state from pickup_locations
    union
    select city, state from delivery_locations

)

select
    {{ dbt_utils.generate_surrogate_key(['city', 'state']) }} as LOCATION_SK,
    city                                                       as CITY,
    state                                                      as STATE

from all_locations
