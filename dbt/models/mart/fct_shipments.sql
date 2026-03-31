WITH shipments AS (

    SELECT * FROM {{ ref('int_shipments') }}

),

dim_carrier AS (

    SELECT
        carrier_sk AS carrier_sk,
        carrier_name AS carrier_name
    FROM {{ ref('dim_carrier') }}

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
    loadsmart_id                AS loadsmart_id,

    -- foreign keys
    carrier_sk                  AS carrier_sk,
    shipper_sk                  AS shipper_sk,
    pickup_location_sk          AS pickup_location_sk,
    delivery_location_sk        AS delivery_location_sk,
    pickup_date_sk              AS pickup_date_sk,
    delivery_date_sk            AS delivery_date_sk,
    booked_date_sk              AS booked_date_sk,

    -- measures
    book_price                  AS book_price,
    source_price                AS source_price,
    pnl                         AS pnl,
    mileage                     AS mileage,
    lead_time_days              AS lead_time_days,
    booking_to_pickup_days      AS booking_to_pickup_days,
    book_price_per_mile         AS book_price_per_mile,

    -- shipment attributes
    equipment_type              AS equipment_type,
    sourcing_channel            AS sourcing_channel,

    -- performance flags
    is_profitable               AS is_profitable,
    is_mileage_valid            AS is_mileage_valid,
    delivered_on_time           AS delivered_on_time,
    has_any_tracking            AS has_any_tracking,
    carrier_on_time_to_pickup   AS carrier_on_time_to_pickup,
    carrier_on_time_to_delivery AS carrier_on_time_to_delivery,
    carrier_on_time_overall     AS carrier_on_time_overall,

    -- tracking detail
    has_mobile_app_tracking     AS has_mobile_app_tracking,
    has_macropoint_tracking     AS has_macropoint_tracking,
    has_edi_tracking            AS has_edi_tracking,

    -- load metadata
    contracted_load             AS contracted_load,
    load_booked_autonomously    AS load_booked_autonomously,
    load_sourced_autonomously   AS load_sourced_autonomously,
    load_was_cancelled          AS load_was_cancelled,
    vip_carrier                 AS vip_carrier,
    carrier_dropped_us_count    AS carrier_dropped_us_count,

    -- timestamps
    quote_at                    AS quote_at,
    booked_at                   AS booked_at,
    sourced_at                  AS sourced_at,
    pickup_at                   AS pickup_at,
    delivered_at                AS delivered_at,
    pickup_appointment_at       AS pickup_appointment_at,
    delivery_appointment_at     AS delivery_appointment_at,

    -- lane / geo
    lane_raw                    AS lane_raw,
    pickup_city                 AS pickup_city,
    pickup_state                AS pickup_state,
    delivery_city               AS delivery_city,
    delivery_state              AS delivery_state

FROM joined
