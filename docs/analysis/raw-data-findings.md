# Raw Data Findings — `raw.shipments`

Analysis of `2026_data_challenge_ae_data.csv` (5,361 rows).
All figures below were taken directly from the `raw` layer before any transformation.

---

## 1. Duplicate column in CSV

**Field:** `has_mobile_app_tracking`

The CSV contains this column **twice** with the exact same name. Pandas auto-renames the second occurrence to `has_mobile_app_tracking.1`. The duplicate column was dropped in the ingest script (`scripts/ingest.py`) before loading into DuckDB, keeping only the first occurrence.

**Resolution:** Both columns are kept at ingest (`scripts/ingest.py`): the second occurrence is renamed to `has_mobile_app_tracking_2`. In staging (`stg_shipments.sql`) both columns were confirmed **identical** (0 divergences), so `has_mobile_app_tracking_2` is dropped there — the original column remains exposed in the mart. Raw keeps both for future audit.

---

## 2. Duplicate `loadsmart_id` values

**Impact:** 4 duplicate IDs → 8 rows total (4 pairs of exactly identical rows)


| loadsmart_id | lane                           | load_was_cancelled |
| ------------ | ------------------------------ | ------------------ |
| 206432441    | Trenton,MO -> Reno,NV          | False              |
| 206437697    | Plant City,FL -> McCook,IL     | True               |
| 206533729    | Compton,CA -> Plant City,FL    | False              |
| 206586825    | Sapulpa,OK -> Warner Robins,GA | False              |


All pairs are **identical rows** — not updates or different versions of the same shipment. They look like accidental duplicate ingestion at the source.

**To do:** Add a uniqueness constraint at the source. And qualify in staging to remove the duplicates.

---

## 3. Null `carrier_name`

**Impact:** 499 rows (9.31% of total)

Most records without carrier_name are cancelled loads (`load_was_cancelled = TRUE`). That is coherent: if the load was cancelled before a carrier was assigned, there is no name to record.


| Situation                             | Rows          |
| ------------------------------------ | --------------- |
| Total nulls                          | 499             |
| Cancelled with null carrier_name     | ~480 (estimated) |
| Not cancelled with null carrier_name | ~19             |


**To do:** Check if this logic is right and if it makes sense to have a `dim_carrier` dimension with a default `"Unknown"` member to preserve referential integrity in the mart.

---

## 4. `book_price` and `source_price` equal to zero

**Impact:**

- `book_price = 0`: 530 rows
- `source_price = 0`: 519 rows

**Breakdown by cancellation status:**


| load_was_cancelled | Rows | Rows with book_price = 0 |
| ------------------ | ------ | ------------------------- |
| True               | 517    | 514                       |
| False              | 4,844  | 16                        |


The majority of zeros are on cancelled loads. For cancelled loads, zero prices are semantically valid (no service executed). The **16 non-cancelled rows with book_price = 0** are potentially problematic.

**To do:** Investigate the 16 active loads with zero price — may be tests, courtesy loads, or registration errors. Consider excluding them from financial analyses.

---

## 5. `pnl` inconsistent with `book_price - source_price`

**Impact:** 24 rows where `pnl ≠ book_price - source_price` (difference > $0.01)

In all **24** cases, **`source_price = 0` but `book_price > 0`**, and the recorded `pnl` is `0` instead of the expected value (`book_price`). Example:


| loadsmart_id | book_price | source_price | pnl recorded | pnl expected |
| ------------ | ---------- | ------------ | -------------- | ------------ |
| 206554409    | 7,232.42   | 0.00         | 0.00           | 7,232.42     |
| 206577609    | 479.27     | 0.00         | 0.00           | 479.27       |


**Suggestion:** Do not use the raw `pnl` field directly in analytics. The mart recomputes PnL as `book_price - source_price` for consistency.

---

## 6. `mileage` equal to zero

**Impact:** 47 rows with `mileage = 0`


| Status             | Rows |
| ------------------ | ------ |
| Cancelled         | 2      |
| **Not cancelled** | **45** |


The 45 non-cancelled loads with zero mileage are suspicious. Verified examples have long real lanes (e.g. `Maxton,NC -> Portland,OR`, `Lakewood,NY -> Portland,OR`) — routes that clearly should have mileage > 0.

**Suggestion:** This is likely an integration error with the distance engine. Exclude those 45 rows from cost-per-mile analysis. Check problems with product / engineering team. 

---

## 7. `carrier_rating` with no value

**Impact:** 4,614 of 5,361 rows with no value (86.1% null)


| Metric          | Value       |
| ---------------- | ----------- |
| Total rows  | 5,361       |
| With rating       | 747 (13.9%) |
| Value range | 0.0 – 5.0   |


Only 13.9% of loads have a rating. That makes the column unusable for population-level analysis without explicit segmentation.

**Todo:** Understand better the business logic behind the carrier rating and how it is used.

---

## 8. `sourcing_channel` very sparse

**Impact:** 5,117 of 5,361 rows with no value (95.5% null)


| sourcing_channel     | Rows |
| -------------------- | ------ |
| NULL                 | 5,117  |
| carrier_capacity     | 96     |
| dat_in               | 80     |
| dat_out              | 30     |
| source_list          | 28     |
| ts_in                | 6      |
| ts_out               | 2      |
| external_source_list | 1      |
| livejobs             | 1      |


**Suggestion:** Check whether null `sourcing_channel` means a specific channel or a logging failure. Consider mapping NULL to `"direct"` or `"unknown"` so sourcing analyses are not distorted.

---

## 9. `delivered_at` before `pickup_at`

**Impact:** 467 rows where `delivery_date < pickup_date`

This is logically impossible for a delivered load. Possible causes:

- Delivery timestamps represent **scheduled** (appointment), not actual
- Timezone error in conversion
- Test data

**Suggestion:** Clarify whether `delivery_date` is actual delivery or only appointment. If actual, the 467 rows need investigation. The mart does not filter these rows but exposes a flag for analysis.

---

## Executive summary


| #   | Finding                                              | Rows affected | Severity    |
| --- | --------------------------------------------------- | --------------- | ------------- |
| 1   | Duplicate column (`has_mobile_app_tracking`)        | all           | High          |
| 2   | Duplicate `loadsmart_id` (identical rows)         | 8               | Medium         |
| 3   | Null `carrier_name`                                 | 499 (9.3%)      | Medium         |
| 4   | `book_price` / `source_price` = 0                   | ~530 / ~519     | Medium         |
| 5   | `pnl` inconsistent with `book_price - source_price` | 24              | High          |
| 6   | `mileage` = 0 on active loads                      | 45              | Medium         |
| 7   | `carrier_rating` sparse                            | 4,614 (86%)     | Informational |
| 8   | `sourcing_channel` sparse                          | 5,117 (95%)     | Informational |
| 9   | `delivered_at` < `pickup_at`                        | 467 (8.7%)      | High          |

