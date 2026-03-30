"""
Superset configuration for local development.

- Metadata stored in SQLite (simple for local/demo).
- DuckDB connection must be added manually via the UI after startup:
    SQLAlchemy URI: duckdb:////opt/airflow/data/loadsmart.duckdb
"""

import os

SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "loadsmart_superset_secret_change_me")

# SQLite para metadados locais (adequado para demo/desenvolvimento)
SQLALCHEMY_DATABASE_URI = "sqlite:////app/superset_home/superset.db"

# Desabilita exemplos (acelera o init)
SUPERSET_LOAD_EXAMPLES = False

# Permite que o Superset conecte a arquivos locais via SQLAlchemy
PREVENT_UNSAFE_DB_CONNECTIONS = False

# ── MCP Server (Superset 5.0+) ───────────────────────────────────────────────
# Modo dev: auth desabilitada, usuário admin fixo.
# NUNCA usar em produção.
MCP_AUTH_ENABLED = False
MCP_DEV_USERNAME = "admin"

MCP_SERVICE_HOST = "0.0.0.0"
MCP_SERVICE_PORT = 5008
