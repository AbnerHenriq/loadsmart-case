# apache/superset with DuckDB SQLAlchemy drivers + fastmcp (MCP server).
# Used by docker-compose for the Loadsmart case; config is copied from superset_config.py.
FROM apache/superset:latest

USER root

RUN /usr/local/bin/pip install \
    --target /app/.venv/lib/python3.10/site-packages \
    --no-cache-dir \
    duckdb==1.1.0 \
    duckdb-engine==0.13.2 \
    fastmcp

COPY superset_config.py /app/superset_home/superset_config.py

ENV SUPERSET_CONFIG_PATH=/app/superset_home/superset_config.py

USER superset
