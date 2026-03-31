# Loadsmart — Analytics Engineer Challenge

## Stack


| Component         | Technology            |
| ----------------- | --------------------- |
| Data warehouse    | DuckDB (local file)   |
| Transformation    | dbt-core + dbt-duckdb |
| Orchestration     | Apache Airflow 2.9    |
| Visualization     | Apache Superset       |
| Analysis / export | Jupyter Notebook      |
| Infrastructure    | Docker Compose        |


---

## Prerequisites

- Docker Desktop (with Docker Compose v2)
- Python 3.11+ (to run dbt locally, optional)
- Git

---

## Project layout

```
loadsmart-case/
├── Makefile                           # make setup / reset / teardown
├── docker-compose.yml                 # Airflow + Superset + DuckDB
├── docker/superset/
│   ├── Dockerfile                     # Image with duckdb-engine installed
│   └── superset_config.py
├── data/
│   └── 2026_data_challenge_ae_data.csv
├── scripts/
│   ├── ingest.py                      # CSV → DuckDB raw.shipments
│   ├── export_last_month.py           # Monthly export + email (optional)
│   └── superset_bootstrap.py          # Configures connection, dataset, metrics, dashboards
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   └── models/
│       ├── staging/                   # stg_shipments
│       ├── intermediate/              # int_shipments
│       └── mart/                      # dim_* + fct_shipments
├── airflow/dags/
│   └── loadsmart_pipeline.py          # ingest → dbt run → dbt test → export_last_month
├── notebooks/
│   └── loadsmart_analysis.ipynb
├── docs/
│   ├── analysis/
│   │   └── raw-data-findings.md
│   └── runbooks/
│       ├── rbk001-superset-connections.md
│       ├── rbk002-superset-datasets.md
│       ├── rbk003-superset-metrics.md
│       ├── rbk004-superset-dashboards.md
│       └── rbk005-create-dashboard.md
├── .env.example                       # template; copy to `.env` (not in git)
└── requirements.txt
```

---

## How to run the project

**Prerequisite:** Docker Desktop installed and running.

**Environment file:** `.env` is not in the repository (secrets stay local). After cloning, copy the template once, then run setup:

```bash
git clone https://github.com/AbnerHenriq/loadsmart-case.git
cd loadsmart-case
cp .env.example .env
make setup
```

