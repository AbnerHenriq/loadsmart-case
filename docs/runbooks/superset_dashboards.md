# Runbook — Criar Dashboards no Superset via API

## Contexto

Dashboards no Superset são compostos por **charts** (visualizações) organizados em um
layout de grid. Este runbook documenta o fluxo completo descoberto na versão **6.0.1**.

---

## Pré-requisitos

- Superset rodando em `http://localhost:8088`
- Dataset criado com as métricas necessárias (ver `superset_metrics.md`)
- Python com `requests` instalado

---

## Fluxo em 4 etapas

```
1. Autenticar (Bearer + CSRF)
        ↓
2. Criar charts (POST /api/v1/chart/)
        ↓
3. Criar dashboard vazio (POST /api/v1/dashboard/)
        ↓
4. Vincular charts → dashboard (PUT /api/v1/chart/{id})
        ↓
5. Aplicar layout (PUT /api/v1/dashboard/{id} com position_json)
```

> **Armadilha crítica:** charts NÃO se vinculam ao dashboard pelo `position_json`.
> O vínculo é feito via PUT no **chart** com `{"dashboards": [dash_id]}`.
> Sem isso, o dashboard exibe: *"There is no chart definition associated with this component"*.

---

## Autenticação (igual ao runbook de métricas)

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

## Etapa 2 — Criar charts

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
    assert r.status_code == 201, f"Erro ao criar chart '{title}': {r.text}"
    cid = r.json()["id"]
    print(f"  ✓ [{cid}] {title}")
    return cid
```

### Tipos de chart e seus params mínimos

**KPI — `big_number_total`**
```python
params = {
    "viz_type": "big_number_total",
    "datasource": f"{DATASET_ID}__table",
    "metric": "total_loads",          # nome da métrica
    "subheader": "no período",        # texto abaixo do número
    "time_range": "No filter",
}
```

**Barra temporal — `echarts_timeseries_bar`**
```python
params = {
    "viz_type": "echarts_timeseries_bar",
    "datasource": f"{DATASET_ID}__table",
    "metrics": ["total_loads"],       # lista de métricas
    "x_axis": "DELIVERED_AT",         # coluna datetime para o eixo X
    "time_grain_sqla": "P1M",         # granularidade: P1D=dia, P1W=semana, P1M=mês
    "time_range": "No filter",
}
```

**Barra horizontal — `bar`**
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

## Etapa 3 — Criar dashboard vazio

```python
r = session.post(f"{BASE}/api/v1/dashboard/", json={
    "dashboard_title": "Volume & Funil Operacional",
    "published": True,
    "slug": "volume-funil",           # URL amigável (único)
})
assert r.status_code == 201, r.text
dash_id = r.json()["id"]
print(f"Dashboard criado: id={dash_id}")
```

---

## Etapa 4 — Vincular charts ao dashboard

```python
chart_ids = [2, 3, 4, 5, 6, 7, 8, 9]   # IDs retornados no passo 2

for cid in chart_ids:
    r = session.put(f"{BASE}/api/v1/chart/{cid}", json={"dashboards": [dash_id]})
    assert r.status_code == 200, f"Erro ao vincular chart {cid}: {r.text}"
    print(f"  ✓ chart {cid} vinculado")
```

---

## Etapa 5 — Aplicar layout (position_json)

O layout usa um grid de **12 colunas**. Cada chart tem `width` (1–12) e `height` (unidades).

```python
def build_position_json(rows):
    """
    rows: lista de listas de chart_ids.
    Exemplo: [[2, 3, 4], [5, 6, 7], [8, 9]]
    → Linha 1 com 3 charts de width=4, Linha 2 com 2 charts de width=6
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
        width = 12 // len(row_charts)           # divide igualmente
        height = 15 if width <= 4 else 30       # KPIs menores, charts maiores

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


# Exemplo: 3 KPIs na linha 1, 3 KPIs na linha 2, 2 charts largos na linha 3
position_json = build_position_json([
    [2, 3, 4],    # linha 1 — 3 KPIs (width=4 cada)
    [5, 6, 7],    # linha 2 — 3 KPIs (width=4 cada)
    [8, 9],       # linha 3 — 2 charts (width=6 cada)
])

r = session.put(f"{BASE}/api/v1/dashboard/{dash_id}", json={
    "position_json": position_json,
    "json_metadata": json.dumps({"refresh_frequency": 0}),
})
assert r.status_code == 200, f"Erro no layout: {r.text}"
print(f"Layout aplicado. URL: {BASE}/superset/dashboard/{dash_id}/")
```

---

## Armadilhas conhecidas

| Problema | Causa | Solução |
|---|---|---|
| *"There is no chart definition"* | Charts não vinculados ao dashboard | PUT em cada chart com `{"dashboards": [dash_id]}` — etapa 4 |
| `400 — position_data Unknown field` | Campo errado na versão 4.x/6.x | Usar `position_json`, não `position_data` |
| `position_json` ignorado no POST | API não aceita layout na criação | Criar dashboard vazio (POST) e depois aplicar layout (PUT) |
| Charts duplicados ao re-rodar | Script cria novos charts sem verificar existência | Verificar `/api/v1/chart/?q=...` antes de criar |
| CSRF missing no PUT | Sessão não mantém cookies | Usar `requests.Session()`, não `requests.put()` avulso |

---

## Script completo — referência rápida

```python
# 1. auth (ver acima)
# 2. criar charts
c1 = create_chart("Total de Cargas",     "big_number_total",       {...})
c2 = create_chart("Evolução Mensal",     "echarts_timeseries_bar", {...})
# 3. criar dashboard
dash_id = session.post(f"{BASE}/api/v1/dashboard/", json={...}).json()["id"]
# 4. vincular
for cid in [c1, c2]:
    session.put(f"{BASE}/api/v1/chart/{cid}", json={"dashboards": [dash_id]})
# 5. layout
session.put(f"{BASE}/api/v1/dashboard/{dash_id}", json={"position_json": build_position_json([[c1, c2]])})
```
