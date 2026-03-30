# Runbook — Gerenciar Conexões de Database no Superset via API

## Contexto

Conexões de database no Superset são o ponto de entrada para todos os datasets e charts.
Este runbook cobre listar, inspecionar e duplicar conexões via REST API.

Padrão descoberto empiricamente no Superset **6.0.1** com DuckDB.

---

## Pré-requisitos

- Superset rodando em `http://localhost:8088`
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

## 1. Listar conexões existentes

```python
r = session.get(f"{BASE}/api/v1/database/?q=(page_size:20)")
for db in r.json().get("result", []):
    print(f"id={db['id']}  name={db['database_name']}  backend={db.get('backend')}")
```

> **Atenção**: o endpoint de listagem **não retorna** `sqlalchemy_uri` nem credenciais
> por segurança. Use o endpoint `/connection` para inspecionar detalhes (ver seção 2).

---

## 2. Inspecionar conexão completa

```python
DATABASE_ID = 1

r = session.get(f"{BASE}/api/v1/database/{DATABASE_ID}/connection")
db = r.json()["result"]

print("name       :", db["database_name"])
print("URI        :", db["sqlalchemy_uri"])
print("driver     :", db["driver"])
print("parameters :", db["parameters"])
print("extra      :", db["extra"])
```

Este endpoint retorna a URI completa e todos os parâmetros de configuração —
use-o como base para duplicar ou auditar a conexão.

---

## 3. Duplicar conexão existente

Útil para criar ambientes separados (ex: produção vs sandbox) apontando para
o mesmo banco, ou para testar alterações sem afetar a conexão original.

```python
DATABASE_ID = 1  # id da conexão original

# 1. Buscar configuração completa
db = session.get(f"{BASE}/api/v1/database/{DATABASE_ID}/connection").json()["result"]

# 2. Criar cópia com novo nome
r = session.post(f"{BASE}/api/v1/database/", json={
    "database_name":          f"{db['database_name']} (copy)",
    "sqlalchemy_uri":         db["sqlalchemy_uri"],
    "configuration_method":   db["configuration_method"],
    "driver":                 db["driver"],
    "expose_in_sqllab":       db["expose_in_sqllab"],
    "allow_ctas":             db["allow_ctas"],
    "allow_cvas":             db["allow_cvas"],
    "allow_dml":              db["allow_dml"],
    "allow_file_upload":      db["allow_file_upload"],
    "allow_run_async":        db["allow_run_async"],
    "extra":                  db["extra"],
    "masked_encrypted_extra": db["masked_encrypted_extra"],
    "impersonate_user":       db["impersonate_user"],
})

new_id = r.json()["id"]
print(f"Conexão criada: id={new_id}")
```

---

## 4. Renomear conexão existente

```python
session.put(f"{BASE}/api/v1/database/{new_id}", json={
    "database_name": "DuckDB — Sandbox"
})
```

---

## 5. Testar conectividade

```python
r = session.get(f"{BASE}/api/v1/database/{DATABASE_ID}/schemas/")
print("Schemas disponíveis:", r.json().get("result"))
```

Se retornar lista vazia ou erro, a conexão está quebrada (URI errada, banco fora do ar,
driver não instalado no venv do Superset).

---

## Conexões neste projeto

| id | Nome | URI |
|----|------|-----|
| 1 | `DuckDB` | `duckdb:////opt/airflow/data/loadsmart.duckdb` |
| 2 | `DuckDB (copy)` | `duckdb:////opt/airflow/data/loadsmart.duckdb` |

### URI do DuckDB no Docker

O caminho `/opt/airflow/data/` é o volume montado em `./data` no `docker-compose.yml`.
**Nunca usar o path local da máquina host** (ex: `/Users/abner/...`) — o Superset roda
dentro do container e não enxerga esse caminho.

---

## Armadilhas conhecidas

| Armadilha | Causa | Fix |
|-----------|-------|-----|
| `GET /database/` não retorna URI | Endpoint de listagem mascara credenciais | Usar `GET /database/{id}/connection` |
| Conexão criada mas datasets não enxergam o banco | `database_name` duplicado confunde o Superset | Dar nomes distintos sempre |
| Driver `duckdb_engine` não encontrado | Instalado no Python errado (não no venv do Superset) | Ver runbook de instalação no README |
| `sqlalchemy_uri` retorna `null` na listagem | Normal — só aparece em `/connection` | Usar o endpoint correto |
