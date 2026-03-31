# Runbook — Create Superset dashboards via API

## Context

Superset dashboards are composed of **charts** (visualizations) organized in a
grid layout. This runbook documents the full flow discovered on **6.0.1**.

---

## Prerequisites

- Superset running at `http://localhost:8088`
- Dataset created with required metrics (see `rbk003-superset-metrics.md`)
- Python with `requests` installed

---

## Flow in 4 steps

```
1. Authenticate (Bearer + CSRF)
        ↓
2. Create charts (POST /api/v1/chart/)
        ↓
3. Create empty dashboard (POST /api/v1/dashboard/)
        ↓
4. Link charts → dashboard (PUT /api/v1/chart/{id})
        ↓
5. Apply layout (PUT /api/v1/dashboard/{id} with position_json)
```

> **Critical pitfall:** charts are NOT linked to the dashboard via `position_json`.
> The link is done via PUT on the **chart** with `{"dashboards": [dash_id]}`.
> Without it, the dashboard shows: *"There is no chart definition associated with this component"*.

---

## Authentication (same as metrics runbook)

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

## Step 2 — Create charts

```python
DATASET_ID = 1

def create_chart(title, viz_type, params):
    r = session.post(f"{BASE}/api/v1/chart/", json={
        "slice_name": title,
        "viz_type": viz_type,
        "datasource_id": DATASET_ID,
        "datasource_type": "table",
        "params": json.dumps(params),
        "description": "",
    })
    assert r.status_code == 201, f"Error creating chart '{title}': {r.text}"
    cid = r.json()["id"]
    print(f"  ✓ [{cid}] {title}")
    return cid
```

### Chart types and minimum params

**KPI — `big_number_total`**
```python
params = {
    "viz_type": "big_number_total",
    "datasource": f"{DATASET_ID}__table",
    "metric": "total_loads",          # metric name
    "subheader": "in period",        # text below number
    "time_range": "No filter",
}
```

**Time bar — `echarts_timeseries_bar`**
```python
params = {
    "viz_type": "echarts_timeseries_bar",
    "datasource": f"{DATASET_ID}__table",
    "metrics": ["total_loads"],       # metric list
    "x_axis": "DELIVERED_AT",         # datetime column for X axis
    "time_grain_sqla": "P1M",         # granularity: P1D=day, P1W=week, P1M=month
    "time_range": "No filter",
}
```

**Horizontal bar — `bar`**
```python
params = {
    "viz_type": "bar",
    "datasource": f"{DATASET_ID}__table",
    "metrics": ["on_time_overall_rate"],
    "groupby": ["carrier_name"],
    "time_range": "No filter",
    "orientation": "horizontal",
}
```

**Donut — `pie`**
```python
params = {
    "viz_type": "pie",
    "datasource": f"{DATASET_ID}__table",
    "metric": "total_loads",
    "groupby": ["EQUIPMENT_TYPE"],
    "time_range": "No filter",
    "donut": True,
}
```

---

## Step 3 — Create empty dashboard

```python
r = session.post(f"{BASE}/api/v1/dashboard/", json={
    "dashboard_title": "Volume & Operational Funnel",
    "published": True,
    "slug": "volume-funnel",           # friendly URL (unique)
})
assert r.status_code == 201, r.text
dash_id = r.json()["id"]
print(f"Dashboard created: id={dash_id}")
```

---

## Step 4 — Link charts to dashboard

```python
chart_ids = [2, 3, 4, 5, 6, 7, 8, 9]   # IDs from step 2

for cid in chart_ids:
    r = session.put(f"{BASE}/api/v1/chart/{cid}", json={"dashboards": [dash_id]})
    assert r.status_code == 200, f"Error linking chart {cid}: {r.text}"
    print(f"  ✓ chart {cid} linked")
```

---

## Step 5 — Apply layout (position_json)

Layout uses a **12-column** grid. Each chart has `width` (1–12) and `height` (units).

