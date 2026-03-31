WITH spine AS (

    {{ dbt_utils.date_spine(
        datepart   = 'day',
        start_date = "(SELECT MIN(LEAST(pickup_at::DATE, delivered_at::DATE, booked_at::DATE)) FROM " ~ ref('int_shipments') ~ ")",
        end_date   = "(SELECT MAX(GREATEST(pickup_at::DATE, delivered_at::DATE, booked_at::DATE)) + INTERVAL '1 day' FROM " ~ ref('int_shipments') ~ ")"
    ) }}

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['date_day']) }} AS date_sk,
    date_day AS date_day,
    EXTRACT(YEAR FROM date_day)::INT AS year,
    EXTRACT(QUARTER FROM date_day)::INT AS quarter,
    EXTRACT(MONTH FROM date_day)::INT AS month,
    STRFTIME(date_day, '%B') AS month_name,
    EXTRACT(WEEK FROM date_day)::INT AS week_of_year,
    EXTRACT(DAY FROM date_day)::INT AS day_of_month,
    EXTRACT(DOW FROM date_day)::INT AS day_of_week,
    STRFTIME(date_day, '%A') AS day_name,
    date_day = CURRENT_DATE AS is_today,
    EXTRACT(DOW FROM date_day) IN (0, 6) AS is_weekend

FROM spine
