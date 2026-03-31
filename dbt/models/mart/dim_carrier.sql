/*
  dim_carrier
  ───────────
  One row per unique carrier. Includes a default "Unknown" member (carrier_sk = -1)
  to preserve referential integrity for the ~499 shipments where carrier_name is null
  (mostly cancelled loads — see docs/analysis/raw-data-findings.md, finding #3).
*/

with carriers as (

    select distinct
        carrier_name,
        -- use max() to get a non-null rating where available across shipments
        max(carrier_rating)          as carrier_rating,
        max(vip_carrier::int)::bool  as vip_carrier,
        max(carrier_dropped_us_count) as carrier_dropped_us_count

    from {{ ref('int_shipments') }}
    where carrier_name is not null
    group by carrier_name

),

with_sk as (

    select
        {{ dbt_utils.generate_surrogate_key(['carrier_name']) }} as carrier_sk,
        NULLIF(TRIM(carrier_name), '')                           as carrier_name,
        carrier_rating,
        vip_carrier,
        carrier_dropped_us_count

    from carriers

),

-- sentinel row for shipments with no carrier assigned
unknown as (

    select
        'unknown-carrier'  as carrier_sk,
        'Unknown'          as carrier_name,
        null::double       as carrier_rating,
        false              as vip_carrier,
        0                  as carrier_dropped_us_count

),

combined as (

    select * from unknown
    union all
    select * from with_sk

)

select
    carrier_sk               as CARRIER_SK,
    carrier_name             as CARRIER_NAME,
    carrier_rating           as CARRIER_RATING,
    vip_carrier              as VIP_CARRIER,
    carrier_dropped_us_count as CARRIER_DROPPED_US_COUNT

from combined
