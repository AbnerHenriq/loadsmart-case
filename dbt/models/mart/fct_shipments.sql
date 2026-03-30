/*
  fct_shipments
  ─────────────
  Grain: one row per unique loadsmart_id (post-deduplication).
  Contains all foreign keys to dimensions and all measures.

  FK resolution:
  - carrier_sk   → dim_carrier  (nulls resolve to 'unknown-carrier' sentinel)
  - shipper_sk   → dim_shipper
  - pickup_location_sk / delivery_location_sk → dim_location
  - pickup_date_sk / delivery_date_sk → dim_date
*/

with shipments as (

    select * from {{ ref('int_shipments') }}

),

dim_carrier as (

    select carrier_sk, carrier_name from {{ ref('dim_carrier') }}

),

dim_shipper as (

    select shipper_sk, shipper_name from {{ ref('dim_shipper') }}

),

dim_location as (

    select location_sk, city, state from {{ ref('dim_location') }}

),

dim_date as (

    select date_sk, date_day from {{ ref('dim_date') }}

),

joined as (

    select
        -- natural key
        s.loadsmart_id,

        -- foreign keys
        coalesce(dc.carrier_sk, 'unknown-carrier')    as carrier_sk,
        ds.shipper_sk,
        dl_pickup.location_sk                         as pickup_location_sk,
        dl_delivery.location_sk                       as delivery_location_sk,
        dd_pickup.date_sk                             as pickup_date_sk,
        dd_delivery.date_sk                           as delivery_date_sk,
        dd_booked.date_sk                             as booked_date_sk,

        -- measures
        s.book_price,
        s.source_price,
        s.computed_pnl                                as pnl,
        s.mileage,
        s.lead_time_days,
        s.booking_to_pickup_days,

        -- round-trip cost per mile (guarded against mileage = 0)
        case
            when s.mileage > 0 then round(s.book_price / s.mileage, 4)
            else null
        end                                           as book_price_per_mile,

        -- shipment attributes
        s.equipment_type,
        s.sourcing_channel,

        -- performance flags
        s.is_profitable,
        s.is_mileage_valid,
        s.delivered_on_time,
        s.has_any_tracking,
        s.carrier_on_time_to_pickup,
        s.carrier_on_time_to_delivery,
        s.carrier_on_time_overall,

        -- tracking detail
        s.has_mobile_app_tracking,
        s.has_macropoint_tracking,
        s.has_edi_tracking,

        -- load metadata
        s.contracted_load,
        s.load_booked_autonomously,
        s.load_sourced_autonomously,
        s.load_was_cancelled,

        -- load metadata (autonomia / drops)
        s.vip_carrier,
        s.carrier_dropped_us_count,

        -- timestamps (for ad-hoc analysis + lead-time metrics)
        s.quote_at,
        s.booked_at,
        s.sourced_at,
        s.pickup_at,
        s.delivered_at,
        s.pickup_appointment_at,
        s.delivery_appointment_at,

        -- lane / geo (para filtros e visualizações no Superset)
        s.lane_raw,
        s.pickup_city,
        s.pickup_state,
        s.delivery_city,
        s.delivery_state

    from shipments s

    left join dim_carrier dc
        on s.carrier_name = dc.carrier_name

    left join dim_shipper ds
        on s.shipper_name = ds.shipper_name

    left join dim_location dl_pickup
        on s.pickup_city = dl_pickup.city
        and s.pickup_state = dl_pickup.state

    left join dim_location dl_delivery
        on s.delivery_city = dl_delivery.city
        and s.delivery_state = dl_delivery.state

    left join dim_date dd_pickup
        on s.pickup_at::date = dd_pickup.date_day

    left join dim_date dd_delivery
        on s.delivered_at::date = dd_delivery.date_day

    left join dim_date dd_booked
        on s.booked_at::date = dd_booked.date_day

)

select * from joined
