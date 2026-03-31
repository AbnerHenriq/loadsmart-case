/*
  dim_shipper
  ───────────
  One row per unique shipper.
*/

WITH shippers AS (

    SELECT DISTINCT shipper_name
    FROM {{ ref('int_shipments') }}
    WHERE shipper_name IS NOT NULL

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['shipper_name']) }} AS SHIPPER_SK,
    shipper_name AS SHIPPER_NAME

FROM shippers
