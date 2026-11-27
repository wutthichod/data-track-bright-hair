"""Run all SQL files in sql/ (in name order) against bright.duckdb.

Usage:
    .venv/bin/python run.py          # run everything
    .venv/bin/python run.py 01       # run only files whose name starts with '01'
"""
import os
import sys
import time
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "bright.duckdb"
SQL_DIR = ROOT / "sql"


def main(prefix: str | None = None) -> None:
    os.chdir(ROOT)  # relative CSV paths inside the SQL resolve from the project root

    files = sorted(p for p in SQL_DIR.glob("*.sql") if not p.name.startswith("00_"))
    if prefix:
        files = [p for p in files if p.name.startswith(prefix)]
    if not files:
        sys.exit("No SQL files to run.")

    con = duckdb.connect(str(DB_PATH))
    try:
        for path in files:
            start = time.perf_counter()
            print(f"→ {path.name:<28}", end="", flush=True)
            try:
                con.execute(path.read_text(encoding="utf-8"))
            except duckdb.Error as e:
                print("FAILED")
                print(f"\n{type(e).__name__}: {e}")
                sys.exit(1)
            print(f"ok  ({time.perf_counter() - start:.2f}s)")
    finally:
        con.close()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)