You can edit `.env` later to rotate secrets or to enable SMTP for the monthly export (see [Monthly export by email](#monthly-export-by-email)). The values in `.env.example` are enough for a first local run.

`make setup` starts all containers, runs the data pipeline (ingest → dbt run → dbt test -> send to email), and configures Superset automatically. When it finishes, open:

- **Superset:** [http://localhost:8088](http://localhost:8088) — login `admin` / `admin`
- **Airflow:** [http://localhost:9090](http://localhost:9090) — login `admin` / `admin`

Superset comes up with 6 dashboards, 48 metrics, and the DuckDB connection wired.
                                                                      |

### Other commands

```bash

make setup # setup airflow, dbt, superset configuration
make reset # drop everything and start again (setup)

```

### Locally (without Docker)

Create a virtual environment to isolate project dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate       # Linux/macOS
# .venv\Scripts\activate        # Windows

pip install -r requirements.txt
```

With the venv active, run the pipeline:

```bash
# Ingestion
python scripts/ingest.py

# dbt
cd dbt
dbt deps --profiles-dir .
dbt run --profiles-dir .
dbt test --profiles-dir .
```

To deactivate the venv when done:

```bash
deactivate
```

### Jupyter Notebook

With the venv active:

```bash
jupyter notebook notebooks/loadsmart_analysis.ipynb
```

The notebook includes:

- `split_lane(lane)` — parses `"City,ST -> City,ST"` into a dict with pickup/delivery city and state

---

### Monthly export by email

The pipeline includes an `export_last_month` task that, at the end of each run,
writes the CSV to `data/exports/deliveries_YYYY_MM.csv` and sends it by email when
SMTP variables are set.

#### How to configure

Ensure you have a `.env` file (`cp .env.example .env` on first clone). To send email, **uncomment and fill** the SMTP block at the bottom of `.env.example` in your `.env` (or add the same variables):

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=you@gmail.com
SMTP_PASSWORD=your-app-password-here
SMTP_RECIPIENTS=recipient@example.com
```

If those variables are missing or empty, the task still writes the CSV under `data/exports/`; only the email step is skipped.

> Separate multiple recipients with a comma: `a@x.com,b@y.com`

#### How to get a Gmail App Password

Gmail does not accept your account password directly for SMTP app connections.
Use an **App Password**:

1. Go to [myaccount.google.com/security](https://myaccount.google.com/security)
2. Turn on **2-Step Verification** (if not already enabled)
3. Security → **App passwords** (or search “App Passwords”)
4. Choose app **Other (custom name)** → type `loadsmart` → **Generate**
5. Copy the 16-character password (no spaces) and paste it into `SMTP_PASSWORD`

#### How to test locally (without Docker)

```bash
# Export vars in the terminal session
export SMTP_HOST=smtp.gmail.com
export SMTP_PORT=587
export SMTP_USER=you@gmail.com
export SMTP_PASSWORD=your-app-password-here
export SMTP_RECIPIENTS=recipient@example.com
export DUCKDB_PATH=data/loadsmart.duckdb

# Run the script directly
source .venv/bin/activate
python scripts/export_last_month.py
```

Or re-trigger the `loadsmart_pipeline` DAG in Airflow — the `export_last_month` task handles sending.

## Exploring DuckDB

The database file is `data/loadsmart.duckdb` after the pipeline runs.

### Via terminal (DuckDB CLI)

```bash
# Install the CLI if you don’t have it
brew install duckdb          # macOS
# or download from https://duckdb.org/docs/installation

duckdb data/loadsmart.duckdb
```

Useful CLI commands:

```sql
-- List all schemas and tables
SHOW ALL TABLES;

-- Describe a table
DESCRIBE main_mart.fct_shipments;

-- Explore first rows
SELECT * FROM main_mart.fct_shipments LIMIT 10;
SELECT * FROM main_mart.dim_carrier   LIMIT 10;
SELECT * FROM main_mart.dim_location  LIMIT 10;
SELECT * FROM main_mart.dim_date      LIMIT 5;

-- Quit
.quit
```

### Via Python (venv active)

```python
import duckdb

con = duckdb.connect("data/loadsmart.duckdb")
df = con.execute("SELECT * FROM main_mart.fct_shipments LIMIT 20").df()
print(df)
```

---

## Dimensional model (star schema)

```
                    dim_date
                      │
          dim_carrier  │  dim_shipper
               │       │       │
               └───fct_shipments───┘
                      │
                 dim_location
```


| Table           | Schema       | Rows  | Description                                 |
| --------------- | ------------ | ----- | ------------------------------------------- |
| `raw.shipments` | raw          | 5,361 | Raw CSV data                                |
| `int_shipments` | intermediate | 5,357 | Deduplicated + derived metrics              |
| `dim_carrier`   | mart         | 2,203 | Unique carriers + “Unknown” sentinel        |
| `dim_shipper`   | mart         | 94    | Unique shippers                             |
| `dim_location`  | mart         | 988   | Unique cities/states (origin + destination) |
| `dim_date`      | mart         | 438   | Calendar covering the full data period      |
| `fct_shipments` | mart         | 5,357 | Central fact — one row per shipment         |


### dbt layers


| Layer        | Materialization | Purpose                                   |
| ------------ | --------------- | ----------------------------------------- |
| staging      | view            | Cleanup, typing, parsing the `lane` field |
| intermediate | table           | Deduplication, derived metrics            |
| mart         | table           | Dimensions and fact ready for analysis    |


---

## Metrics and dashboards (Superset)

All configured automatically by `superset_bootstrap.py` during `make setup`.

### Available dashboards


| Dashboard                   | Audience      | Questions answered                         |
| --------------------------- | ------------- | ------------------------------------------ |
| Financial Health            | CFO / Pricing | PnL, margin, revenue per mile              |
| Volume & Operational Funnel | Ops Manager   | Volume, cancellation, lead time            |
| Carrier Performance         | Ops Manager   | On-time rates, drops, VIP carriers         |
| Operational Autonomy        | Product       | Autonomous booking/sourcing vs human touch |
| Tracking & Visibility       | Product       | Mobile, Macropoint, EDI coverage           |


## Semantic Layer

#### Domain 1 — Financial


| Metric             | Label                 | Domain    | Owner         | SQL expression                     |
| ------------------ | --------------------- | --------- | ------------- | ---------------------------------- |
| `total_revenue`    | Total revenue         | Financial | CFO / Pricing | `SUM(book_price)`                  |
| `total_cost`       | Total cost            | Financial | CFO / Pricing | `SUM(source_price)`                |
| `total_pnl`        | Total PnL             | Financial | CFO / Pricing | `SUM(pnl)`                         |
| `avg_book_price`   | Avg book price        | Financial | CFO / Pricing | `AVG(book_price)`                  |
| `avg_pnl`          | Avg PnL               | Financial | CFO / Pricing | `AVG(pnl)`                         |
| `total_mileage`    | Total mileage         | Financial | CFO / Pricing | `SUM(mileage)`                     |
| `avg_mileage`      | Avg mileage           | Financial | CFO / Pricing | `AVG(mileage)`                     |
| `margin_pct`       | Margin %              | Financial | CFO / Pricing | `SUM(pnl) / SUM(book_price)`       |
| `cost_per_mile`    | Cost per mile         | Financial | CFO / Pricing | `SUM(source_price) / SUM(mileage)` |
| `revenue_per_mile` | Revenue per mile      | Financial | CFO / Pricing | `SUM(book_price) / SUM(mileage)`   |
| `pnl_per_mile`     | PnL per mile          | Financial | CFO / Pricing | `SUM(pnl) / SUM(mileage)`          |
| `spread_price`     | Book vs source spread | Financial | CFO / Pricing | `AVG(book_price - source_price)`   |


#### Domain 2 — Volume and funnel


| Metric                   | Label                           | Domain          | Owner       | SQL expression                                  |
| ------------------------ | ------------------------------- | --------------- | ----------- | ----------------------------------------------- |
| `total_loads`            | Total loads                     | Volume / Funnel | Ops Manager | `COUNT(loadsmart_id)`                           |
| `cancelled_loads`        | Cancelled loads                 | Volume / Funnel | Ops Manager | `SUM(load_was_cancelled::int)`                  |
| `active_loads`           | Active loads                    | Volume / Funnel | Ops Manager | `SUM((NOT load_was_cancelled)::int)`            |
| `contracted_loads`       | Contracted loads                | Volume / Funnel | Ops Manager | `SUM(contracted_load::int)`                     |
| `cancellation_rate`      | Cancellation rate               | Volume / Funnel | Ops Manager | `SUM(load_was_cancelled::int) * 1.0 / COUNT(*)` |
| `contracted_load_rate`   | % contracted loads              | Volume / Funnel | Product     | `SUM(contracted_load::int) * 1.0 / COUNT(*)`    |
| `avg_lead_time_booking`  | Lead time quote → book (hours)  | Volume / Funnel | Product     | `AVG(datediff('hour', quote_at, booked_at))`    |
| `avg_lead_time_sourcing` | Lead time book → source (hours) | Volume / Funnel | Product     | `AVG(datediff('hour', booked_at, sourced_at))`  |
| `avg_transit_days`       | Avg transit time (days)         | Volume / Funnel | Ops Manager | `AVG(datediff('day', pickup_at, delivered_at))` |


#### Domain 3 — Carrier performance


| Metric                   | Label                          | Domain  | Owner       | SQL expression                                                                                   |
| ------------------------ | ------------------------------ | ------- | ----------- | ------------------------------------------------------------------------------------------------ |
| `on_time_pickup_count`   | On-time pickups (count)        | Carrier | Ops Manager | `SUM(carrier_on_time_to_pickup::int)`                                                            |
| `on_time_delivery_count` | On-time deliveries (count)     | Carrier | Ops Manager | `SUM(carrier_on_time_to_delivery::int)`                                                          |
| `on_time_overall_count`  | On-time overall (count)        | Carrier | Ops Manager | `SUM(carrier_on_time_overall::int)`                                                              |
| `total_carrier_drops`    | Total drops                    | Carrier | Ops Manager | `SUM(carrier_dropped_us_count)`                                                                  |
| `vip_carrier_loads`      | Loads with VIP carrier         | Carrier | Ops Manager | `SUM(vip_carrier::int)`                                                                          |
| `on_time_pickup_rate`    | On-time to pickup %            | Carrier | Ops Manager | `SUM(carrier_on_time_to_pickup::int) * 1.0 / COUNT(*)`                                           |
| `on_time_delivery_rate`  | On-time to delivery %          | Carrier | Ops Manager | `SUM(carrier_on_time_to_delivery::int) * 1.0 / COUNT(*)`                                         |
| `on_time_overall_rate`   | On-time overall %              | Carrier | Ops Manager | `SUM(carrier_on_time_overall::int) * 1.0 / COUNT(*)`                                             |
| `avg_drops_per_carrier`  | Avg drops per carrier          | Carrier | Ops Manager | `SUM(carrier_dropped_us_count) * 1.0 / COUNT(*)`                                                 |
| `vip_carrier_rate`       | % loads with VIP carrier       | Carrier | Ops Manager | `SUM(vip_carrier::int) * 1.0 / COUNT(*)`                                                         |
| `on_time_delta`          | Pickup vs delivery on-time gap | Carrier | Ops Manager | `(SUM(carrier_on_time_to_pickup::int) - SUM(carrier_on_time_to_delivery::int)) * 1.0 / COUNT(*)` |


#### Domain 4 — Operational autonomy


| Metric                     | Label                      | Domain     | Owner   | SQL expression                                                                              |
| -------------------------- | -------------------------- | ---------- | ------- | ------------------------------------------------------------------------------------------- |
| `autonomously_booked`      | Autonomous bookings        | Automation | Product | `SUM(load_booked_autonomously::int)`                                                        |
| `autonomously_sourced`     | Autonomous sourcings       | Automation | Product | `SUM(load_sourced_autonomously::int)`                                                       |
| `fully_autonomous_loads`   | 100% autonomous loads      | Automation | Product | `SUM((load_booked_autonomously AND load_sourced_autonomously)::int)`                        |
| `autonomous_booking_rate`  | Autonomous booking rate %  | Automation | Product | `SUM(load_booked_autonomously::int) * 1.0 / COUNT(*)`                                       |
| `autonomous_sourcing_rate` | Autonomous sourcing rate % | Automation | Product | `SUM(load_sourced_autonomously::int) * 1.0 / COUNT(*)`                                      |
| `fully_autonomous_rate`    | 100% autonomous rate %     | Automation | Product | `SUM((load_booked_autonomously AND load_sourced_autonomously)::int) * 1.0 / COUNT(*)`       |
| `human_intervention_rate`  | Human intervention rate %  | Automation | Product | `1.0 - SUM((load_booked_autonomously AND load_sourced_autonomously)::int) * 1.0 / COUNT(*)` |


#### Domain 5 — Tracking and visibility


| Metric                     | Label                      | Domain   | Owner   | SQL expression                                                                                              |
| -------------------------- | -------------------------- | -------- | ------- | ----------------------------------------------------------------------------------------------------------- |
| `mobile_tracked`           | Loads with mobile tracking | Tracking | Product | `SUM(has_mobile_app_tracking::int)`                                                                         |
| `macropoint_tracked`       | Loads with Macropoint      | Tracking | Product | `SUM(has_macropoint_tracking::int)`                                                                         |
| `edi_tracked`              | Loads with EDI             | Tracking | Product | `SUM(has_edi_tracking::int)`                                                                                |
| `any_tracked`              | Loads with any tracking    | Tracking | Product | `SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int)`                        |
| `mobile_tracking_rate`     | Mobile app coverage %      | Tracking | Product | `SUM(has_mobile_app_tracking::int) * 1.0 / COUNT(*)`                                                        |
| `macropoint_tracking_rate` | Macropoint coverage %      | Tracking | Product | `SUM(has_macropoint_tracking::int) * 1.0 / COUNT(*)`                                                        |
| `edi_tracking_rate`        | EDI coverage %             | Tracking | Product | `SUM(has_edi_tracking::int) * 1.0 / COUNT(*)`                                                               |
| `total_tracking_coverage`  | Total tracking coverage %  | Tracking | Product | `SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int) * 1.0 / COUNT(*)`       |
| `blind_shipment_rate`      | Loads with no tracking %   | Tracking | Product | `1.0 - SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int) * 1.0 / COUNT(*)` |


### Dashboard 1 — Operational health

**Audience:** ops manager · **Question:** did something break?


| Chart                      | Type           | Metric(s)                                      | Dimension               |
| -------------------------- | -------------- | ---------------------------------------------- | ----------------------- |
| On-time rate               | KPI            | `on_time_overall_rate`                         | —                       |
| Total loads                | KPI            | `COUNT(loadsmart_id)`                          | —                       |
| Avg transit time           | KPI            | `AVG(lead_time_days)`                          | —                       |
| Cancellation rate          | KPI            | `cancellation_rate`                            | —                       |
| On-time rate by carrier    | Horizontal bar | `on_time_overall_rate`                         | `carrier_name`          |
| Monthly on-time trend      | Line           | `on_time_overall_rate`                         | month of `delivered_at` |
| Mix by equipment type      | Donut          | `COUNT(*)`                                     | `equipment_type`        |
| Pickup vs delivery on-time | Grouped bar    | `on_time_pickup_rate`, `on_time_delivery_rate` | `carrier_name`          |


### Dashboard 2 — Financial health

**Audience:** CFO / pricing analyst · **Question:** where do we profit and lose?


| Chart                        | Type           | Metric(s)                | Dimension               |
| ---------------------------- | -------------- | ------------------------ | ----------------------- |
| Total PnL                    | KPI            | `SUM(pnl)`               | —                       |
| Margin %                     | KPI            | `margin_pct`             | —                       |
| Cost per mile                | KPI            | `cost_per_mile`          | —                       |
| Avg book price               | KPI            | `AVG(book_price)`        | —                       |
| Margin by sourcing channel   | Horizontal bar | `margin_pct`             | `sourcing_channel`      |
| PnL by shipper (top 10)      | Horizontal bar | `SUM(pnl)`               | `shipper_name`          |
| Mileage vs PnL               | Scatter        | `pnl_per_mile`           | `carrier_name`          |
| Monthly PnL and margin trend | Line           | `SUM(pnl)`, `margin_pct` | month of `delivered_at` |


### Dashboard 3 — Efficiency & autonomy

**Audience:** product / leadership · **Question:** is automation improving?


| Chart                     | Type           | Metric(s)                                                              | Dimension               |
| ------------------------- | -------------- | ---------------------------------------------------------------------- | ----------------------- |
| 100% autonomous rate      | KPI            | `fully_autonomous_rate`                                                | —                       |
| Tracking coverage         | KPI            | `total_tracking_coverage`                                              | —                       |
| % VIP carrier loads       | KPI            | `vip_carrier_rate`                                                     | —                       |
| Loads without tracking    | KPI            | `blind_shipment_rate`                                                  | —                       |
| Autonomy by channel       | Horizontal bar | `fully_autonomous_rate`                                                | `sourcing_channel`      |
| Coverage by tracking type | Grouped bar    | `mobile/macropoint/edi_rate`                                           | —                       |
| Monthly autonomy trend    | Line           | `fully_autonomous_rate`                                                | month of `delivered_at` |
| Ranked carriers           | Table          | `on_time_overall_rate`, `fully_autonomous_rate`, `blind_shipment_rate` | `carrier_name`          |


---

## Data quality

Quality findings for the raw layer are documented in
[docs/analysis/raw-data-findings.md](docs/analysis/raw-data-findings.md).

Summary of main points:


| Finding                                             | Rows | Severity |
| --------------------------------------------------- | ---- | -------- |
| Duplicate `has_mobile_app_tracking` column in CSV   | all  | High     |
| `pnl` inconsistent with `book_price - source_price` | 24   | High     |
| `delivered_at` before `pickup_at`                   | 467  | High     |
| Duplicate `loadsmart_id` (identical rows)           | 8    | Medium   |
| Null `carrier_name` (mostly cancelled)              | 499  | Medium   |
| `mileage = 0` on non-cancelled loads                | 45   | Medium   |


dbt tests are set to `warn` (non-blocking) for known findings so the pipeline can run
while issues are investigated.

---

## Stop and reset the environment

```bash
make teardown    # stop and remove containers, volumes, and local images
make reset       # teardown + full setup (useful for a clean slate)
```

