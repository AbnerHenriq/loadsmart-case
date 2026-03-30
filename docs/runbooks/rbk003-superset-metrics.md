# Runbook — Criar Métricas no Superset via API

## Contexto

Métricas no Superset são expressões SQL agregadas vinculadas a um dataset.
Elas ficam disponíveis em todos os charts que usam aquele dataset.

Este runbook documenta o padrão descoberto empiricamente na versão **6.0.1** do Superset.

---

## Pré-requisitos

- Superset rodando em `http://localhost:8088`
- Dataset já criado (ver `superset_dashboards.md`)
- Python com `requests` instalado

---

## Armadilhas conhecidas

| Problema | Causa | Solução |
|---|---|---|
| `422 — One or more metrics already exist` | Payload inclui campos `created_on`, `changed_on`, `uuid` das métricas existentes | Filtrar apenas os campos permitidos antes do PUT |
| `400 — The CSRF session token is missing` | Requisição sem CSRF token ou sem cookies de sessão | Usar `requests.Session()` e buscar o token antes do PUT |
| `422 — Unknown field` | Campos como `currency` não são aceitos no PUT | Usar apenas os campos da lista `ALLOWED` abaixo |

---

## Campos permitidos no payload de métricas

```python
ALLOWED = {"id", "metric_name", "expression", "metric_type", "verbose_name",
           "d3format", "description", "warning_text", "extra"}
```

> **Regra crítica:** métricas existentes devem incluir o campo `id`.
> Novas métricas não devem incluir `id`.
> Omitir `id` de uma métrica existente faz o Superset tentar recriá-la e falhar.

---

## Padrão de autenticação

```python
import requests

BASE = "http://localhost:8088"

session = requests.Session()

# 1. Login — obtém o Bearer token
token = session.post(f"{BASE}/api/v1/security/login", json={
    "username": "admin",
    "password": "admin",
    "provider": "db"
}).json()["access_token"]

session.headers.update({"Authorization": f"Bearer {token}"})

# 2. CSRF — obrigatório para qualquer mutação (POST/PUT/DELETE)
csrf_token = session.get(f"{BASE}/api/v1/security/csrf_token/").json()["result"]
session.headers.update({
    "X-CSRFToken": csrf_token,
    "Content-Type": "application/json"
})
```

---

## Adicionar métricas a um dataset existente

```python
DATASET_ID = 1  # ajuste conforme necessário
ALLOWED = {"id", "metric_name", "expression", "metric_type", "verbose_name",
           "d3format", "description", "warning_text", "extra"}

# 1. Busca métricas existentes e limpa campos não permitidos
raw = session.get(f"{BASE}/api/v1/dataset/{DATASET_ID}").json()["result"]["metrics"]
metrics = [{k: v for k, v in m.items() if k in ALLOWED} for m in raw]

existing_names = {m["metric_name"] for m in metrics}

# 2. Define as novas métricas
new_metrics = [
    {
        "metric_name": "total_loads",
        "expression": "COUNT(LOADSMART_ID)",
        "metric_type": "count",
        "verbose_name": "Total de Cargas",
        "d3format": ",d",
        "description": "Número total de cargas no período"
    },
    {
        "metric_name": "cancellation_rate",
        "expression": "SUM(CAST(LOAD_WAS_CANCELLED AS INT)) * 1.0 / COUNT(*)",
        "metric_type": "expr",
        "verbose_name": "Taxa de Cancelamento",
        "d3format": ".1%",
        "description": "% de cargas canceladas"
    },
]

# 3. Adiciona apenas as que não existem
for m in new_metrics:
    if m["metric_name"] not in existing_names:
        metrics.append(m)

# 4. PUT — substitui a lista completa de métricas do dataset
r = session.put(f"{BASE}/api/v1/dataset/{DATASET_ID}", json={"metrics": metrics})
assert r.status_code == 200, f"Erro: {r.status_code} {r.text}"
print(f"Métricas salvas. Total: {len(metrics)}")
```

---

## Campos de referência por tipo de métrica

| Tipo | `metric_type` | `d3format` sugerido |
|---|---|---|
| Contagem simples | `count` | `,d` |
| Soma | `sum` | `,.2f` |
| Média | `avg` | `,.2f` |
| Proporção / taxa | `expr` | `.1%` |
| Razão monetária | `expr` | `$,.2f` |

---

## Verificar métricas criadas

```python
result = session.get(f"{BASE}/api/v1/dataset/{DATASET_ID}").json()["result"]
for m in result["metrics"]:
    print(f"  [{m['id']}] {m['metric_name']:30} {m['expression']}")
```

---

## Domínios e métricas do projeto Loadsmart

Ver tabela completa em [README.md — Métricas calculadas](../../README.md#métricas-calculadas).

| Domínio | Qtd | Owner |
|---|---|---|
| Financeiro | 12 | CFO / Pricing |
| Volume / Funil | 9 | Ops Manager / Produto |
| Carrier | 11 | Ops Manager |
| Automação | 7 | Produto |
| Tracking | 9 | Produto |
