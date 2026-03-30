/*
  dim_date
  ────────
  Date spine via dbt_utils.date_spine, cobrindo o range completo do dataset.
  Grain: um dia por linha.

  Nota: dbt_utils.date_spine não aceita CTE como parâmetro (gera SQL estático),
  então as subqueries de boundary são injetadas diretamente nos argumentos.
*/

with spine as (

    {{ dbt_utils.date_spine(
        datepart   = 'day',
        start_date = "(select min(least(PICKUP_AT::date, DELIVERED_AT::date, BOOKED_AT::date)) from " ~ ref('int_shipments') ~ ")",
        end_date   = "(select max(greatest(PICKUP_AT::date, DELIVERED_AT::date, BOOKED_AT::date)) + interval '1 day' from " ~ ref('int_shipments') ~ ")"
    ) }}

)

select
    {{ dbt_utils.generate_surrogate_key(['date_day']) }} as DATE_SK,
    date_day                                             as DATE_DAY,
    extract(year    from date_day)::int                  as YEAR,
    extract(quarter from date_day)::int                  as QUARTER,
    extract(month   from date_day)::int                  as MONTH,
    strftime(date_day, '%B')                             as MONTH_NAME,
    extract(week    from date_day)::int                  as WEEK_OF_YEAR,
    extract(day     from date_day)::int                  as DAY_OF_MONTH,
    extract(dow     from date_day)::int                  as DAY_OF_WEEK,
    strftime(date_day, '%A')                             as DAY_NAME,
    date_day = current_date                              as IS_TODAY,
    extract(dow from date_day) in (0, 6)                 as IS_WEEKEND

from spine
