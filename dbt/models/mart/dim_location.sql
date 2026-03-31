/*
  dim_location
  ─────────────
  One row per unique city+state combination.
  Reused by fct_shipments twice: as pickup_location_sk and delivery_location_sk.
*/

WITH pickup_locations AS (

    SELECT DISTINCT pickup_city AS city, pickup_state AS state
    FROM {{ ref('int_shipments') }}
    WHERE pickup_city IS NOT NULL AND pickup_state IS NOT NULL

),

delivery_locations AS (

    SELECT DISTINCT delivery_city AS city, delivery_state AS state
    FROM {{ ref('int_shipments') }}
    WHERE delivery_city IS NOT NULL AND delivery_state IS NOT NULL

),

all_locations AS (

    SELECT city, state FROM pickup_locations
    UNION
    SELECT city, state FROM delivery_locations

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['city', 'state']) }} AS LOCATION_SK,
    city AS CITY,
    state AS STATE

FROM all_locations
