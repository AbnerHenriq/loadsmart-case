"""
superset_bootstrap.py
---------------------
Bootstraps a fresh Superset instance with all Loadsmart case resources:
  1. Database connection (DuckDB)
  2. Virtual datasets (all loads + active loads only)
  3. Metrics (48 across 5 domains)
  4. Dashboards + charts (5 dashboards)

Idempotent: skips any resource that already exists by name.
Run after `docker compose up` once Superset is healthy.

Usage:
    python scripts/superset_bootstrap.py

Environment variables (all optional):
    SUPERSET_URL       default: http://localhost:8088
    SUPERSET_USERNAME  default: admin
    SUPERSET_PASSWORD  default: admin
    DUCKDB_PATH        default: /opt/airflow/data/loadsmart.duckdb

If AIRFLOW_WEBSERVER_INTERNAL is set (e.g. http://airflow-webserver:8080 in Docker),
the bootstrap waits for the latest loadsmart_pipeline DAG run to succeed via the
Airflow REST API instead of opening DuckDB (avoids file-lock races on bind mounts).
Use AIRFLOW_USER / AIRFLOW_PASS (or AIRFLOW_API_USER / AIRFLOW_API_PASSWORD) for basic auth.
"""

import json
import os
import sys
import time

import requests

# ── Config ────────────────────────────────────────────────────────────────────

BASE = os.getenv("SUPERSET_URL", "http://localhost:8088")
USERNAME = os.getenv("SUPERSET_USERNAME", "admin")
PASSWORD = os.getenv("SUPERSET_PASSWORD", "admin")
DUCKDB_PATH = os.getenv("DUCKDB_PATH", "/opt/airflow/data/loadsmart.duckdb")

# ── Auth ──────────────────────────────────────────────────────────────────────

def get_session() -> requests.Session:
    session = requests.Session()
    token = session.post(f"{BASE}/api/v1/security/login", json={
        "username": USERNAME, "password": PASSWORD, "provider": "db"
    }).json()["access_token"]
    session.headers.update({"Authorization": f"Bearer {token}"})
    csrf = session.get(f"{BASE}/api/v1/security/csrf_token/").json()["result"]
    session.headers.update({"X-CSRFToken": csrf, "Content-Type": "application/json"})
    return session


