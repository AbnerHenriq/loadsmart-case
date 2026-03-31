SELECT
    loadsmart_id,
    lane_raw,
    pickup_city,
    pickup_state,
    delivery_city,
    delivery_state,

    -- timestamps
    quote_at,
    booked_at,
    sourced_at,
    pickup_at,
    delivered_at,
    pickup_appointment_at,
    delivery_appointment_at,

    -- financials (computed_pnl fixes the 24 inconsistent raw rows)
    book_price,
    source_price,
    ROUND(book_price - source_price, 2) AS computed_pnl,
    mileage,

    -- derived time metrics
    ROUND(
        DATE_DIFF('hour', pickup_at, delivered_at) / 24.0,
        2
    ) AS lead_time_days,

    ROUND(
        DATE_DIFF('hour', booked_at, pickup_at) / 24.0,
        2
    ) AS booking_to_pickup_days,

    -- derived financial flags
    (book_price - source_price) > 0 AS is_profitable,
    mileage > 0 AS is_mileage_valid,

    -- delivery punctuality
    -- 467 rows have delivered_at < pickup_at (data quality issue — finding #9)
    CASE
        WHEN delivered_at IS NULL OR delivery_appointment_at IS NULL THEN NULL
        WHEN delivered_at <= delivery_appointment_at THEN TRUE
        ELSE FALSE
    END AS delivered_on_time,

    -- any tracking method available
    (
        has_mobile_app_tracking
        OR has_macropoint_tracking
        OR has_edi_tracking
    ) AS has_any_tracking,

    -- pass-through columns
    equipment_type,
    sourcing_channel,
    carrier_rating,
    carrier_name,
    shipper_name,
    carrier_on_time_to_pickup,
    carrier_on_time_to_delivery,
    carrier_on_time_overall,
    has_mobile_app_tracking,
    has_macropoint_tracking,
    has_edi_tracking,
    vip_carrier,
    carrier_dropped_us_count,
    contracted_load,
    load_booked_autonomously,
    load_sourced_autonomously,
    load_was_cancelled

FROM {{ ref('stg_shipments') }}
