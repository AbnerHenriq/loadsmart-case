# Runbook — Implementar Dashboard no Superset

Você é um Analytics Engineer implementando um novo dashboard no Superset.
Siga as etapas abaixo **em ordem**, pausando para confirmação onde indicado.

---

## ETAPA 0 — PRD

Verifique se o usuário forneceu um PRD (Product Requirements Document) ou descrição do dashboard.

- Se **forneceu** (como argumento ou mensagem anterior): extraia objetivo, audiência, métricas esperadas e granularidade temporal.
- Se **não forneceu**: pergunte antes de continuar:
  > "Para criar o dashboard, preciso de um PRD ou descrição. Me informe: (1) objetivo do dashboard, (2) quem vai usar, (3) quais perguntas ele deve responder, (4) filtros ou granularidade desejada."

Não avance para a Etapa 1 sem ter as respostas acima.

---

## ETAPA 1 — Brainstorm de Métricas

Com base no PRD, liste:

1. **O que o dashboard deve responder** — 3 a 5 perguntas de negócio objetivas.
2. **Métricas candidatas** — nome `snake_case`, SQL expression usando colunas de `fct_shipments`, formato (`d3format`) e tipo (`count`, `sum`, `avg`, `expr`).
3. **Dimensões de análise** — colunas para agrupamento (ex: `carrier_name`, `EQUIPMENT_TYPE`, `DELIVERED_AT`).
4. **Tipos de chart** — para cada métrica, qual visualização faz mais sentido (KPI, barra temporal, donut, barra horizontal).

Apresente esse brainstorm ao usuário antes de continuar. Aguarde aprovação.

---

## ETAPA 2 — Validar Colunas e Métricas Disponíveis no Superset

> **OBRIGATÓRIO antes de qualquer implementação.** Colunas e métricas inexistentes no
> dataset causam "Data error" em runtime — o chart é criado sem erro, mas falha ao renderizar.

### 2a — Listar colunas reais do dataset

```python
result = session.get(f"{BASE}/api/v1/dataset/1").json()["result"]
cols = sorted([c["column_name"] for c in result.get("columns", [])])
print("Colunas disponíveis:", cols)
```

> **Atenção:** colunas do Superset podem estar em UPPERCASE (`LANE_RAW`, `PICKUP_STATE`,
> `DELIVERED_AT`) mesmo que o SQL original use lowercase. Sempre use o nome **exato**
> retornado pela API — nunca assuma case pela leitura do modelo dbt.

Compare cada coluna de dimensão planejada no brainstorm com a lista acima. Se não existir:
- A coluna não foi exposta no dataset virtual → sincronize via `PUT /api/v1/dataset/{id}/refresh`
- Ou o nome está em case diferente → use o nome exato da API

### 2b — Verificar Métricas Existentes no Superset

Autentique no Superset e inspecione o dataset `fct_shipments` (id=1):

```python
# Referência: docs/runbooks/rbk003-superset-metrics.md — Padrão de autenticação
import requests, json

BASE = "http://localhost:8088"
session = requests.Session()
token = session.post(f"{BASE}/api/v1/security/login",
    json={"username": "admin", "password": "admin", "provider": "db"}
).json()["access_token"]
session.headers.update({"Authorization": f"Bearer {token}"})
csrf = session.get(f"{BASE}/api/v1/security/csrf_token/").json()["result"]
session.headers.update({"X-CSRFToken": csrf, "Content-Type": "application/json"})

# Listar métricas existentes
result = session.get(f"{BASE}/api/v1/dataset/1").json()["result"]
existing = {m["metric_name"]: m["id"] for m in result["metrics"]}
print(json.dumps(list(existing.keys()), indent=2))
```

Monte uma tabela comparando:

| Métrica (PRD) | Existe? | ID (se sim) | Ação |
|---|---|---|---|
| `total_loads` | ✓ | 3 | — |
| `nova_metrica` | ✗ | — | Criar |

---

## ETAPA 3 — Criar Métricas Faltantes (se houver)

Se alguma métrica não existe, crie-a via PUT no dataset.

**Regra crítica** (ver `docs/runbooks/rbk003-superset-metrics.md`):
- Montar payload com **todas as métricas existentes** (com seus `id`s) + as novas (sem `id`)
- Usar apenas os campos: `id`, `metric_name`, `expression`, `metric_type`, `verbose_name`, `d3format`, `description`, `warning_text`, `extra`
- Enviar como PUT completo — Superset substitui a lista inteira

```python
ALLOWED = {"id", "metric_name", "expression", "metric_type", "verbose_name",
           "d3format", "description", "warning_text", "extra"}

raw = session.get(f"{BASE}/api/v1/dataset/1").json()["result"]["metrics"]
existing_metrics = [{k: v for k, v in m.items() if k in ALLOWED} for m in raw]

new_metrics = [
    # adicione aqui apenas as métricas do PRD que não existem
    {
        "metric_name": "exemplo_metrica",
        "expression": "COUNT(*)",
        "metric_type": "count",
        "verbose_name": "Exemplo",
        "d3format": ",d",
    },
]

all_metrics = existing_metrics + new_metrics
r = session.put(f"{BASE}/api/v1/dataset/1", json={"metrics": all_metrics})
print(r.status_code, r.text[:200])
```

