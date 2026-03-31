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

# Export columns per PRD (query uses mart snake_case; values = CSV header names)
COLUMNS = {
    "loadsmart_id": "loadsmart_id",
    "shipper_name": "shipper_name",
    "delivered_at": "delivery_date",
    "pickup_city": "pickup_city",
    "pickup_state": "pickup_state",
    "delivery_city": "delivery_city",
    "delivery_state": "delivery_state",
    "book_price": "book_price",
    "carrier_name": "carrier_name",
}


def export(db_path, output_dir="data/exports"):
    con = duckdb.connect(db_path, read_only=True)

    max_date_raw = con.execute("""
        SELECT MAX(delivered_at)
        FROM main_mart.fct_shipments
        WHERE load_was_cancelled = false
    """).fetchone()[0]

    if max_date_raw is None:
        raise ValueError("No deliveries found.")

    max_date = max_date_raw.date() if hasattr(max_date_raw, "date") else max_date_raw
    start = max_date.replace(day=1)
    end = start + relativedelta(months=1)

    print(f"Exporting: {start.strftime('%B %Y')} ({start} to {end})")

    df = con.execute("""
        SELECT
            f.loadsmart_id,
            f.delivered_at,
            f.pickup_city,
            f.pickup_state,
            f.delivery_city,
            f.delivery_state,
            f.book_price,
            dc.carrier_name AS carrier_name,
            ds.shipper_name AS shipper_name
        FROM main_mart.fct_shipments f
        LEFT JOIN main_mart.dim_carrier dc ON f.carrier_sk = dc.carrier_sk
        LEFT JOIN main_mart.dim_shipper ds ON f.shipper_sk = ds.shipper_sk
        WHERE
            f.delivered_at >= CAST(? AS DATE)
            AND f.delivered_at < CAST(? AS DATE)
            AND f.load_was_cancelled = false
        ORDER BY f.delivered_at
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
