WITH carriers AS (

    SELECT DISTINCT
        carrier_name,
        MAX(carrier_rating) AS carrier_rating,
        MAX(vip_carrier::INT)::BOOL AS vip_carrier,
        MAX(carrier_dropped_us_count) AS carrier_dropped_us_count

    FROM {{ ref('int_shipments') }}
    WHERE carrier_name IS NOT NULL
    GROUP BY carrier_name

),

with_sk AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['carrier_name']) }} AS carrier_sk,
        NULLIF(TRIM(carrier_name), '') AS carrier_name,
        carrier_rating,
        vip_carrier,
        carrier_dropped_us_count

    FROM carriers

),

-- sentinel row for shipments with no carrier assigned
unknown AS (

    SELECT
        'unknown-carrier' AS carrier_sk,
        'Unknown' AS carrier_name,
        NULL::DOUBLE AS carrier_rating,
        FALSE AS vip_carrier,
        0 AS carrier_dropped_us_count

),

combined AS (

    SELECT * FROM unknown
    UNION ALL
    SELECT * FROM with_sk

)

SELECT
    carrier_sk AS carrier_sk,
    carrier_name AS carrier_name,
    carrier_rating AS carrier_rating,
    vip_carrier AS vip_carrier,
    carrier_dropped_us_count AS carrier_dropped_us_count

FROM combined
