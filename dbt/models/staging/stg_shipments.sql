SELECT
    -- identifiers
    loadsmart_id,

    -- lane parsing: "City,ST -> City,ST"
    lane AS lane_raw,
    TRIM(SPLIT_PART(SPLIT_PART(lane, ' -> ', 1), ',', 1)) AS pickup_city,
    TRIM(SPLIT_PART(SPLIT_PART(lane, ' -> ', 1), ',', 2)) AS pickup_state,
    TRIM(SPLIT_PART(SPLIT_PART(lane, ' -> ', 2), ',', 1)) AS delivery_city,
    TRIM(SPLIT_PART(SPLIT_PART(lane, ' -> ', 2), ',', 2)) AS delivery_state,

    -- dates
    {{ parse_ts('quote_date') }} AS quote_at,
    {{ parse_ts('book_date') }} AS booked_at,
    {{ parse_ts('source_date') }} AS sourced_at,
    {{ parse_ts('pickup_date') }} AS pickup_at,
    {{ parse_ts('delivery_date') }} AS delivered_at,
    {{ parse_ts('pickup_appointment_time') }} AS pickup_appointment_at,
    {{ parse_ts('delivery_appointment_time') }} AS delivery_appointment_at,

    -- financials
    book_price,
    source_price,
    pnl,
    mileage,

    -- shipment attributes
    NULLIF(TRIM(equipment_type), '') AS equipment_type,
    NULLIF(TRIM(sourcing_channel), '') AS sourcing_channel,
    carrier_rating,

    -- parties
    NULLIF(TRIM(carrier_name), '') AS carrier_name,
    NULLIF(TRIM(shipper_name), '') AS shipper_name,

    -- carrier performance flags (already BOOLEAN from ingest)
    carrier_on_time_to_pickup,
    carrier_on_time_to_delivery,
    carrier_on_time_overall,

    -- tracking flags
    -- has_mobile_app_tracking_2 confirmed identical (0 divergences) — dropped
    has_mobile_app_tracking,
    has_macropoint_tracking,
    has_edi_tracking,

    -- load metadata flags (already BOOLEAN from ingest)
    vip_carrier,
    carrier_dropped_us_count,
    contracted_load,
    load_booked_autonomously,
    load_sourced_autonomously,
    load_was_cancelled

FROM {{ source('raw', 'shipments') }}

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY loadsmart_id
    ORDER BY {{ parse_ts('book_date') }}
) = 1