```python
def build_position_json(rows):
    """
    rows: list of lists of chart_ids.
    Example: [[2, 3, 4], [5, 6, 7], [8, 9]]
    → Row 1 with 3 charts width=4, Row 2 with 2 charts width=6
    """
    positions = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID":  {"type": "ROOT", "id": "ROOT_ID", "children": ["GRID_ID"]},
        "GRID_ID":  {"type": "GRID", "id": "GRID_ID",
                     "children": [f"ROW_{i+1}" for i in range(len(rows))],
                     "parents": ["ROOT_ID"]},
    }

    for row_idx, row_charts in enumerate(rows):
        row_id = f"ROW_{row_idx + 1}"
        chart_keys = [f"CHART_{cid}" for cid in row_charts]
        width = 12 // len(row_charts)           # split evenly
        height = 15 if width <= 4 else 30       # smaller KPIs, larger charts

        positions[row_id] = {
            "type": "ROW", "id": row_id,
            "children": chart_keys,
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        }
        for cid in row_charts:
            key = f"CHART_{cid}"
            positions[key] = {
                "type": "CHART", "id": key, "children": [],
                "parents": ["ROOT_ID", "GRID_ID", row_id],
                "meta": {"chartId": cid, "width": width, "height": height},
            }

    return json.dumps(positions)


# Example: 3 KPIs row 1, 3 KPIs row 2, 2 wide charts row 3
position_json = build_position_json([
    [2, 3, 4],    # row 1 — 3 KPIs (width=4 each)
    [5, 6, 7],    # row 2 — 3 KPIs (width=4 each)
    [8, 9],       # row 3 — 2 charts (width=6 each)
])

r = session.put(f"{BASE}/api/v1/dashboard/{dash_id}", json={
    "position_json": position_json,
    "json_metadata": json.dumps({"refresh_frequency": 0}),
})
assert r.status_code == 200, f"Layout error: {r.text}"
print(f"Layout applied. URL: {BASE}/superset/dashboard/{dash_id}/")
```

---

## Viz types confirmed in this build (apache/superset:latest 6.0.1)

| viz_type | Use | Status |
|---|---|---|
| `big_number_total` | Single KPI | ✓ works |
| `echarts_timeseries_bar` | Time series (x_axis + time_grain) | ✓ works |
| `pie` | Donut / pie | ✓ works |
| `table` | Ranking, top N, breakdown by dimension | ✓ works |
| `bar` | Categorical bar (legacy) | ✗ "Item with key 'bar' is not registered" |
| `echarts_bar` | Categorical bar (ECharts) | ✗ "Item with key 'echarts_bar' is not registered" |

> **Rule:** The REST API accepts any string as `viz_type` (returns 201), but the frontend fails if the plugin is not in the bundle. For charts grouped by dimension (`groupby`), use **`table`**.

---

## Known pitfalls

| Issue | Cause | Solution |
|---|---|---|
| *"There is no chart definition"* | Charts not linked to dashboard | PUT each chart with `{"dashboards": [dash_id]}` — step 4 |
| `400 — position_data Unknown field` | Wrong field in 4.x/6.x | Use `position_json`, not `position_data` |
| `position_json` ignored on POST | API does not accept layout on create | Create empty dashboard (POST) then apply layout (PUT) |
| Duplicate charts on re-run | Script creates new charts without checking | Query `/api/v1/chart/?q=...` before creating |
| CSRF missing on PUT | Session does not keep cookies | Use `requests.Session()`, not standalone `requests.put()` |
| "Item with key X is not registered" | Viz plugin not loaded in bundle | See viz type table above; use `table` for categories |
| "Columns missing in dataset" | Column name lowercase, dataset uses UPPERCASE | Validate columns via `GET /api/v1/dataset/{id}` before creating charts |

---

## Full script — quick reference

```python
# 1. auth (see above)
# 2. create charts
c1 = create_chart("Total loads",     "big_number_total",       {...})
c2 = create_chart("Monthly trend",     "echarts_timeseries_bar", {...})
# 3. create dashboard
dash_id = session.post(f"{BASE}/api/v1/dashboard/", json={...}).json()["id"]
# 4. link
for cid in [c1, c2]:
    session.put(f"{BASE}/api/v1/chart/{cid}", json={"dashboards": [dash_id]})
# 5. layout
session.put(f"{BASE}/api/v1/dashboard/{dash_id}", json={"position_json": build_position_json([[c1, c2]])})
```
