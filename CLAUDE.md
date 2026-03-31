# CLAUDE.md — Loadsmart Analytics Case

Persistent context for AI sessions in this project.

---

## Project

Analytics pipeline for Loadsmart shipment data.
Stack: **DuckDB + dbt-core + Apache Airflow + Apache Superset**, all via Docker Compose.

Flow: `CSV → raw.shipments (ingest.py) → stg_ → int_ → mart.* → Superset dashboards`

Bring up the environment: `make setup` (Docker required).
Full reset from scratch: `make reset`.

---

## SQL conventions

### SQL keywords in UPPERCASE

All reserved SQL words must be written in UPPERCASE in dbt files:
`SELECT`, `FROM`, `AS`, `WHERE`, `WITH`, `JOIN`, `ON`, `CASE`, `WHEN`, `THEN`, `ELSE`, `END`,
`QUALIFY`, `PARTITION BY`, `ORDER BY`, `GROUP BY`, `COALESCE`, `NULLIF`, `TRIM`, `ROUND`, etc.

### Columns: lowercase in stg/int, UPPERCASE only in the final `SELECT` of the mart

- **`staging/` and `intermediate/`:** column identifiers in **lowercase snake_case**
  (`loadsmart_id`, `booked_at`, `carrier_name`). Easier to read and matches `schema.yml`.

- **`mart/` (facts and dims):** in the model’s **final `SELECT`**, every column exposed to
  consumers (Superset) must use an **`UPPERCASE`** alias (`AS CARRIER_NAME`,
  `AS LOADSMART_ID`). The Superset API returns names exactly as in DuckDB — the bootstrap
  uses them for `groupby`, filters, and metrics; case mismatch breaks charts.

Inner CTEs inside a `mart/` file keep intermediate columns in lowercase; only the final
layer applies `AS ...` in uppercase.

```sql
-- Inner CTE (lowercase)
SELECT carrier_name, book_price FROM ...

-- Final mart SELECT (UPPERCASE)
SELECT
    carrier_name AS CARRIER_NAME,
    book_price   AS BOOK_PRICE
FROM ...
```

### Descriptive table aliases

Avoid opaque one-letter aliases (`s`, `ds`) in `JOIN`. Prefer names that show role
(`shipment`, `carrier_dim`, `shipper_dim`). Details: `.claude/commands/001-sql-best-practices.md`.

### Timestamps via `parse_ts` macro

Never use `strptime()` directly. Use the macro in `dbt/macros/parse_ts.sql`:

```sql
{{ parse_ts('book_date') }}   -- not: strptime(book_date, '%m/%d/%Y %H:%M')
```

### Refs and sources — no hardcoded schema

```sql
FROM {{ source('raw', 'shipments') }}   -- not: FROM raw.shipments
FROM {{ ref('fct_shipments') }}         -- not: FROM mart.fct_shipments
```

### Other mandatory rules

- **CTEs** instead of inline subqueries
- **QUALIFY** for deduplication (`ROW_NUMBER() OVER (PARTITION BY ...)`)
- **`NULLIF(TRIM(col), '')`** for string columns from external sources
- **`COALESCE(fk, 'unknown-...')`** for dimension FKs that may be NULL
- **`CASE WHEN denominator > 0 THEN ... ELSE NULL END`** before any division
- **`SELECT *` forbidden** in `mart/` models (list columns explicitly)

---

## dbt layer boundaries

| Layer | DuckDB schema | Materialization | Responsibility |
|--------|--------------|-----------------|----------------|
| `staging/` | `staging` | view | Parse, cleanup, typing, dedup |
| `intermediate/` | `intermediate` | table | Derived metrics, enrichment |
| `mart/` | `mart` | table | Facts/dims exposed to Superset |

Business logic **never** in staging. Joins to final dimensions **never** in intermediate.

---

## Document naming

| Prefix | Type | Location |
|--------|------|----------|
| `rbk0XX` | Runbook (reference guide) | `docs/runbooks/` |
| `0XX` | Invocable Claude command | `.claude/commands/` |
| `cur0XX` | Cursor rule | `.cursor/rules/` |

Exploratory analyses live in `docs/analysis/` (no numeric prefix).

---

## Available Claude commands

| Command | What it does |
|---------|----------------|
| `/001-sql-best-practices` | Reviews SQL against project rules (`001-sql-best-practices.md`) |
| `/002-pr-review` | Full PR review: SQL + layers + tests + data impact |
| `/003-create-dashboard` | Runs runbook `rbk005` to create a Superset dashboard |

`/002-pr-review` calls `/001-sql-best-practices` automatically for every changed `.sql` file.

---

## Data — important notes

- **5,357 shipments** after deduplication (4 pairs of identical rows removed in staging)
- **`carrier_sk = 'unknown-carrier'`** is the sentinel for loads without a carrier (499 cases, mostly cancelled)
- **PnL** is always recomputed as `book_price - source_price` — the raw `pnl` field has 24 inconsistencies
- **`IS_MILEAGE_VALID`** filters the 45 loads with `mileage = 0` for cost-per-mile analysis
- **`DELIVERED_ON_TIME`** includes 467 cases where `delivered_at < pickup_at` — flag exposed, not filtered
- 9 data-quality findings documented in `docs/analysis/raw-data-findings.md`

---

## Superset

- UI: `http://localhost:8088` (admin / admin)
- Airflow: `http://localhost:9090` (admin / admin)
- Main dataset: `fct_shipments` (id=1)
- Idempotent bootstrap: `scripts/superset_bootstrap.py` (safe to re-run)
- Critical pitfall: use `echarts_timeseries_bar` (not `bar`); `groupby` columns must be UPPERCASE

Reference runbooks: `docs/runbooks/rbk001` through `rbk005`.
