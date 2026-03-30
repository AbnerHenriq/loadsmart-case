/*
  stg_shipments
  ─────────────
  Limpeza, tipagem e parse da camada raw.
  - Coluna duplicada has_mobile_app_tracking_2 confirmada idêntica à original
    (0 divergências) — dropada aqui, mantida no raw para auditoria.
  - Deduplicação de loadsmart_id via QUALIFY: 4 pares de linhas idênticas
    encontrados no raw (ver docs/raw_data_findings.md — achado #2).
  - Datas parseadas via macro parse_ts.
  - Nomes de coluna em UPPERCASE.
*/

select
    -- identifiers
    loadsmart_id                                                        as LOADSMART_ID,

    -- lane parsing: "City,ST -> City,ST"
    lane                                                                as LANE_RAW,
    trim(split_part(split_part(lane, ' -> ', 1), ',', 1))              as PICKUP_CITY,
    trim(split_part(split_part(lane, ' -> ', 1), ',', 2))              as PICKUP_STATE,
    trim(split_part(split_part(lane, ' -> ', 2), ',', 1))              as DELIVERY_CITY,
    trim(split_part(split_part(lane, ' -> ', 2), ',', 2))              as DELIVERY_STATE,

    -- dates (macro parse_ts: strptime(col, '%m/%d/%Y %H:%M')::timestamp)
    {{ parse_ts('quote_date') }}                                        as QUOTE_AT,
    {{ parse_ts('book_date') }}                                         as BOOKED_AT,
    {{ parse_ts('source_date') }}                                       as SOURCED_AT,
    {{ parse_ts('pickup_date') }}                                       as PICKUP_AT,
    {{ parse_ts('delivery_date') }}                                     as DELIVERED_AT,
    {{ parse_ts('pickup_appointment_time') }}                           as PICKUP_APPOINTMENT_AT,
    {{ parse_ts('delivery_appointment_time') }}                         as DELIVERY_APPOINTMENT_AT,

    -- financials (already DOUBLE from ingest)
    book_price                                                          as BOOK_PRICE,
    source_price                                                        as SOURCE_PRICE,
    pnl                                                                 as PNL,
    mileage                                                             as MILEAGE,

    -- shipment attributes
    nullif(trim(equipment_type), '')                                    as EQUIPMENT_TYPE,
    nullif(trim(sourcing_channel), '')                                  as SOURCING_CHANNEL,
    carrier_rating                                                      as CARRIER_RATING,

    -- parties
    nullif(trim(carrier_name), '')                                      as CARRIER_NAME,
    nullif(trim(shipper_name), '')                                      as SHIPPER_NAME,

    -- carrier performance flags (already BOOLEAN from ingest)
    carrier_on_time_to_pickup                                           as CARRIER_ON_TIME_TO_PICKUP,
    carrier_on_time_to_delivery                                         as CARRIER_ON_TIME_TO_DELIVERY,
    carrier_on_time_overall                                             as CARRIER_ON_TIME_OVERALL,

    -- tracking flags
    -- has_mobile_app_tracking_2 confirmada idêntica (0 divergências) — dropada
    has_mobile_app_tracking                                             as HAS_MOBILE_APP_TRACKING,
    has_macropoint_tracking                                             as HAS_MACROPOINT_TRACKING,
    has_edi_tracking                                                    as HAS_EDI_TRACKING,

    -- load metadata flags (already BOOLEAN from ingest)
    vip_carrier                                                         as VIP_CARRIER,
    carrier_dropped_us_count                                            as CARRIER_DROPPED_US_COUNT,
    contracted_load                                                     as CONTRACTED_LOAD,
    load_booked_autonomously                                            as LOAD_BOOKED_AUTONOMOUSLY,
    load_sourced_autonomously                                           as LOAD_SOURCED_AUTONOMOUSLY,
    load_was_cancelled                                                  as LOAD_WAS_CANCELLED

from {{ source('raw', 'shipments') }}

qualify row_number() over (
    partition by loadsmart_id
    order by {{ parse_ts('book_date') }}
) = 1
