/*
  dim_date
  ────────
  Date spine via dbt_utils.date_spine covering the full dataset range.
  Grain: one row per day.

  Note: dbt_utils.date_spine does not accept a CTE as a parameter (emits static SQL),
  so boundary subqueries are injected directly into the arguments.
*/

WITH spine AS (

    {{ dbt_utils.date_spine(
        datepart   = 'day',
        start_date = "(SELECT MIN(LEAST(pickup_at::DATE, delivered_at::DATE, booked_at::DATE)) FROM " ~ ref('int_shipments') ~ ")",
        end_date   = "(SELECT MAX(GREATEST(pickup_at::DATE, delivered_at::DATE, booked_at::DATE)) + INTERVAL '1 day' FROM " ~ ref('int_shipments') ~ ")"
    ) }}

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['date_day']) }} AS DATE_SK,
    date_day AS DATE_DAY,
    EXTRACT(YEAR FROM date_day)::INT AS YEAR,
    EXTRACT(QUARTER FROM date_day)::INT AS QUARTER,
    EXTRACT(MONTH FROM date_day)::INT AS MONTH,
    STRFTIME(date_day, '%B') AS MONTH_NAME,
    EXTRACT(WEEK FROM date_day)::INT AS WEEK_OF_YEAR,
    EXTRACT(DAY FROM date_day)::INT AS DAY_OF_MONTH,
    EXTRACT(DOW FROM date_day)::INT AS DAY_OF_WEEK,
    STRFTIME(date_day, '%A') AS DAY_NAME,
    date_day = CURRENT_DATE AS IS_TODAY,
    EXTRACT(DOW FROM date_day) IN (0, 6) AS IS_WEEKEND

FROM spine
