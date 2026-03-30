/*
  int_shipments
  ─────────────
  Enriquecimento da staging com métricas derivadas de negócio.
  Deduplicação de loadsmart_id foi movida para a staging (via QUALIFY).

  Key decisions:
  - computed_pnl substitui o campo pnl raw, inconsistente em 24 linhas
    (ver docs/analysis/raw-data-findings.md — achado #5).
  - Cargas canceladas são mantidas. A fact table expõe a flag LOAD_WAS_CANCELLED
    para que consumidores filtrem conforme necessário.
*/

select
    LOADSMART_ID,
    LANE_RAW,
    PICKUP_CITY,
    PICKUP_STATE,
    DELIVERY_CITY,
    DELIVERY_STATE,

    -- timestamps
    QUOTE_AT,
    BOOKED_AT,
    SOURCED_AT,
    PICKUP_AT,
    DELIVERED_AT,
    PICKUP_APPOINTMENT_AT,
    DELIVERY_APPOINTMENT_AT,

    -- financials (COMPUTED_PNL corrige as 24 linhas inconsistentes do raw)
    BOOK_PRICE,
    SOURCE_PRICE,
    round(BOOK_PRICE - SOURCE_PRICE, 2)  as COMPUTED_PNL,
    MILEAGE,

    -- métricas de tempo derivadas
    round(
        date_diff('hour', PICKUP_AT, DELIVERED_AT) / 24.0, 2
    )                                    as LEAD_TIME_DAYS,

    round(
        date_diff('hour', BOOKED_AT, PICKUP_AT) / 24.0, 2
    )                                    as BOOKING_TO_PICKUP_DAYS,

    -- flags financeiras derivadas
    (BOOK_PRICE - SOURCE_PRICE) > 0      as IS_PROFITABLE,
    MILEAGE > 0                          as IS_MILEAGE_VALID,

    -- pontualidade de entrega
    -- 467 linhas têm DELIVERED_AT < PICKUP_AT (problema de qualidade — achado #9)
    case
        when DELIVERED_AT is null or DELIVERY_APPOINTMENT_AT is null then null
        when DELIVERED_AT <= DELIVERY_APPOINTMENT_AT then true
        else false
    end                                  as DELIVERED_ON_TIME,

    -- qualquer método de tracking disponível
    (
        HAS_MOBILE_APP_TRACKING
        or HAS_MACROPOINT_TRACKING
        or HAS_EDI_TRACKING
    )                                    as HAS_ANY_TRACKING,

    -- colunas pass-through
    EQUIPMENT_TYPE,
    SOURCING_CHANNEL,
    CARRIER_RATING,
    CARRIER_NAME,
    SHIPPER_NAME,
    CARRIER_ON_TIME_TO_PICKUP,
    CARRIER_ON_TIME_TO_DELIVERY,
    CARRIER_ON_TIME_OVERALL,
    HAS_MOBILE_APP_TRACKING,
    HAS_MACROPOINT_TRACKING,
    HAS_EDI_TRACKING,
    VIP_CARRIER,
    CARRIER_DROPPED_US_COUNT,
    CONTRACTED_LOAD,
    LOAD_BOOKED_AUTONOMOUSLY,
    LOAD_SOURCED_AUTONOMOUSLY,
    LOAD_WAS_CANCELLED

from {{ ref('stg_shipments') }}
