# Runbook — Create and copy virtual Superset datasets via API

## Context

Superset datasets can be **physical** (point directly to a table) or
**virtual** (defined by custom SQL). Virtual datasets allow JOINs,
fixed filters, and transformations without changing the database.

This runbook covers:
1. List and inspect existing datasets
2. Create a virtual dataset from scratch
3. Copy an existing dataset with an extra filter (e.g. active loads only)

Patterns discovered empirically on Superset **6.0.1** with DuckDB.

---

## Prerequisites

- Superset running at `http://localhost:8088`
- Database already connected (see DuckDB connection in README)
- Python with `requests` installed

---

## Authentication

```python
import requests, json

BASE = "http://localhost:8088"
session = requests.Session()

token = session.post(f"{BASE}/api/v1/security/login", json={
    "username": "admin", "password": "admin", "provider": "db"
}).json()["access_token"]

session.headers.update({"Authorization": f"Bearer {token}"})
csrf_token = session.get(f"{BASE}/api/v1/security/csrf_token/").json()["result"]
session.headers.update({"X-CSRFToken": csrf_token, "Content-Type": "application/json"})
```

---

## 1. List datasets and detect virtual vs physical

```python
r = session.get(f"{BASE}/api/v1/dataset/?q=(page_size:20)")
for ds in r.json().get("result", []):
    tipo = "virtual" if ds.get("sql") else "physical"
    print(f"id={ds['id']}  [{tipo}]  {ds['table_name']}  schema={ds.get('schema')}")
```

A dataset is **virtual** when the `sql` field is set.

---

## 2. Inspect a full dataset

```python
r = session.get(f"{BASE}/api/v1/dataset/1")
ds = r.json()["result"]

print("SQL:", ds.get("sql"))
print("Columns:", [c["column_name"] for c in ds["columns"]])
print("Metrics:", [m["metric_name"] for m in ds["metrics"]])
```

---

## 3. Create virtual dataset from scratch

```python
# Discover database id
r = session.get(f"{BASE}/api/v1/database/?q=(page_size:10)")
for db in r.json()["result"]:
    print(f"id={db['id']}  {db['database_name']}")

DATABASE_ID = 1  # adjust to DuckDB id

r = session.post(f"{BASE}/api/v1/dataset/", json={
    "database": DATABASE_ID,
    "table_name": "my_dataset",
    "schema": "loadsmart.main_mart",   # database schema (optional)
    "sql": """
        SELECT f.*, dc.carrier_name
        FROM main_mart.fct_shipments f
        LEFT JOIN main_mart.dim_carrier dc ON f.carrier_sk = dc.carrier_sk
        WHERE f.load_was_cancelled = false
    """,
})

new_id = r.json()["id"]
print(f"Dataset created: id={new_id}")
```

> **Note:** do not send `columns` or `metrics` in POST — Superset returns
> `400 Unknown field`. Add them later via PUT (see section 5).

---

## 4. Copy existing dataset with extra filter

Pattern for a “filtered view” of an already configured dataset,
preserving all metrics.

```python
DATASET_ID = 1  # original dataset

# 1. Fetch original
ds = session.get(f"{BASE}/api/v1/dataset/{DATASET_ID}").json()["result"]

# 2. Build SQL with extra filter
sql_filtered = ds["sql"].rstrip().rstrip(";") + "\nWHERE f.load_was_cancelled = false"
# If original SQL already has WHERE, use AND instead of WHERE

# 3. Create new dataset (no columns/metrics in POST)
r = session.post(f"{BASE}/api/v1/dataset/", json={
    "database": ds["database"]["id"],
    "table_name": "fct_shipments_active",
    "schema": ds.get("schema"),
    "sql": sql_filtered,
})
new_id = r.json()["id"]
print(f"Dataset created: id={new_id}")

# 4. Copy metrics from original
ALLOWED_MET = {
    "metric_name", "expression", "metric_type", "verbose_name",
    "d3format", "description", "warning_text", "extra"
}
metrics = [{k: v for k, v in m.items() if k in ALLOWED_MET} for m in ds["metrics"]]

r = session.put(f"{BASE}/api/v1/dataset/{new_id}", json={"metrics": metrics})
print(f"Metrics copied: {len(metrics)}")

# 5. Sync columns (introspect)
session.put(f"{BASE}/api/v1/dataset/{new_id}/refresh")
print("Columns synced")
```

---

## 5. Add metrics to an existing dataset

See runbook `rbk003-superset-metrics.md` for the full pattern.
Key point: always GET existing metrics, filter to `ALLOWED_MET`,
and send everything together in PUT (not only new ones).

---

## Datasets in this project

| id | Name | Type | Filter |
|----|------|------|--------|
| 1 | `fct_shipments` | virtual | all loads |
| 2 | `fct_shipments_active` | virtual | `load_was_cancelled = false` |

To reference a dataset in chart params, use `"{id}__table"`:

```python
# Full dataset
"datasource": "1__table"

# Active loads only
"datasource": "2__table"
```

---

## Known pitfalls

| Pitfall | Cause | Fix |
|---------|-------|-----|
| `400 — columns: Unknown field` | `columns`/`metrics` in POST payload | Send only in PUT after creation |
| Dataset created but no columns | Superset does not auto-introspect | Call `PUT /api/v1/dataset/{id}/refresh` |
| SQL with subquery fails | DuckDB requires alias on subquery | `SELECT * FROM (SELECT ...) AS sub` |
| Wrong schema in DuckDB | DuckDB uses `schema.database` inverted vs Postgres | Use `main_mart.table` directly in SQL, not the `schema` field |
