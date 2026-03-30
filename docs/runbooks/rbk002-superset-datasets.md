# Runbook — Criar e Copiar Datasets Virtuais no Superset via API

## Contexto

Datasets no Superset podem ser **físicos** (apontam direto para uma tabela) ou
**virtuais** (definidos por um SQL customizado). Datasets virtuais permitem JOINs,
filtros fixos e transformações sem alterar o banco.

Este runbook cobre:
1. Listar e inspecionar datasets existentes
2. Criar um dataset virtual do zero
3. Copiar um dataset existente com um filtro adicional (ex: só cargas ativas)

Padrão descoberto empiricamente no Superset **6.0.1** com DuckDB.

---

## Pré-requisitos

- Superset rodando em `http://localhost:8088`
- Banco de dados já conectado (ver conexão DuckDB no README)
- Python com `requests` instalado

---

## Autenticação

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

## 1. Listar datasets e identificar se são virtuais

```python
r = session.get(f"{BASE}/api/v1/dataset/?q=(page_size:20)")
for ds in r.json().get("result", []):
    tipo = "virtual" if ds.get("sql") else "físico"
    print(f"id={ds['id']}  [{tipo}]  {ds['table_name']}  schema={ds.get('schema')}")
```

Um dataset é **virtual** quando o campo `sql` está preenchido.

---

## 2. Inspecionar um dataset completo

```python
r = session.get(f"{BASE}/api/v1/dataset/1")
ds = r.json()["result"]

print("SQL:", ds.get("sql"))
print("Colunas:", [c["column_name"] for c in ds["columns"]])
print("Métricas:", [m["metric_name"] for m in ds["metrics"]])
```

---

## 3. Criar dataset virtual do zero

```python
# Descobrir o id do banco de dados
r = session.get(f"{BASE}/api/v1/database/?q=(page_size:10)")
for db in r.json()["result"]:
    print(f"id={db['id']}  {db['database_name']}")

DATABASE_ID = 1  # ajuste conforme o id do DuckDB

r = session.post(f"{BASE}/api/v1/dataset/", json={
    "database": DATABASE_ID,
    "table_name": "meu_dataset",
    "schema": "loadsmart.main_mart",   # schema do banco (opcional)
    "sql": """
        SELECT f.*, dc.carrier_name
        FROM main_mart.fct_shipments f
        LEFT JOIN main_mart.dim_carrier dc ON f.carrier_sk = dc.carrier_sk
        WHERE f.load_was_cancelled = false
    """,
})

new_id = r.json()["id"]
print(f"Dataset criado: id={new_id}")
```

> **Atenção**: não enviar `columns` nem `metrics` no POST — o Superset retorna
> `400 Unknown field`. Adicione-os depois via PUT (ver seção 5).

---

## 4. Copiar dataset existente com filtro adicional

Este é o padrão para criar uma "view filtrada" de um dataset já configurado,
preservando todas as métricas.

```python
DATASET_ID = 1  # dataset original

# 1. Buscar o original
ds = session.get(f"{BASE}/api/v1/dataset/{DATASET_ID}").json()["result"]

# 2. Montar SQL com filtro adicional
sql_filtrado = ds["sql"].rstrip().rstrip(";") + "\nWHERE f.load_was_cancelled = false"
# Se o SQL original já tiver WHERE, use AND em vez de WHERE

# 3. Criar novo dataset (sem colunas/métricas no POST)
r = session.post(f"{BASE}/api/v1/dataset/", json={
    "database": ds["database"]["id"],
    "table_name": "fct_shipments_active",
    "schema": ds.get("schema"),
    "sql": sql_filtrado,
})
new_id = r.json()["id"]
print(f"Dataset criado: id={new_id}")

# 4. Copiar métricas do original
ALLOWED_MET = {
    "metric_name", "expression", "metric_type", "verbose_name",
    "d3format", "description", "warning_text", "extra"
}
metrics = [{k: v for k, v in m.items() if k in ALLOWED_MET} for m in ds["metrics"]]

r = session.put(f"{BASE}/api/v1/dataset/{new_id}", json={"metrics": metrics})
print(f"Métricas copiadas: {len(metrics)}")

# 5. Sincronizar colunas (introspect)
session.put(f"{BASE}/api/v1/dataset/{new_id}/refresh")
print("Colunas sincronizadas")
```

---

## 5. Adicionar métricas a um dataset existente

Ver runbook `rbk003-superset-metrics.md` para o padrão completo.
O campo-chave: sempre fazer GET das métricas existentes, filtrar para `ALLOWED_MET`,
e enviar tudo junto no PUT (não apenas as novas).

---

## Datasets neste projeto

| id | Nome | Tipo | Filtro |
|----|------|------|--------|
| 1 | `fct_shipments` | virtual | todas as cargas |
| 2 | `fct_shipments_active` | virtual | `load_was_cancelled = false` |

Para referenciar um dataset em params de chart, use `"{id}__table"`:

```python
# Dataset completo
"datasource": "1__table"

# Só cargas ativas
"datasource": "2__table"
```

---

## Armadilhas conhecidas

| Armadilha | Causa | Fix |
|-----------|-------|-----|
| `400 — columns: Unknown field` | `columns`/`metrics` no payload do POST | Enviar só no PUT após criação |
| Dataset criado mas sem colunas | Superset não faz introspect automático | Chamar `PUT /api/v1/dataset/{id}/refresh` |
| SQL com subquery falha | DuckDB exige alias na subquery | `SELECT * FROM (SELECT ...) AS sub` |
| Schema errado no DuckDB | DuckDB usa `schema.database` invertido vs Postgres | Usar `main_mart.tabela` diretamente no SQL, não no campo `schema` |
