"""Check that every raw.<table> has exactly as many rows as its CSV (minus header)."""
import csv
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
CSV_DIR = ROOT / "Bright-Case-Study-Dataset-CSV"

con = duckdb.connect(str(ROOT / "bright.duckdb"), read_only=True)
all_ok = True

print(f"{'table':<18}{'csv':>9}{'raw':>9}  status")
for path in sorted(CSV_DIR.glob("*.csv")):
    with path.open(newline="", encoding="utf-8") as fh:
        n_csv = sum(1 for row in csv.reader(fh) if row) - 1   # data rows, header excluded

    try:
        n_raw = con.execute(f"SELECT count(*) FROM raw.{path.stem}").fetchone()[0]
    except duckdb.CatalogException:
        n_raw = None

    ok = n_raw == n_csv
    all_ok &= ok
    status = "OK" if ok else ("MISSING TABLE" if n_raw is None else "MISMATCH")
    print(f"{path.stem:<18}{n_csv:>9}{n_raw if n_raw is not None else '-':>9}  {status}")

con.close()
print("\nALL OK" if all_ok else "\nCHECK FAILED")
sys.exit(0 if all_ok else 1)