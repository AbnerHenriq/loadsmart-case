# Usa o build mais recente disponível no Docker Hub.
# MCP (superset mcp run) está documentado mas ainda não foi publicado em nenhum
# tag estável do Docker Hub (6.0.1 é o latest em 2026-03-29).
# Quando o 6.1+ for publicado com MCP, basta rodar: docker compose build --no-cache
FROM apache/superset:latest

USER root

# O venv do Superset não tem pip próprio; instalamos direto no site-packages do venv.
# duckdb==1.1.0: mesma versão usada no pipeline
# duckdb-engine==0.13.2: SQLAlchemy dialect para DuckDB
RUN /usr/local/bin/pip install \
    --target /app/.venv/lib/python3.10/site-packages \
    --no-cache-dir \
    duckdb==1.1.0 \
    duckdb-engine==0.13.2 \
    fastmcp

COPY superset_config.py /app/superset_home/superset_config.py

ENV SUPERSET_CONFIG_PATH=/app/superset_home/superset_config.py

USER superset
