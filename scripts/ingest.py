"""
Ingest the raw CSV into DuckDB raw.shipments.

Usage:
    python scripts/ingest.py [--csv-path PATH] [--db-path PATH]

Defaults read from env vars:
    CSV_PATH  → data/2026_data_challenge_ae_data.csv
    DUCKDB_PATH → data/loadsmart.duckdb
"""

import os
import argparse
import duckdb
import pandas as pd

DEFAULT_CSV = os.path.join(os.path.dirname(__file__), "..", "data", "2026_data_challenge_ae_data.csv")
# DUCKDB_PATH is set to the Docker path inside containers (/opt/airflow/data/...).
# Locally, fall back to the relative path inside data/.
_default_db_local = os.path.join(os.path.dirname(__file__), "..", "data", "loadsmart.duckdb")
DEFAULT_DB = os.environ.get("DUCKDB_PATH", _default_db_local)
if DEFAULT_DB == "/opt/airflow/data/loadsmart.duckdb" and not os.path.exists("/opt/airflow"):
    DEFAULT_DB = _default_db_local


def ingest(csv_path: str, db_path: str) -> None:
    csv_path = os.path.abspath(csv_path)
    db_path = os.path.abspath(db_path)

    print(f"[ingest] Reading CSV: {csv_path}")
    df = pd.read_csv(csv_path)

    # The CSV has a duplicate column name 'has_mobile_app_tracking'.
    # pandas auto-renames the second occurrence to 'has_mobile_app_tracking.1'.
    # We keep both — rename the duplicate so staging can inspect and decide.
    if "has_mobile_app_tracking.1" in df.columns:
        df = df.rename(columns={"has_mobile_app_tracking.1": "has_mobile_app_tracking_2"})
        print("[ingest] Renamed duplicate column to 'has_mobile_app_tracking_2'")

    print(f"[ingest] Rows loaded: {len(df)}")
    print(f"[ingest] Connecting to DuckDB: {db_path}")

    con = duckdb.connect(db_path)
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    con.execute("DROP TABLE IF EXISTS raw.shipments")
    con.execute("CREATE TABLE raw.shipments AS SELECT * FROM df")

    row_count = con.execute("SELECT COUNT(*) FROM raw.shipments").fetchone()[0]
    print(f"[ingest] raw.shipments created — {row_count} rows")
    con.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv-path", default=DEFAULT_CSV)
    parser.add_argument("--db-path", default=DEFAULT_DB)
    args = parser.parse_args()
    ingest(args.csv_path, args.db_path)
