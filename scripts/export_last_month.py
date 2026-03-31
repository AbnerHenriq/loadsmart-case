import io
import os
import smtplib
import email.mime.multipart
import email.mime.text
import email.mime.base
import email.encoders
from pathlib import Path

import duckdb
import pandas as pd
from dateutil.relativedelta import relativedelta

# Export columns per PRD
COLUMNS = {
    "LOADSMART_ID": "loadsmart_id",
    "SHIPPER_NAME": "shipper_name",
    "DELIVERED_AT": "delivery_date",
    "PICKUP_CITY": "pickup_city",
    "PICKUP_STATE": "pickup_state",
    "DELIVERY_CITY": "delivery_city",
    "DELIVERY_STATE": "delivery_state",
    "BOOK_PRICE": "book_price",
    "CARRIER_NAME": "carrier_name",
}


def export(db_path, output_dir="data/exports"):
    con = duckdb.connect(db_path, read_only=True)

    max_date_raw = con.execute("""
        SELECT MAX(DELIVERED_AT)
        FROM main_mart.fct_shipments
        WHERE LOAD_WAS_CANCELLED = false
    """).fetchone()[0]

    if max_date_raw is None:
        raise ValueError("No deliveries found.")

    max_date = max_date_raw.date() if hasattr(max_date_raw, "date") else max_date_raw
    start = max_date.replace(day=1)
    end = start + relativedelta(months=1)

    print(f"Exporting: {start.strftime('%B %Y')} ({start} to {end})")

    df = con.execute("""
        SELECT
            f.LOADSMART_ID,
            f.DELIVERED_AT,
            f.PICKUP_CITY,
            f.PICKUP_STATE,
            f.DELIVERY_CITY,
            f.DELIVERY_STATE,
            f.BOOK_PRICE,
            dc.carrier_name AS CARRIER_NAME,
            ds.shipper_name AS SHIPPER_NAME
        FROM main_mart.fct_shipments f
        LEFT JOIN main_mart.dim_carrier dc ON f.CARRIER_SK = dc.CARRIER_SK
        LEFT JOIN main_mart.dim_shipper ds ON f.SHIPPER_SK = ds.SHIPPER_SK
        WHERE
            f.DELIVERED_AT >= CAST(? AS DATE)
            AND f.DELIVERED_AT < CAST(? AS DATE)
            AND f.LOAD_WAS_CANCELLED = false
        ORDER BY f.DELIVERED_AT
    """, [str(start), str(end)]).df()

    con.close()

    df_out = df[list(COLUMNS.keys())].rename(columns=COLUMNS)

    output_path = Path(output_dir) / f"deliveries_{start.strftime('%Y_%m')}.csv"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_out.to_csv(output_path, index=False)

    print(f"CSV saved: {output_path} ({len(df_out)} rows)")
    return str(output_path), df_out, start


def send_email(df, smtp_config, recipients, subject, filename):
    buffer = io.StringIO()
    df.to_csv(buffer, index=False)
    csv_bytes = buffer.getvalue().encode("utf-8")

    msg = email.mime.multipart.MIMEMultipart()
    msg["From"] = smtp_config["user"]
    msg["To"] = ", ".join(recipients)
    msg["Subject"] = subject
    msg.attach(email.mime.text.MIMEText("Please find attached the CSV for the last completed month.", "plain"))

    attachment = email.mime.base.MIMEBase("application", "octet-stream")
    attachment.set_payload(csv_bytes)
    email.encoders.encode_base64(attachment)
    attachment.add_header("Content-Disposition", "attachment", filename=filename)
    msg.attach(attachment)

    with smtplib.SMTP(smtp_config["host"], smtp_config["port"]) as server:
        server.starttls()
        server.login(smtp_config["user"], smtp_config["password"])
        server.sendmail(smtp_config["user"], recipients, msg.as_string())

    print(f"Email sent to: {', '.join(recipients)}")


def run(db_path, output_dir="data/exports"):
    csv_path, df_out, start = export(db_path, output_dir)

    host = os.environ.get("SMTP_HOST")
    user = os.environ.get("SMTP_USER")
    password = os.environ.get("SMTP_PASSWORD")
    recipients_raw = os.environ.get("SMTP_RECIPIENTS", "")

    if not all([host, user, password, recipients_raw]):
        print("SMTP not configured, skipping email.")
        return

    smtp_config = {
        "host": host,
        "port": int(os.environ.get("SMTP_PORT", "587")),
        "user": user,
        "password": password,
    }
    recipients = [r.strip() for r in recipients_raw.split(",") if r.strip()]
    subject = f"Deliveries — {start.strftime('%B %Y')}"

    send_email(df_out, smtp_config, recipients, subject, Path(csv_path).name)


if __name__ == "__main__":
    run(
        db_path=os.environ.get("DUCKDB_PATH", "data/loadsmart.duckdb"),
        output_dir=os.environ.get("EXPORT_DIR", "data/exports"),
    )
