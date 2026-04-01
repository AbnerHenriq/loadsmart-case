"""
loadsmart_pipeline
──────────────────
Orchestrates the full Loadsmart data pipeline:

  ingest_csv  →  dbt_deps  →  dbt_run  →  dbt_test  →  export_last_month

Schedule: manual trigger only.
Trigger via the Airflow UI or:
  docker compose exec airflow-webserver airflow dags trigger loadsmart_pipeline

export_last_month writes a CSV to data/exports/ and — if the SMTP_*
environment variables are set in .env — sends it by e-mail.
"""

from __future__ import annotations

import os
from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator

DUCKDB_PATH = os.environ.get("DUCKDB_PATH", "/opt/airflow/data/loadsmart.duckdb")
CSV_PATH = "/opt/airflow/data/2026_data_challenge_ae_data.csv"
DBT_PROJECT_DIR = "/opt/airflow/dbt"
DBT_PROFILES_DIR = "/opt/airflow/dbt"

default_args = {
    "owner": "loadsmart",
    "retries": 0,
}

with DAG(
    dag_id="loadsmart_pipeline",
    description="Ingest CSV → dbt deps → dbt run → dbt test (DuckDB)",
    schedule=None,           # manual trigger only
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args=default_args,
    tags=["loadsmart", "dbt", "duckdb"],
) as dag:

    def run_ingest(**context):
        """Load raw CSV into DuckDB raw.shipments."""
        import sys
        sys.path.insert(0, "/opt/airflow/scripts")
        from ingest import ingest
        ingest(csv_path=CSV_PATH, db_path=DUCKDB_PATH)

    ingest_csv = PythonOperator(
        task_id="ingest_csv",
        python_callable=run_ingest,
    )

    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=(
            f"dbt deps "
            f"--project-dir {DBT_PROJECT_DIR} "
            f"--profiles-dir {DBT_PROFILES_DIR}"
        ),
        env={**os.environ, "DUCKDB_PATH": DUCKDB_PATH},
    )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=(
            f"dbt run "
            f"--project-dir {DBT_PROJECT_DIR} "
            f"--profiles-dir {DBT_PROFILES_DIR} "
            f"--target dev "
            f"--no-partial-parse"
        ),
        env={**os.environ, "DUCKDB_PATH": DUCKDB_PATH},
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"dbt test "
            f"--project-dir {DBT_PROJECT_DIR} "
            f"--profiles-dir {DBT_PROFILES_DIR} "
            f"--target dev "
            f"--no-partial-parse"
        ),
        env={**os.environ, "DUCKDB_PATH": DUCKDB_PATH},
    )

    def run_export(**context):
        """Export last-month deliveries to CSV and optionally send by e-mail."""
        import sys
        sys.path.insert(0, "/opt/airflow/scripts")
        from export_last_month import run
        run(db_path=DUCKDB_PATH, output_dir="/opt/airflow/data/exports")

    export_last_month = PythonOperator(
        task_id="export_last_month",
        python_callable=run_export,
    )

    ingest_csv >> dbt_deps >> dbt_run >> dbt_test >> export_last_month