Após criar, **documente** as novas métricas adicionando-as à tabela em `docs/runbooks/rbk003-superset-metrics.md` (seção "Domínios e métricas do projeto Loadsmart").

Se nenhuma métrica nova foi necessária, pule para a Etapa 4.

---

## ETAPA 4 — Confirmar Plano do Dashboard

**Pause aqui e apresente ao usuário:**

```
Dashboard: <título>
Audiência: <quem vai usar>

Charts planejados:
  Linha 1: [KPI Total Cargas] [KPI Taxa X] [KPI Taxa Y]   ← 3 colunas
  Linha 2: [Evolução Mensal — barra temporal]               ← largura total
  Linha 3: [Top Carriers — barra horiz] [Distribuição — donut]  ← 2 colunas

Métricas usadas: total_loads, taxa_x, taxa_y, ...
Dataset: fct_shipments (id=1)

Confirma? (s/n)
```

Só avance para a Etapa 5 após confirmação explícita do usuário.

---

## ETAPA 5 — Criar Dashboard

Siga o fluxo completo de `docs/runbooks/rbk004-superset-dashboards.md`:

### 5.1 — Verificar se o dashboard já existe

```python
r = session.get(f"{BASE}/api/v1/dashboard/?q=(page_size:50)")
existing_titles = {d["dashboard_title"] for d in r.json().get("result", [])}
if "<título>" in existing_titles:
    print("Dashboard já existe — pulando criação")
```

### 5.2 — Criar charts

Use `POST /api/v1/chart/` para cada chart. Referência de params mínimos por tipo:

**KPI (`big_number_total`):**
```python
{
    "viz_type": "big_number_total",
    "datasource": "1__table",
    "metric": "nome_metrica",
    "time_range": "No filter",
    "header_font_size": 0.3,
    "subheader_font_size": 0.125,
}
```

**Barra temporal (`echarts_timeseries_bar`):**
```python
{
    "viz_type": "echarts_timeseries_bar",
    "datasource": "1__table",
    "metrics": ["nome_metrica"],
    "x_axis": "DELIVERED_AT",
    "time_grain_sqla": "P1M",
    "time_range": "No filter",
    "x_axis_time_format": "%b/%Y",
    "color_scheme": "d3Category10",
}
```

**Ranking / breakdown por dimensão (`table`):**
```python
# ← NÃO usar "bar" nem "echarts_bar" — plugins não carregados no build apache/superset:latest 6.0.1
# A API aceita esses viz_types (retorna 201), mas o frontend quebra com "Item with key X is not registered"
# Usar "table" para qualquer chart agrupado por dimensão (groupby)
{
    "viz_type": "table",
    "datasource": "1__table",
    "metrics": ["metrica_principal", "metrica_secundaria"],
    "groupby": ["COLUNA_DIM"],       # ← UPPERCASE conforme retornado pela API
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
    "metric": "nome_metrica",
    "groupby": ["coluna_dim"],
    "time_range": "No filter",
    "donut": True,
    "color_scheme": "d3Category10",
}
```

### 5.3 — Criar dashboard vazio

```python
r = session.post(f"{BASE}/api/v1/dashboard/", json={
    "dashboard_title": "<título>",
    "published": True,
})
dash_id = r.json()["id"]
```

### 5.4 — Vincular charts ao dashboard

```python
# OBRIGATÓRIO — sem isso os charts aparecem em branco no dashboard
for cid in chart_ids:
    session.put(f"{BASE}/api/v1/chart/{cid}", json={"dashboards": [dash_id]})
```

### 5.5 — Aplicar layout

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

# rows: lista de listas com os chart_ids, na ordem visual do dashboard
session.put(f"{BASE}/api/v1/dashboard/{dash_id}", json={
    "position_json": build_position_json(rows),
    "json_metadata": json.dumps({"refresh_frequency": 0}),
})
```

---

## ETAPA 6 — Validar

Após criar o dashboard:

1. Abra `http://localhost:8088` e navegue até o dashboard.
2. Verifique que **todos os charts renderizam** (sem "Data error" ou "Metric does not exist").
3. Se algum chart falhar, confirme:
   - A métrica existe no dataset (`GET /api/v1/dataset/1`)
   - O `datasource_id` no chart bate com o id real do dataset
   - O chart foi vinculado ao dashboard (etapa 5.4)

---

## Armadilhas críticas (resumo)

| Problema | Causa | Fix |
|---|---|---|
| "Metric does not exist" | `datasource_id` errado no chart | Sempre usar o id real do dataset |
| Charts em branco | Chart não vinculado ao dashboard | PUT em cada chart com `{"dashboards": [dash_id]}` |
| `422` ao criar métricas | Payload sem `id` de métricas existentes | Buscar existentes com `id`, merging correto |
| Dashboard duplicado | Script não checa existência | `GET /dashboard/` e comparar títulos antes do POST |

---

## Referências

- [rbk003-superset-metrics.md](docs/runbooks/rbk003-superset-metrics.md) — criação e validação de métricas
- [rbk004-superset-dashboards.md](docs/runbooks/rbk004-superset-dashboards.md) — fluxo completo de charts e layout
- [rbk001-superset-connections.md](docs/runbooks/rbk001-superset-connections.md) — gerenciar conexões de database
- [rbk002-superset-datasets.md](docs/runbooks/rbk002-superset-datasets.md) — listar e criar datasets virtuais
