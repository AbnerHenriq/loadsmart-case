WITH shipments AS (

    SELECT * FROM {{ ref('int_shipments') }}

),

dim_carrier AS (

    SELECT carrier_sk, carrier_name FROM {{ ref('dim_carrier') }}

),

dim_shipper AS (

    SELECT shipper_sk, shipper_name FROM {{ ref('dim_shipper') }}

),

dim_location AS (

    SELECT location_sk, city, state FROM {{ ref('dim_location') }}

),

dim_date AS (

    SELECT date_sk, date_day FROM {{ ref('dim_date') }}

),

joined AS (

    SELECT
        -- natural key
        shipment.loadsmart_id,

        -- foreign keys
        COALESCE(carrier_dim.carrier_sk, 'unknown-carrier') AS carrier_sk,
        shipper_dim.shipper_sk,
        dl_pickup.location_sk AS pickup_location_sk,
        dl_delivery.location_sk AS delivery_location_sk,
        dd_pickup.date_sk AS pickup_date_sk,
        dd_delivery.date_sk AS delivery_date_sk,
        dd_booked.date_sk AS booked_date_sk,

        -- measures
        shipment.book_price,
        shipment.source_price,
        shipment.computed_pnl AS pnl,
        shipment.mileage,
        shipment.lead_time_days,
        shipment.booking_to_pickup_days,

        -- round-trip cost per mile (guarded against mileage = 0)
        CASE
            WHEN shipment.mileage > 0 THEN ROUND(shipment.book_price / shipment.mileage, 4)
            ELSE NULL
        END AS book_price_per_mile,

        -- shipment attributes
        shipment.equipment_type,
        shipment.sourcing_channel,

        -- performance flags
        shipment.is_profitable,
        shipment.is_mileage_valid,
        shipment.delivered_on_time,
        shipment.has_any_tracking,
        shipment.carrier_on_time_to_pickup,
        shipment.carrier_on_time_to_delivery,
        shipment.carrier_on_time_overall,

        -- tracking detail
        shipment.has_mobile_app_tracking,
        shipment.has_macropoint_tracking,
        shipment.has_edi_tracking,

        -- load metadata
        shipment.contracted_load,
        shipment.load_booked_autonomously,
        shipment.load_sourced_autonomously,
        shipment.load_was_cancelled,

        -- load metadata (autonomia / drops)
        shipment.vip_carrier,
        shipment.carrier_dropped_us_count,

        -- timestamps (for ad-hoc analysis + lead-time metrics)
        shipment.quote_at,
        shipment.booked_at,
        shipment.sourced_at,
        shipment.pickup_at,
        shipment.delivered_at,
        shipment.pickup_appointment_at,
        shipment.delivery_appointment_at,

        -- lane / geo (for Superset filters and charts)
        shipment.lane_raw,
        shipment.pickup_city,
        shipment.pickup_state,
        shipment.delivery_city,
        shipment.delivery_state

    FROM shipments AS shipment

    LEFT JOIN dim_carrier AS carrier_dim
        ON shipment.carrier_name = carrier_dim.carrier_name

    LEFT JOIN dim_shipper AS shipper_dim
        ON shipment.shipper_name = shipper_dim.shipper_name

    LEFT JOIN dim_location AS dl_pickup
        ON shipment.pickup_city = dl_pickup.city
        AND shipment.pickup_state = dl_pickup.state

    LEFT JOIN dim_location AS dl_delivery
        ON shipment.delivery_city = dl_delivery.city
        AND shipment.delivery_state = dl_delivery.state

    LEFT JOIN dim_date AS dd_pickup
        ON shipment.pickup_at::DATE = dd_pickup.date_day

    LEFT JOIN dim_date AS dd_delivery
        ON shipment.delivered_at::DATE = dd_delivery.date_day

    LEFT JOIN dim_date AS dd_booked
        ON shipment.booked_at::DATE = dd_booked.date_day

)

SELECT
    -- natural key
    loadsmart_id                AS LOADSMART_ID,

    -- foreign keys
    carrier_sk                  AS CARRIER_SK,
    shipper_sk                  AS SHIPPER_SK,
    pickup_location_sk          AS PICKUP_LOCATION_SK,
    delivery_location_sk        AS DELIVERY_LOCATION_SK,
    pickup_date_sk              AS PICKUP_DATE_SK,
    delivery_date_sk            AS DELIVERY_DATE_SK,
    booked_date_sk              AS BOOKED_DATE_SK,

    -- measures
    book_price                  AS BOOK_PRICE,
    source_price                AS SOURCE_PRICE,
    pnl                         AS PNL,
    mileage                     AS MILEAGE,
    lead_time_days              AS LEAD_TIME_DAYS,
    booking_to_pickup_days      AS BOOKING_TO_PICKUP_DAYS,
    book_price_per_mile         AS BOOK_PRICE_PER_MILE,

    -- shipment attributes
    equipment_type              AS EQUIPMENT_TYPE,
    sourcing_channel            AS SOURCING_CHANNEL,

    -- performance flags
    is_profitable               AS IS_PROFITABLE,
    is_mileage_valid            AS IS_MILEAGE_VALID,
    delivered_on_time           AS DELIVERED_ON_TIME,
    has_any_tracking            AS HAS_ANY_TRACKING,
    carrier_on_time_to_pickup   AS CARRIER_ON_TIME_TO_PICKUP,
    carrier_on_time_to_delivery AS CARRIER_ON_TIME_TO_DELIVERY,
    carrier_on_time_overall     AS CARRIER_ON_TIME_OVERALL,

    -- tracking detail
    has_mobile_app_tracking     AS HAS_MOBILE_APP_TRACKING,
    has_macropoint_tracking     AS HAS_MACROPOINT_TRACKING,
    has_edi_tracking            AS HAS_EDI_TRACKING,

    -- load metadata
    contracted_load             AS CONTRACTED_LOAD,
    load_booked_autonomously    AS LOAD_BOOKED_AUTONOMOUSLY,
    load_sourced_autonomously   AS LOAD_SOURCED_AUTONOMOUSLY,
    load_was_cancelled          AS LOAD_WAS_CANCELLED,
    vip_carrier                 AS VIP_CARRIER,
    carrier_dropped_us_count    AS CARRIER_DROPPED_US_COUNT,

    -- timestamps
    quote_at                    AS QUOTE_AT,
    booked_at                   AS BOOKED_AT,
    sourced_at                  AS SOURCED_AT,
    pickup_at                   AS PICKUP_AT,
    delivered_at                AS DELIVERED_AT,
    pickup_appointment_at       AS PICKUP_APPOINTMENT_AT,
    delivery_appointment_at     AS DELIVERY_APPOINTMENT_AT,

    -- lane / geo
    lane_raw                    AS LANE_RAW,
    pickup_city                 AS PICKUP_CITY,
    pickup_state                AS PICKUP_STATE,
    delivery_city               AS DELIVERY_CITY,
    delivery_state              AS DELIVERY_STATE

FROM joined
