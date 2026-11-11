"""Load the raw CSV files into BigQuery's `raw` dataset.

Every run fully replaces the raw tables (WRITE_TRUNCATE), so it is safe to rerun at
any time. That matters on the BigQuery sandbox, where tables expire after 60 days.

All columns land as STRING on purpose: raw tables mirror the files exactly, and
type casting happens in the dbt staging models, where failures are visible and tested.

Prerequisites:
    pip install -r requirements.txt
    gcloud auth application-default login
    python scripts/convert_online_retail_xlsx.py path/to/online_retail_II.xlsx data/

Usage:
    python scripts/load_raw.py --project excellent-badge-514402-s5
"""

import argparse
import csv
import os
import sys
from pathlib import Path

from google.cloud import bigquery

DATA_DIR = Path(__file__).resolve().parent.parent / "data"

ONLINE_RETAIL_COLUMNS = [
    # (column in the CSV header, column name in BigQuery)
    ("Invoice", "invoice"),
    ("StockCode", "stock_code"),
    ("Description", "description"),
    ("Quantity", "quantity"),
    ("InvoiceDate", "invoice_date"),
    ("Price", "price"),
    ("Customer ID", "customer_id"),
    ("Country", "country"),
]
SUNBELT_COLUMNS = [
    (c, c)
    for c in [
        "order_id", "order_date", "account_name", "sku", "product",
        "qty_ordered", "qty_fulfilled", "unit_price", "fulfillment_status", "channel",
    ]
]

TABLES = [
    # (file in data/, table in the raw dataset, expected columns)
    ("online_retail_ii_2009_2010.csv", "online_retail_ii_2009_2010", ONLINE_RETAIL_COLUMNS),
    ("online_retail_ii_2010_2011.csv", "online_retail_ii_2010_2011", ONLINE_RETAIL_COLUMNS),
    ("sunbelt_raw_export.csv", "sunbelt_order_lines", SUNBELT_COLUMNS),
]


def count_rows_and_check_header(path: Path, columns) -> int:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        expected = [src for src, _ in columns]
        if header != expected:
            raise SystemExit(f"{path.name}: header {header} does not match expected {expected}")
        return sum(1 for _ in reader)


def load_table(client: bigquery.Client, dataset: str, filename: str, table: str, columns) -> None:
    path = DATA_DIR / filename
    if not path.exists():
        raise SystemExit(f"Missing {path}. See the prerequisites at the top of this script.")

    expected_rows = count_rows_and_check_header(path, columns)
    table_id = f"{client.project}.{dataset}.{table}"
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        schema=[bigquery.SchemaField(name, "STRING", mode="NULLABLE") for _, name in columns],
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        allow_quoted_newlines=True,
        encoding="UTF-8",
    )
    with path.open("rb") as f:
        job = client.load_table_from_file(f, table_id, job_config=job_config)
    job.result()

    loaded_rows = client.get_table(table_id).num_rows
    status = "OK" if loaded_rows == expected_rows else "MISMATCH"
    print(f"[{status}] {table_id}: {loaded_rows:,} rows loaded, {expected_rows:,} rows in {filename}")
    if status != "OK":
        raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project", default=os.environ.get("GCP_PROJECT_ID"), help="Google Cloud project ID")
    parser.add_argument("--dataset", default="raw", help="Target dataset (default: raw)")
    args = parser.parse_args()
    if not args.project:
        sys.exit("Pass --project or set GCP_PROJECT_ID.")

    client = bigquery.Client(project=args.project)
    client.create_dataset(bigquery.Dataset(f"{args.project}.{args.dataset}"), exists_ok=True)
    for filename, table, columns in TABLES:
        load_table(client, args.dataset, filename, table, columns)
    print("Raw load complete.")


if __name__ == "__main__":
    main()
