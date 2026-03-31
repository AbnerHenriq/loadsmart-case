# Runbook — Manage Superset database connections via API

## Context

Database connections in Superset are the entry point for all datasets and charts.
This runbook covers listing, inspecting, and duplicating connections via REST API.

Patterns discovered empirically on Superset **6.0.1** with DuckDB.

---

## Prerequisites

- Superset running at `http://localhost:8088`
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

## 1. List existing connections

```python
r = session.get(f"{BASE}/api/v1/database/?q=(page_size:20)")
for db in r.json().get("result", []):
    print(f"id={db['id']}  name={db['database_name']}  backend={db.get('backend')}")
```

> **Note:** the list endpoint **does not return** `sqlalchemy_uri` or credentials
> for security. Use the `/connection` endpoint to inspect details (see section 2).

---

## 2. Inspect full connection

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

This endpoint returns the full URI and all configuration parameters —
use it as the basis to duplicate or audit the connection.

---

## 3. Duplicate existing connection

Useful to create separate environments (e.g. production vs sandbox) pointing to
the same database, or to test changes without affecting the original connection.

```python
DATABASE_ID = 1  # original connection id

# 1. Fetch full configuration
db = session.get(f"{BASE}/api/v1/database/{DATABASE_ID}/connection").json()["result"]

# 2. Create copy with a new name
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
print(f"Connection created: id={new_id}")
```

---

## 4. Rename existing connection

```python
session.put(f"{BASE}/api/v1/database/{new_id}", json={
    "database_name": "DuckDB — Sandbox"
})
```

---

## 5. Test connectivity

```python
r = session.get(f"{BASE}/api/v1/database/{DATABASE_ID}/schemas/")
print("Available schemas:", r.json().get("result"))
```

If it returns an empty list or error, the connection is broken (wrong URI, database down,
driver not installed in Superset venv).

---

## Connections in this project

| id | Name | URI |
|----|------|-----|
| 1 | `DuckDB` | `duckdb:////opt/airflow/data/loadsmart.duckdb` |
| 2 | `DuckDB (copy)` | `duckdb:////opt/airflow/data/loadsmart.duckdb` |

### DuckDB URI in Docker

The path `/opt/airflow/data/` is the volume mounted from `./data` in `docker-compose.yml`.
**Never use the host machine local path** (e.g. `/Users/abner/...`) — Superset runs
inside the container and cannot see that path.

---

## Known pitfalls

| Pitfall | Cause | Fix |
|---------|-------|-----|
| `GET /database/` does not return URI | List endpoint masks credentials | Use `GET /database/{id}/connection` |
| Connection created but datasets cannot see DB | Duplicate `database_name` confuses Superset | Always use distinct names |
| `duckdb_engine` driver not found | Installed in wrong Python (not Superset venv) | See install runbook in README |
| `sqlalchemy_uri` returns `null` in list | Normal — only appears on `/connection` | Use the correct endpoint |
