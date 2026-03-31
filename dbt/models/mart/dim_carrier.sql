/*
  dim_carrier
  ───────────
  One row per unique carrier. Includes a default "Unknown" member (carrier_sk = -1)
  to preserve referential integrity for the ~499 shipments where carrier_name is null
  (mostly cancelled loads — see docs/analysis/raw-data-findings.md, finding #3).
*/

WITH carriers AS (

    SELECT DISTINCT
        carrier_name,
        -- use MAX() to get a non-null rating where available across shipments
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
    carrier_sk AS CARRIER_SK,
    carrier_name AS CARRIER_NAME,
    carrier_rating AS CARRIER_RATING,
    vip_carrier AS VIP_CARRIER,
    carrier_dropped_us_count AS CARRIER_DROPPED_US_COUNT

FROM combined
