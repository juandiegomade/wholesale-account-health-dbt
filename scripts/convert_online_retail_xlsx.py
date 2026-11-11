"""Convert the UCI "Online Retail II" Excel file into one UTF-8 CSV per sheet.

The workbook has two sheets ("Year 2009-2010" and "Year 2010-2011"). Each sheet is
written as-is, as text: no rows are dropped and no values are cleaned here. Cleaning
belongs in dbt, where every rule is visible, tested and documented.

The only formatting applied is what Excel forces on us:
  - integer-like numbers that Excel stores as floats (Customer ID 13085.0,
    numeric StockCodes) are written without the trailing ".0"
  - timestamps are written as ISO 8601 (YYYY-MM-DD HH:MM:SS)

Usage:
    python scripts/convert_online_retail_xlsx.py path/to/online_retail_II.xlsx data/
"""

import csv
import datetime as dt
import sys
from pathlib import Path

import pandas as pd

SHEETS = {
    "Year 2009-2010": "online_retail_ii_2009_2010.csv",
    "Year 2010-2011": "online_retail_ii_2010_2011.csv",
}
COLUMNS = ["Invoice", "StockCode", "Description", "Quantity", "InvoiceDate", "Price", "Customer ID", "Country"]


def to_text(value) -> str:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    if isinstance(value, (pd.Timestamp, dt.datetime)):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def main(xlsx_path: str, out_dir: str) -> None:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for sheet, filename in SHEETS.items():
        df = pd.read_excel(xlsx_path, sheet_name=sheet, engine="calamine", dtype=object)
        missing = [c for c in COLUMNS if c not in df.columns]
        if missing:
            raise SystemExit(f"Sheet {sheet!r} is missing expected columns: {missing}")
        df = df[COLUMNS]
        target = out / filename
        with target.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
            writer.writerow(COLUMNS)
            for row in df.itertuples(index=False, name=None):
                writer.writerow([to_text(v) for v in row])
        print(f"{sheet}: {len(df):,} rows -> {target}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
