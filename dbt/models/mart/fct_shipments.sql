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

select
    -- natural key
    loadsmart_id                as LOADSMART_ID,

    -- foreign keys
    carrier_sk                  as CARRIER_SK,
    shipper_sk                  as SHIPPER_SK,
    pickup_location_sk          as PICKUP_LOCATION_SK,
    delivery_location_sk        as DELIVERY_LOCATION_SK,
    pickup_date_sk              as PICKUP_DATE_SK,
    delivery_date_sk            as DELIVERY_DATE_SK,
    booked_date_sk              as BOOKED_DATE_SK,

    -- measures
    book_price                  as BOOK_PRICE,
    source_price                as SOURCE_PRICE,
    pnl                         as PNL,
    mileage                     as MILEAGE,
    lead_time_days              as LEAD_TIME_DAYS,
    booking_to_pickup_days      as BOOKING_TO_PICKUP_DAYS,
    book_price_per_mile         as BOOK_PRICE_PER_MILE,

    -- shipment attributes
    equipment_type              as EQUIPMENT_TYPE,
    sourcing_channel            as SOURCING_CHANNEL,

    -- performance flags
    is_profitable               as IS_PROFITABLE,
    is_mileage_valid            as IS_MILEAGE_VALID,
    delivered_on_time           as DELIVERED_ON_TIME,
    has_any_tracking            as HAS_ANY_TRACKING,
    carrier_on_time_to_pickup   as CARRIER_ON_TIME_TO_PICKUP,
    carrier_on_time_to_delivery as CARRIER_ON_TIME_TO_DELIVERY,
    carrier_on_time_overall     as CARRIER_ON_TIME_OVERALL,

    -- tracking detail
    has_mobile_app_tracking     as HAS_MOBILE_APP_TRACKING,
    has_macropoint_tracking     as HAS_MACROPOINT_TRACKING,
    has_edi_tracking            as HAS_EDI_TRACKING,

    -- load metadata
    contracted_load             as CONTRACTED_LOAD,
    load_booked_autonomously    as LOAD_BOOKED_AUTONOMOUSLY,
    load_sourced_autonomously   as LOAD_SOURCED_AUTONOMOUSLY,
    load_was_cancelled          as LOAD_WAS_CANCELLED,
    vip_carrier                 as VIP_CARRIER,
    carrier_dropped_us_count    as CARRIER_DROPPED_US_COUNT,

    -- timestamps
    quote_at                    as QUOTE_AT,
    booked_at                   as BOOKED_AT,
    sourced_at                  as SOURCED_AT,
    pickup_at                   as PICKUP_AT,
    delivered_at                as DELIVERED_AT,
    pickup_appointment_at       as PICKUP_APPOINTMENT_AT,
    delivery_appointment_at     as DELIVERY_APPOINTMENT_AT,

    -- lane / geo
    lane_raw                    as LANE_RAW,
    pickup_city                 as PICKUP_CITY,
    pickup_state                as PICKUP_STATE,
    delivery_city               as DELIVERY_CITY,
    delivery_state              as DELIVERY_STATE

from joined
