# Runbook — Create Superset metrics via API

## Context

Metrics in Superset are SQL aggregate expressions attached to a dataset.
They are available on all charts using that dataset.

This runbook documents patterns discovered empirically on Superset **6.0.1**.

---

## Prerequisites

- Superset running at `http://localhost:8088`
- Dataset already created (see `rbk002-superset-datasets.md`)
- Python with `requests` installed

---

## Known pitfalls

| Issue | Cause | Solution |
|---|---|---|
| `422 — One or more metrics already exist` | Payload includes `created_on`, `changed_on`, `uuid` from existing metrics | Filter to allowed fields only before PUT |
| `400 — The CSRF session token is missing` | Request without CSRF or session cookies | Use `requests.Session()` and fetch token before PUT |
| `422 — Unknown field` | Fields like `currency` not accepted on PUT | Use only fields in the `ALLOWED` list below |

---

## Allowed fields in metric payload

```python
ALLOWED = {"id", "metric_name", "expression", "metric_type", "verbose_name",
           "d3format", "description", "warning_text", "extra"}
```

> **Critical rule:** existing metrics must include the `id` field.
> New metrics must not include `id`.
> Omitting `id` on an existing metric makes Superset try to recreate it and fail.

---

## Authentication pattern

```python
import requests

BASE = "http://localhost:8088"

session = requests.Session()

# 1. Login — Bearer token
token = session.post(f"{BASE}/api/v1/security/login", json={
    "username": "admin",
    "password": "admin",
    "provider": "db"
}).json()["access_token"]

session.headers.update({"Authorization": f"Bearer {token}"})

# 2. CSRF — required for any mutation (POST/PUT/DELETE)
csrf_token = session.get(f"{BASE}/api/v1/security/csrf_token/").json()["result"]
session.headers.update({
    "X-CSRFToken": csrf_token,
    "Content-Type": "application/json"
})
```

---

## Add metrics to an existing dataset

```python
DATASET_ID = 1  # adjust as needed
ALLOWED = {"id", "metric_name", "expression", "metric_type", "verbose_name",
           "d3format", "description", "warning_text", "extra"}

# 1. Fetch existing metrics and strip disallowed fields
raw = session.get(f"{BASE}/api/v1/dataset/{DATASET_ID}").json()["result"]["metrics"]
metrics = [{k: v for k, v in m.items() if k in ALLOWED} for m in raw]

existing_names = {m["metric_name"] for m in metrics}

# 2. Define new metrics
new_metrics = [
    {
        "metric_name": "total_loads",
        "expression": "COUNT(loadsmart_id)",
        "metric_type": "count",
        "verbose_name": "Total loads",
        "d3format": ",d",
        "description": "Total number of loads in the period"
    },
    {
        "metric_name": "cancellation_rate",
        "expression": "SUM(CAST(load_was_cancelled AS INT)) * 1.0 / COUNT(*)",
        "metric_type": "expr",
        "verbose_name": "Cancellation rate",
        "d3format": ".1%",
        "description": "% of cancelled loads"
    },
]

# 3. Append only those that do not exist
for m in new_metrics:
    if m["metric_name"] not in existing_names:
        metrics.append(m)

# 4. PUT — replaces the full metric list for the dataset
r = session.put(f"{BASE}/api/v1/dataset/{DATASET_ID}", json={"metrics": metrics})
assert r.status_code == 200, f"Error: {r.status_code} {r.text}"
print(f"Metrics saved. Total: {len(metrics)}")
```

---

## Reference fields by metric type

| Type | `metric_type` | Suggested `d3format` |
|---|---|---|
| Simple count | `count` | `,d` |
| Sum | `sum` | `,.2f` |
| Average | `avg` | `,.2f` |
| Proportion / rate | `expr` | `.1%` |
| Money ratio | `expr` | `$,.2f` |

---

## Verify created metrics

```python
result = session.get(f"{BASE}/api/v1/dataset/{DATASET_ID}").json()["result"]
for m in result["metrics"]:
    print(f"  [{m['id']}] {m['metric_name']:30} {m['expression']}")
```

---

## Domains and Loadsmart project metrics

See full table in [README.md — Calculated metrics](../../README.md#metrics-and-dashboards-superset).

| Domain | Count | Owner |
|---|---|---|
| Financial | 12 | CFO / Pricing |
| Volume / Funnel | 9 | Ops Manager / Product |
| Carrier | 11 | Ops Manager |
| Automation | 7 | Product |
| Tracking | 9 | Product |