def wait_for_superset(timeout: int = 120):
    print(f"Waiting for Superset at {BASE} ...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = requests.get(f"{BASE}/health", timeout=5)
            if r.status_code == 200:
                print("  ✓ Superset ready")
                return
        except requests.ConnectionError:
            pass
        time.sleep(5)
    print("  ✗ Superset did not respond — aborting", file=sys.stderr)
    sys.exit(1)


def wait_for_duckdb(timeout: int = 600):
    """
    Wait for the Airflow DAG to materialize dbt models.
    Checks that main_mart.fct_shipments exists and has rows.
    Exits with code 1 on timeout (docker-compose restart: on-failure will retry).
    """
    try:
        import duckdb as _duckdb
    except ImportError:
        print("  ~ duckdb not available in this container — skipping check")
        print()
        return

    print(f"Waiting for dbt models at {DUCKDB_PATH} ...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            con = _duckdb.connect(DUCKDB_PATH, read_only=True)
            count = con.execute(
                "SELECT COUNT(*) FROM main_mart.fct_shipments"
            ).fetchone()[0]
            con.close()
            if count > 0:
                print(f"  ✓ DuckDB ready ({count:,} rows in fct_shipments)\n")
                return
        except Exception:
            pass
        print("  ... dbt models not yet available, waiting 15s")
        time.sleep(15)

    print(
        "  ✗ dbt models not found after timeout.\n"
        "    Open Airflow (localhost:9090) and run the 'loadsmart_pipeline' DAG.\n"
        "    This service will retry automatically.",
        file=sys.stderr,
    )
    sys.exit(1)


def wait_for_airflow_pipeline(timeout: int = 900):
    """
    Poll Airflow REST API until the latest dag_run of loadsmart_pipeline is success.
    Avoids opening DuckDB while ingest/dbt hold locks (e.g. Docker Desktop + macOS).
    """
    base = os.getenv("AIRFLOW_WEBSERVER_INTERNAL", "").strip().rstrip("/")
    if not base:
        return

    user = os.getenv("AIRFLOW_API_USER", os.getenv("AIRFLOW_USER", "admin"))
    password = os.getenv("AIRFLOW_API_PASSWORD", os.getenv("AIRFLOW_PASS", "admin"))
    dag_id = os.getenv("AIRFLOW_DAG_ID", "loadsmart_pipeline")
    url = f"{base}/api/v1/dags/{dag_id}/dagRuns"

    print(f"Waiting for Airflow DAG {dag_id!r} (latest run = success) at {base} ...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = requests.get(
                url,
                params={"order_by": "-start_date", "limit": 1},
                auth=(user, password),
                timeout=30,
            )
            r.raise_for_status()
            runs = r.json().get("dag_runs") or []
            if not runs:
                print("  ... no dag runs yet, waiting 15s")
                time.sleep(15)
                continue
            state = runs[0].get("state")
            run_id = runs[0].get("dag_run_id", "?")
            if state == "success":
                print(f"  ✓ pipeline succeeded (run_id={run_id})\n")
                return
            if state == "failed":
                print(
                    "  ✗ latest DAG run failed — fix the pipeline and re-run.\n"
                    "    This service will retry automatically.",
                    file=sys.stderr,
                )
                sys.exit(1)
            print(f"  ... dag run state={state!r} (run_id={run_id}), waiting 15s")
            time.sleep(15)
        except requests.RequestException as e:
            print(f"  ... Airflow API unreachable ({e}), waiting 15s")
            time.sleep(15)

    print(
        "  ✗ timeout waiting for successful DAG run.\n"
        "    Open Airflow and run loadsmart_pipeline.\n"
        "    This service will retry automatically.",
        file=sys.stderr,
    )
    sys.exit(1)


# ── Helpers ───────────────────────────────────────────────────────────────────

def log(msg: str):
    print(msg)


def ok(name: str):
    print(f"  ✓ {name}")


def skip(name: str):
    print(f"  ~ {name} (already exists — skipping)")


# ── 1. Connection ─────────────────────────────────────────────────────────────

def setup_connection(session: requests.Session) -> int:
    log("── 1. Database connection ──")

    existing = {db["database_name"]: db["id"]
                for db in session.get(f"{BASE}/api/v1/database/?q=(page_size:50)").json().get("result", [])}

    if "DuckDB" in existing:
        skip("DuckDB")
        return existing["DuckDB"]

    r = session.post(f"{BASE}/api/v1/database/", json={
        "database_name":        "DuckDB",
        "sqlalchemy_uri":       f"duckdb:////{DUCKDB_PATH}",
        "configuration_method": "sqlalchemy_form",
        "driver":               "duckdb_engine",
        "expose_in_sqllab":     True,
        "allow_ctas":           False,
        "allow_cvas":           False,
        "allow_dml":            False,
        "allow_file_upload":    False,
        "allow_run_async":      False,
        "extra":                json.dumps({
            "metadata_params": {}, "engine_params": {},
            "metadata_cache_timeout": {}, "schemas_allowed_for_file_upload": []
        }),
        "masked_encrypted_extra": "{}",
        "impersonate_user":     False,
    })
    db_id = r.json()["id"]
    ok(f"DuckDB created (id={db_id})")
    return db_id


# ── 2. Datasets ───────────────────────────────────────────────────────────────

DATASET_SQL = {
    "fct_shipments": """
SELECT
    f.*,
    dc.carrier_name,
    ds.shipper_name
FROM main_mart.fct_shipments f
LEFT JOIN main_mart.dim_carrier  dc ON f.carrier_sk = dc.carrier_sk
LEFT JOIN main_mart.dim_shipper  ds ON f.shipper_sk = ds.shipper_sk
""".strip(),
}


def setup_datasets(session: requests.Session, db_id: int) -> dict[str, int]:
    log("\n── 2. Datasets ──")

    existing = {ds["table_name"]: ds["id"]
                for ds in session.get(f"{BASE}/api/v1/dataset/?q=(page_size:50)").json().get("result", [])}

    ids = {}
    for name, sql in DATASET_SQL.items():
        if name in existing:
            skip(name)
            ids[name] = existing[name]
            continue

        r = session.post(f"{BASE}/api/v1/dataset/", json={
            "database": db_id,
            "table_name": name,
            "schema": "loadsmart.main_mart",
            "sql": sql,
        })
        if r.status_code == 201:
            ds_id = r.json()["id"]
            session.put(f"{BASE}/api/v1/dataset/{ds_id}/refresh")
            ok(f"{name} (id={ds_id})")
            ids[name] = ds_id
        else:
            print(f"  ✗ {name}: {r.status_code} {r.text[:200]}", file=sys.stderr)

    return ids


# ── 3. Metrics ────────────────────────────────────────────────────────────────

ALL_METRICS = [
    # Domain 1 — Financial
    {"metric_name":"total_revenue",    "verbose_name":"Total revenue",          "expression":"SUM(book_price)",                    "metric_type":"sum","d3format":"$,.2f"},
    {"metric_name":"total_cost",       "verbose_name":"Total cost",            "expression":"SUM(source_price)",                  "metric_type":"sum","d3format":"$,.2f"},
    {"metric_name":"total_pnl",        "verbose_name":"Total PnL",              "expression":"SUM(pnl)",                           "metric_type":"sum","d3format":"$,.2f"},
    {"metric_name":"avg_book_price",   "verbose_name":"Avg book price",       "expression":"AVG(book_price)",                    "metric_type":"avg","d3format":"$,.2f"},
    {"metric_name":"avg_pnl",          "verbose_name":"Avg PnL",              "expression":"AVG(pnl)",                           "metric_type":"avg","d3format":"$,.2f"},
    {"metric_name":"total_mileage",    "verbose_name":"Total mileage",          "expression":"SUM(mileage)",                       "metric_type":"sum","d3format":",d"},
    {"metric_name":"avg_mileage",      "verbose_name":"Avg mileage",          "expression":"AVG(mileage)",                       "metric_type":"avg","d3format":",.1f"},
    {"metric_name":"margin_pct",       "verbose_name":"Margin %",               "expression":"SUM(pnl) / SUM(book_price)",         "metric_type":"avg","d3format":".1%"},
    {"metric_name":"cost_per_mile",    "verbose_name":"Cost per mile",        "expression":"SUM(source_price) / SUM(mileage)",   "metric_type":"avg","d3format":"$,.3f"},
    {"metric_name":"revenue_per_mile", "verbose_name":"Revenue per mile",      "expression":"SUM(book_price) / SUM(mileage)",     "metric_type":"avg","d3format":"$,.3f"},
    {"metric_name":"pnl_per_mile",     "verbose_name":"PnL per mile",          "expression":"SUM(pnl) / SUM(mileage)",            "metric_type":"avg","d3format":"$,.3f"},
    {"metric_name":"spread_price",     "verbose_name":"Book vs source spread",  "expression":"AVG(book_price - source_price)",     "metric_type":"avg","d3format":"$,.2f"},
    # Domain 2 — Volume / Funnel
    {"metric_name":"total_loads",          "verbose_name":"Total loads",              "expression":"COUNT(loadsmart_id)",                                              "metric_type":"count","d3format":",d"},
    {"metric_name":"cancelled_loads",      "verbose_name":"Cancelled loads",            "expression":"SUM(load_was_cancelled::int)",                                      "metric_type":"sum",  "d3format":",d"},
    {"metric_name":"active_loads",         "verbose_name":"Active loads",                "expression":"SUM((NOT load_was_cancelled)::int)",                                "metric_type":"sum",  "d3format":",d"},
    {"metric_name":"contracted_loads",     "verbose_name":"Contracted loads",           "expression":"SUM(contracted_load::int)",                                         "metric_type":"sum",  "d3format":",d"},
    {"metric_name":"cancellation_rate",    "verbose_name":"Cancellation rate",         "expression":"SUM(load_was_cancelled::int) * 1.0 / COUNT(*)",                     "metric_type":"avg",  "d3format":".1%"},
    {"metric_name":"contracted_load_rate", "verbose_name":"% contracted loads",         "expression":"SUM(contracted_load::int) * 1.0 / COUNT(*)",                        "metric_type":"avg",  "d3format":".1%"},
    {"metric_name":"avg_lead_time_booking","verbose_name":"Lead time quote→book (h)",     "expression":"AVG(datediff('hour', quote_at, booked_at))",                        "metric_type":"avg",  "d3format":",.1f"},
    {"metric_name":"avg_lead_time_sourcing","verbose_name":"Lead time book→source (h)",   "expression":"AVG(datediff('hour', booked_at, sourced_at))",                      "metric_type":"avg",  "d3format":",.1f"},
    {"metric_name":"avg_transit_days",     "verbose_name":"Avg transit time (days)",    "expression":"AVG(datediff('day', pickup_at, delivered_at))",                     "metric_type":"avg",  "d3format":",.1f"},
    # Domain 3 — Carrier
    {"metric_name":"on_time_pickup_count",   "verbose_name":"On-time pickups",            "expression":"SUM(carrier_on_time_to_pickup::int)",                                                              "metric_type":"sum","d3format":",d"},
    {"metric_name":"on_time_delivery_count", "verbose_name":"On-time deliveries",           "expression":"SUM(carrier_on_time_to_delivery::int)",                                                            "metric_type":"sum","d3format":",d"},
    {"metric_name":"on_time_overall_count",  "verbose_name":"On-time overall",              "expression":"SUM(carrier_on_time_overall::int)",                                                                "metric_type":"sum","d3format":",d"},
    {"metric_name":"total_carrier_drops",    "verbose_name":"Total carrier drops",             "expression":"SUM(carrier_dropped_us_count)",                                                                    "metric_type":"sum","d3format":",d"},
    {"metric_name":"vip_carrier_loads",      "verbose_name":"Loads with VIP carrier",     "expression":"SUM(vip_carrier::int)",                                                                            "metric_type":"sum","d3format":",d"},
    {"metric_name":"on_time_pickup_rate",    "verbose_name":"On-time to pickup %",        "expression":"SUM(carrier_on_time_to_pickup::int) * 1.0 / COUNT(*)",                                            "metric_type":"avg","d3format":".1%"},
    {"metric_name":"on_time_delivery_rate",  "verbose_name":"On-time to delivery %",      "expression":"SUM(carrier_on_time_to_delivery::int) * 1.0 / COUNT(*)",                                          "metric_type":"avg","d3format":".1%"},
    {"metric_name":"on_time_overall_rate",   "verbose_name":"On-time overall %",          "expression":"SUM(carrier_on_time_overall::int) * 1.0 / COUNT(*)",                                              "metric_type":"avg","d3format":".1%"},
    {"metric_name":"avg_drops_per_carrier",  "verbose_name":"Avg drops per carrier", "expression":"SUM(carrier_dropped_us_count) * 1.0 / COUNT(*)",                                                  "metric_type":"avg","d3format":".2f"},
    {"metric_name":"vip_carrier_rate",       "verbose_name":"% loads with VIP carrier",   "expression":"SUM(vip_carrier::int) * 1.0 / COUNT(*)",                                                          "metric_type":"avg","d3format":".1%"},
    {"metric_name":"on_time_delta",          "verbose_name":"Pickup vs delivery on-time gap",  "expression":"(SUM(carrier_on_time_to_pickup::int) - SUM(carrier_on_time_to_delivery::int)) * 1.0 / COUNT(*)", "metric_type":"avg","d3format":".1%"},
    # Domain 4 — Automation
    {"metric_name":"autonomously_booked",    "verbose_name":"Autonomous bookings",          "expression":"SUM(load_booked_autonomously::int)",                                                                    "metric_type":"sum","d3format":",d"},
    {"metric_name":"autonomously_sourced",   "verbose_name":"Autonomous sourcings",         "expression":"SUM(load_sourced_autonomously::int)",                                                                   "metric_type":"sum","d3format":",d"},
    {"metric_name":"fully_autonomous_loads", "verbose_name":"100% autonomous loads",       "expression":"SUM((load_booked_autonomously AND load_sourced_autonomously)::int)",                                    "metric_type":"sum","d3format":",d"},
    {"metric_name":"autonomous_booking_rate","verbose_name":"Autonomous booking rate",    "expression":"SUM(load_booked_autonomously::int) * 1.0 / COUNT(*)",                                                  "metric_type":"avg","d3format":".1%"},
    {"metric_name":"autonomous_sourcing_rate","verbose_name":"Autonomous sourcing rate",  "expression":"SUM(load_sourced_autonomously::int) * 1.0 / COUNT(*)",                                                 "metric_type":"avg","d3format":".1%"},
    {"metric_name":"fully_autonomous_rate",  "verbose_name":"100% autonomous rate",          "expression":"SUM((load_booked_autonomously AND load_sourced_autonomously)::int) * 1.0 / COUNT(*)",                  "metric_type":"avg","d3format":".1%"},
    {"metric_name":"human_intervention_rate","verbose_name":"Human intervention rate",  "expression":"1.0 - SUM((load_booked_autonomously AND load_sourced_autonomously)::int) * 1.0 / COUNT(*)",            "metric_type":"avg","d3format":".1%"},
    # Domain 5 — Tracking
    {"metric_name":"mobile_tracked",          "verbose_name":"Loads with mobile tracking", "expression":"SUM(has_mobile_app_tracking::int)",                                                                          "metric_type":"sum","d3format":",d"},
    {"metric_name":"macropoint_tracked",      "verbose_name":"Loads with Macropoint",      "expression":"SUM(has_macropoint_tracking::int)",                                                                          "metric_type":"sum","d3format":",d"},
    {"metric_name":"edi_tracked",             "verbose_name":"Loads with EDI",             "expression":"SUM(has_edi_tracking::int)",                                                                                 "metric_type":"sum","d3format":",d"},
    {"metric_name":"any_tracked",             "verbose_name":"Loads with any tracking",  "expression":"SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int)",                        "metric_type":"sum","d3format":",d"},
    {"metric_name":"mobile_tracking_rate",    "verbose_name":"Mobile app coverage %",     "expression":"SUM(has_mobile_app_tracking::int) * 1.0 / COUNT(*)",                                                        "metric_type":"avg","d3format":".1%"},
    {"metric_name":"macropoint_tracking_rate","verbose_name":"Macropoint coverage %",     "expression":"SUM(has_macropoint_tracking::int) * 1.0 / COUNT(*)",                                                        "metric_type":"avg","d3format":".1%"},
    {"metric_name":"edi_tracking_rate",       "verbose_name":"EDI coverage %",            "expression":"SUM(has_edi_tracking::int) * 1.0 / COUNT(*)",                                                               "metric_type":"avg","d3format":".1%"},
    {"metric_name":"total_tracking_coverage", "verbose_name":"Total tracking coverage %","expression":"SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int) * 1.0 / COUNT(*)",    "metric_type":"avg","d3format":".1%"},
    {"metric_name":"blind_shipment_rate",     "verbose_name":"Loads with no tracking %","expression":"1.0 - SUM((has_mobile_app_tracking OR has_macropoint_tracking OR has_edi_tracking)::int) * 1.0 / COUNT(*)","metric_type":"avg","d3format":".1%"},
]

ALLOWED_MET = {"metric_name","expression","metric_type","verbose_name","d3format","description","warning_text","extra"}


def setup_metrics(session: requests.Session, dataset_id: int):
    log("\n── 3. Metrics ──")

    existing = session.get(f"{BASE}/api/v1/dataset/{dataset_id}").json()["result"]["metrics"]
    existing_names = {m["metric_name"] for m in existing
                      if m["metric_name"] in {m["metric_name"] for m in ALL_METRICS}}

    if len(existing_names) == len(ALL_METRICS):
        skip(f"all {len(ALL_METRICS)} metrics")
        return

    # Full PUT: replaces all metrics at once.
    # Do not merge old metrics with IDs mixed with new ones without ID — causes
    # 422 "One or more metrics already exist" in Superset.
    r = session.put(f"{BASE}/api/v1/dataset/{dataset_id}", json={"metrics": ALL_METRICS})
    if r.status_code == 200:
        ok(f"{len(ALL_METRICS)} metrics applied (full replace)")
    else:
        print(f"  ✗ metrics: {r.status_code} {r.text[:200]}", file=sys.stderr)
        sys.exit(1)


# ── 4. Dashboards ─────────────────────────────────────────────────────────────

KPI_FONT = {"header_font_size": 0.3, "subheader_font_size": 0.125}


def kpi(metric: str, ds: str) -> dict:
    return {"viz_type": "big_number_total", "datasource": ds, "metric": metric,
            "time_range": "No filter", **KPI_FONT}


def bar(metrics: list, y_label: str, ds: str, color_scheme: str = "d3Category10",
        stack: bool = False, y_fmt: str = ",d") -> dict:
    return {"viz_type": "echarts_timeseries_bar", "datasource": ds, "metrics": metrics,
            "x_axis": "delivered_at", "time_grain_sqla": "P1M", "time_range": "No filter",
            "x_axis_title": "Month", "y_axis_title": y_label,
            "x_axis_time_format": "%b/%Y", "tooltipTimeFormat": "%b/%Y",
            "y_axis_format": y_fmt, "rich_tooltip": True,
            "stack": stack, "color_scheme": color_scheme}


def tbl(metrics: list, groupby: list, ds: str, row_limit: int = 10) -> dict:
    """Table chart for categorical groupby / rankings.
    Use this instead of 'bar' or 'echarts_bar' — those plugins are NOT loaded in
    apache/superset:latest (6.0.1). The API accepts them (201) but the frontend throws
    'Item with key X is not registered' at render time.
    groupby values must match column names from GET /api/v1/dataset/{id} (mart uses snake_case)."""
    return {"viz_type": "table", "datasource": ds, "metrics": metrics,
            "groupby": groupby, "time_range": "No filter",
            "row_limit": row_limit, "page_length": row_limit}


def build_position_json(title: str, chart_ids: list, rows: list) -> dict:
    """
    rows: list of (index_list, height)
    e.g. [([0,1,2], 25), ([3,4], 35)]
    """
    pos = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID":   {"id": "ROOT_ID",   "type": "ROOT",   "children": ["GRID_ID"]},
        "GRID_ID":   {"id": "GRID_ID",   "type": "GRID",   "parents": ["ROOT_ID"],
                      "children": [f"ROW_{i+1}" for i in range(len(rows))]},
        "HEADER_ID": {"id": "HEADER_ID", "type": "HEADER", "meta": {"text": title}},
    }
    for ri, (idxs, height) in enumerate(rows):
        row_id = f"ROW_{ri+1}"
        keys = [f"CHART_{chart_ids[i]}" for i in idxs]
        pos[row_id] = {"id": row_id, "type": "ROW",
                       "parents": ["ROOT_ID", "GRID_ID"], "children": keys,
                       "meta": {"background": "BACKGROUND_TRANSPARENT"}}
        width = 12 // len(idxs)
        for i in idxs:
            cid = chart_ids[i]
            pos[f"CHART_{cid}"] = {
                "id": f"CHART_{cid}", "type": "CHART",
                "parents": ["ROOT_ID", "GRID_ID", row_id], "children": [],
                "meta": {"chartId": cid, "width": width, "height": height, "sliceName": ""},
            }
    return pos


def create_dashboard(session: requests.Session, title: str, charts_def: list, rows: list,
                     existing_dash_titles: set, ds_id: int = 1) -> int | None:
    if title in existing_dash_titles:
        skip(f"dashboard '{title}'")
        return None

    # Create charts
    chart_ids = []
    for name, viz_type, params in charts_def:
        r = session.post(f"{BASE}/api/v1/chart/", json={
            "slice_name": name, "viz_type": viz_type,
            "datasource_id": ds_id, "datasource_type": "table",
            "params": json.dumps(params),
        })
        cid = r.json()["id"]
        chart_ids.append(cid)

    # Create dashboard
    r = session.post(f"{BASE}/api/v1/dashboard/", json={
        "dashboard_title": title, "published": True
    })
    dash_id = r.json()["id"]

    # Link charts
    for cid in chart_ids:
        session.put(f"{BASE}/api/v1/chart/{cid}", json={"dashboards": [dash_id]})

    # Apply layout
    pos = build_position_json(title, chart_ids, rows)
    session.put(f"{BASE}/api/v1/dashboard/{dash_id}", json={
        "position_json": json.dumps(pos),
        "json_metadata": json.dumps({"refresh_frequency": 0}),
    })

    ok(f"dashboard '{title}' (id={dash_id}, {len(chart_ids)} charts)")
    return dash_id


def setup_dashboards(session: requests.Session, ds_id: int):
    log("\n── 4. Dashboards ──")

    existing_titles = {d["dashboard_title"]
                       for d in session.get(f"{BASE}/api/v1/dashboard/?q=(page_size:50)").json().get("result", [])}

    DS = f"{ds_id}__table"
    log(f"  dataset id={ds_id} → datasource '{DS}'")

    # ── Volume & operational funnel ────────────────────────────────────────────
    create_dashboard(session, "Volume & Operational Funnel", [
        ("Total loads",         "big_number_total",       kpi("total_loads",          DS)),
        ("Cancellation rate",    "big_number_total",       kpi("cancellation_rate",    DS)),
        ("% contracted loads",    "big_number_total",       kpi("contracted_load_rate", DS)),
        ("Avg transit time",      "big_number_total",       kpi("avg_transit_days",     DS)),
        ("Lead time quote→book",    "big_number_total",       kpi("avg_lead_time_booking",DS)),
        ("Lead time book→source",   "big_number_total",       kpi("avg_lead_time_sourcing",DS)),
        ("Monthly load trend","echarts_timeseries_bar",bar(["total_loads"],          "Loads", DS, color_scheme="supersetColors")),
        ("Active vs cancelled loads","echarts_timeseries_bar",bar(["active_loads","cancelled_loads"],"Loads",DS)),
    ], rows=[([0,1,2], 25), ([3,4,5], 25), ([6,7], 35)], existing_dash_titles=existing_titles, ds_id=ds_id)

    # ── Financial health ──────────────────────────────────────────────────────
    create_dashboard(session, "Financial Health", [
        ("Total revenue",            "big_number_total",        kpi("total_revenue",    DS)),
        ("Total cost",              "big_number_total",        kpi("total_cost",       DS)),
        ("Total PnL",                "big_number_total",        kpi("total_pnl",        DS)),
        ("Margin %",                 "big_number_total",        kpi("margin_pct",       DS)),
        ("Avg book price",         "big_number_total",        kpi("avg_book_price",   DS)),
        ("Avg PnL",                "big_number_total",        kpi("avg_pnl",          DS)),
        ("Book vs source spread",    "big_number_total",        kpi("spread_price",     DS)),
        ("Revenue per mile",        "big_number_total",        kpi("revenue_per_mile", DS)),
        ("Cost per mile",          "big_number_total",        kpi("cost_per_mile",    DS)),
        ("PnL per mile",            "big_number_total",        kpi("pnl_per_mile",     DS)),
        ("Monthly revenue vs cost",  "echarts_timeseries_bar",  bar(["total_revenue","total_cost"],"USD",DS,y_fmt="$,.0f")),
        ("Monthly PnL trend",   "echarts_timeseries_bar",  bar(["total_pnl"],"USD",DS,color_scheme="supersetColors",y_fmt="$,.0f")),
    ], rows=[([0,1,2,3], 25), ([4,5,6], 25), ([7,8,9], 25), ([10,11], 35)], existing_dash_titles=existing_titles, ds_id=ds_id)

    # ── Carrier performance ─────────────────────────────────────────────────
    create_dashboard(session, "Carrier Performance", [
        ("On-time to pickup %",          "big_number_total",        kpi("on_time_pickup_rate",   DS)),
        ("On-time to delivery %",        "big_number_total",        kpi("on_time_delivery_rate", DS)),
        ("On-time overall %",            "big_number_total",        kpi("on_time_overall_rate",  DS)),
        ("% VIP carrier loads",         "big_number_total",        kpi("vip_carrier_rate",      DS)),
        ("Total carrier drops",               "big_number_total",        kpi("total_carrier_drops",   DS)),
        ("Pickup vs delivery gap",       "big_number_total",        kpi("on_time_delta",         DS)),
        ("Monthly on-time rates",        "echarts_timeseries_bar",  bar(["on_time_pickup_rate","on_time_delivery_rate","on_time_overall_rate"],"Rate",DS,y_fmt=".1%")),
        ("Monthly drops and VIP loads", "echarts_timeseries_bar",  bar(["total_carrier_drops","vip_carrier_loads"],"Count",DS)),
    ], rows=[([0,1,2], 25), ([3,4,5], 25), ([6,7], 35)], existing_dash_titles=existing_titles, ds_id=ds_id)

    # ── Operational autonomy ─────────────────────────────────────────────────
    create_dashboard(session, "Operational Autonomy", [
        ("Autonomous bookings",              "big_number_total",       kpi("autonomously_booked",     DS)),
        ("Autonomous sourcings",             "big_number_total",       kpi("autonomously_sourced",    DS)),
        ("100% autonomous loads",           "big_number_total",       kpi("fully_autonomous_loads",  DS)),
        ("Autonomous booking rate",        "big_number_total",       kpi("autonomous_booking_rate", DS)),
        ("Autonomous sourcing rate",       "big_number_total",       kpi("autonomous_sourcing_rate",DS)),
        ("Human intervention rate",      "big_number_total",       kpi("human_intervention_rate", DS)),
        ("Autonomy rate trend", "echarts_timeseries_bar", bar(["autonomous_booking_rate","autonomous_sourcing_rate","fully_autonomous_rate"],"Rate",DS,y_fmt=".1%")),
        ("Autonomous loads vs intervention", "echarts_timeseries_bar", bar(["fully_autonomous_loads","autonomously_booked","autonomously_sourced"],"Loads",DS)),
    ], rows=[([0,1,2], 25), ([3,4,5], 25), ([6,7], 35)], existing_dash_titles=existing_titles, ds_id=ds_id)

    # ── Tracking & visibility ───────────────────────────────────────────────
    create_dashboard(session, "Tracking & Visibility", [
        ("Mobile app coverage %",       "big_number_total",       kpi("mobile_tracking_rate",     DS)),
        ("Macropoint coverage %",       "big_number_total",       kpi("macropoint_tracking_rate", DS)),
        ("EDI coverage %",              "big_number_total",       kpi("edi_tracking_rate",        DS)),
        ("Total coverage %",            "big_number_total",       kpi("total_tracking_coverage",  DS)),
        ("Loads with any tracking",    "big_number_total",       kpi("any_tracked",              DS)),
        ("Loads with no tracking %",        "big_number_total",       kpi("blind_shipment_rate",      DS)),
        ("Monthly tracking coverage", "echarts_timeseries_bar", bar(["mobile_tracking_rate","macropoint_tracking_rate","edi_tracking_rate","total_tracking_coverage"],"Rate",DS,y_fmt=".1%")),
        ("Tracked vs blind loads",   "echarts_timeseries_bar", bar(["any_tracked","mobile_tracked","macropoint_tracked","edi_tracked"],"Count",DS)),
    ], rows=[([0,1,2,3], 25), ([4,5], 25), ([6,7], 35)], existing_dash_titles=existing_titles, ds_id=ds_id)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("=" * 50)
    print("  Superset Bootstrap — Loadsmart Case")
    print("=" * 50)

    wait_for_superset()
    if os.getenv("AIRFLOW_WEBSERVER_INTERNAL", "").strip():
        wait_for_airflow_pipeline()
    else:
        wait_for_duckdb()
    session = get_session()

    db_id = setup_connection(session)
    ds_ids = setup_datasets(session, db_id)

    main_ds_id = ds_ids["fct_shipments"]
    setup_metrics(session, main_ds_id)
    setup_dashboards(session, main_ds_id)

    print("\n" + "=" * 50)
    print(f"  ✓ Bootstrap complete → {BASE}")
    print("=" * 50)


if __name__ == "__main__":
    main()
