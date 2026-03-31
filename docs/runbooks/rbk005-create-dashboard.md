# Runbook — Implement a Superset dashboard

You are an Analytics Engineer implementing a new Superset dashboard.
Follow the steps below **in order**, pausing for user confirmation where indicated.

---

## STEP 0 — PRD

Check whether the user provided a PRD (Product Requirements Document) or dashboard description.

- If **provided** (as argument or in a prior message): extract goal, audience, expected metrics, and time granularity.
- If **not provided**: ask before continuing:
  > "To create the dashboard I need a PRD or description. Please provide: (1) dashboard goal, (2) who will use it, (3) what questions it should answer, (4) desired filters or granularity."

Do not proceed to Step 1 without the answers above.

---

## STEP 1 — Metric brainstorm

From the PRD, list:

1. **What the dashboard should answer** — 3 to 5 concrete business questions.
2. **Candidate metrics** — `snake_case` name, SQL expression using `fct_shipments` columns, format (`d3format`), and type (`count`, `sum`, `avg`, `expr`).
3. **Analysis dimensions** — columns for grouping (e.g. `carrier_name`, `equipment_type`, `delivered_at`).
4. **Chart types** — for each metric, which visualization fits best (KPI, time bar, donut, horizontal bar).

Present this brainstorm to the user before continuing. Wait for approval.

---

## STEP 2 — Validate columns and metrics in Superset

> **Required before any implementation.** Non-existent columns or metrics cause "Data error" at runtime — the chart is created without error but fails to render.

### 2a — List real dataset columns

```python
result = session.get(f"{BASE}/api/v1/dataset/1").json()["result"]
cols = sorted([c["column_name"] for c in result.get("columns", [])])
print("Available columns:", cols)
```

> **Note:** Use the **exact** column name returned by `GET /api/v1/dataset/{id}` (this
> project’s `mart/` models expose `snake_case`). Never assume names from memory alone.

Compare each planned dimension column with the list above. If missing:
- The column was not exposed on the virtual dataset → sync via `PUT /api/v1/dataset/{id}/refresh`
- Or the name differs in case → use the exact API name

### 2b — Check existing metrics in Superset

Authenticate and inspect dataset `fct_shipments` (id=1):

```python
# Reference: docs/runbooks/rbk003-superset-metrics.md — Authentication pattern
import requests, json

BASE = "http://localhost:8088"
session = requests.Session()
token = session.post(f"{BASE}/api/v1/security/login",
    json={"username": "admin", "password": "admin", "provider": "db"}
).json()["access_token"]
session.headers.update({"Authorization": f"Bearer {token}"})
csrf = session.get(f"{BASE}/api/v1/security/csrf_token/").json()["result"]
session.headers.update({"X-CSRFToken": csrf, "Content-Type": "application/json"})

# List existing metrics
result = session.get(f"{BASE}/api/v1/dataset/1").json()["result"]
existing = {m["metric_name"]: m["id"] for m in result["metrics"]}
print(json.dumps(list(existing.keys()), indent=2))
```

Build a comparison table:

| Metric (PRD) | Exists? | ID (if yes) | Action |
|---|---|---|---|
| `total_loads` | ✓ | 3 | — |
| `new_metric` | ✗ | — | Create |

---

## STEP 3 — Create missing metrics (if any)

If a metric does not exist, create it via PUT on the dataset.

**Critical rule** (see `docs/runbooks/rbk003-superset-metrics.md`):
- Build payload with **all existing metrics** (with their `id`s) + new ones (no `id`)
- Use only: `id`, `metric_name`, `expression`, `metric_type`, `verbose_name`, `d3format`, `description`, `warning_text`, `extra`
- Send as full PUT — Superset replaces the entire list

```python
ALLOWED = {"id", "metric_name", "expression", "metric_type", "verbose_name",
           "d3format", "description", "warning_text", "extra"}

raw = session.get(f"{BASE}/api/v1/dataset/1").json()["result"]["metrics"]
existing_metrics = [{k: v for k, v in m.items() if k in ALLOWED} for m in raw]

new_metrics = [
    # add only PRD metrics that do not exist yet
    {
        "metric_name": "example_metric",
        "expression": "COUNT(*)",
        "metric_type": "count",
        "verbose_name": "Example",
        "d3format": ",d",
    },
]

all_metrics = existing_metrics + new_metrics
r = session.put(f"{BASE}/api/v1/dataset/1", json={"metrics": all_metrics})
print(r.status_code, r.text[:200])
```

After creating, **document** new metrics by adding them to the table in `docs/runbooks/rbk003-superset-metrics.md` (section "Domains and Loadsmart project metrics").

If no new metrics were needed, skip to Step 4.

---

## STEP 4 — Confirm dashboard plan

**Pause and present to the user:**

```
Dashboard: <title>
Audience: <who will use it>

Planned charts:
  Row 1: [KPI Total loads] [KPI Rate X] [KPI Rate Y]   ← 3 columns
  Row 2: [Monthly trend — time bar]               ← full width
  Row 3: [Top carriers — horizontal bar] [Distribution — donut]  ← 2 columns

Metrics used: total_loads, rate_x, rate_y, ...
Dataset: fct_shipments (id=1)

Confirm? (y/n)
```

Proceed to Step 5 only after explicit user confirmation.

---

## STEP 5 — Create dashboard

Follow the full flow in `docs/runbooks/rbk004-superset-dashboards.md`:

### 5.1 — Check if dashboard already exists

```python
r = session.get(f"{BASE}/api/v1/dashboard/?q=(page_size:50)")
existing_titles = {d["dashboard_title"] for d in r.json().get("result", [])}
if "<title>" in existing_titles:
    print("Dashboard already exists — skipping creation")
```

### 5.2 — Create charts

Use `POST /api/v1/chart/` for each chart. Minimum params by type:

**KPI (`big_number_total`):**
```python
{
    "viz_type": "big_number_total",
    "datasource": "1__table",
    "metric": "metric_name",
    "time_range": "No filter",
    "header_font_size": 0.3,
    "subheader_font_size": 0.125,
}
```

**Time bar (`echarts_timeseries_bar`):**
```python
{
    "viz_type": "echarts_timeseries_bar",
    "datasource": "1__table",
    "metrics": ["metric_name"],
    "x_axis": "delivered_at",
    "time_grain_sqla": "P1M",
    "time_range": "No filter",
    "x_axis_time_format": "%b/%Y",
    "color_scheme": "d3Category10",
}
```

**Ranking / breakdown by dimension (`table`):**
```python
# ← Do NOT use "bar" or "echarts_bar" — plugins not loaded in apache/superset:latest 6.0.1
# The API accepts those viz_types (201) but the frontend throws "Item with key X is not registered"
# Use "table" for any chart grouped by dimension (groupby)
{
    "viz_type": "table",
    "datasource": "1__table",
    "metrics": ["primary_metric", "secondary_metric"],
    "groupby": ["dim_column"],       # ← exact name as returned by API (here: snake_case)
    "time_range": "No filter",
    "row_limit": 10,
    "page_length": 10,
}
```

**Donut (`pie`):**
```python
{
    "viz_type": "pie",
    "datasource": "1__table",
    "metric": "metric_name",
    "groupby": ["dim_column"],
    "time_range": "No filter",
    "donut": True,
    "color_scheme": "d3Category10",
}
```

### 5.3 — Create empty dashboard

```python
r = session.post(f"{BASE}/api/v1/dashboard/", json={
    "dashboard_title": "<title>",
    "published": True,
})
dash_id = r.json()["id"]
```

### 5.4 — Link charts to dashboard

```python
# REQUIRED — without this charts appear blank on the dashboard
for cid in chart_ids:
    session.put(f"{BASE}/api/v1/chart/{cid}", json={"dashboards": [dash_id]})
```

### 5.5 — Apply layout

```python
def build_position_json(rows):
    positions = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {"type": "ROOT", "id": "ROOT_ID", "children": ["GRID_ID"]},
        "GRID_ID": {"type": "GRID", "id": "GRID_ID",
                    "children": [f"ROW_{i+1}" for i in range(len(rows))],
                    "parents": ["ROOT_ID"]},
    }
    for row_idx, row_charts in enumerate(rows):
        row_id = f"ROW_{row_idx + 1}"
        width = 12 // len(row_charts)
        height = 15 if width <= 4 else 30
        positions[row_id] = {
            "type": "ROW", "id": row_id,
            "children": [f"CHART_{cid}" for cid in row_charts],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        }
        for cid in row_charts:
            positions[f"CHART_{cid}"] = {
                "type": "CHART", "id": f"CHART_{cid}", "children": [],
                "parents": ["ROOT_ID", "GRID_ID", row_id],
                "meta": {"chartId": cid, "width": width, "height": height},
            }
    return json.dumps(positions)

# rows: list of lists of chart_ids, in visual order
session.put(f"{BASE}/api/v1/dashboard/{dash_id}", json={
    "position_json": build_position_json(rows),
    "json_metadata": json.dumps({"refresh_frequency": 0}),
})
```

---

## STEP 6 — Validate

After creating the dashboard:

1. Open `http://localhost:8088` and navigate to the dashboard.
2. Verify **all charts render** (no "Data error" or "Metric does not exist").
3. If any chart fails, confirm:
   - The metric exists on the dataset (`GET /api/v1/dataset/1`)
   - The chart `datasource_id` matches the real dataset id
   - The chart was linked to the dashboard (step 5.4)

---

## Critical pitfalls (summary)

| Issue | Cause | Fix |
|---|---|---|
| "Metric does not exist" | Wrong `datasource_id` on chart | Always use real dataset id |
| Blank charts | Chart not linked to dashboard | PUT each chart with `{"dashboards": [dash_id]}` |
| `422` when creating metrics | Payload missing `id` for existing metrics | Fetch existing with `id`, merge correctly |
| Duplicate dashboard | Script does not check existence | `GET /dashboard/` and compare titles before POST |

---

## References

- [rbk003-superset-metrics.md](docs/runbooks/rbk003-superset-metrics.md) — metric creation and validation
- [rbk004-superset-dashboards.md](docs/runbooks/rbk004-superset-dashboards.md) — full chart and layout flow
- [rbk001-superset-connections.md](docs/runbooks/rbk001-superset-connections.md) — manage database connections
- [rbk002-superset-datasets.md](docs/runbooks/rbk002-superset-datasets.md) — list and create virtual datasets
