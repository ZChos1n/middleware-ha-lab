#!/usr/bin/env python3
"""Build a SQLite reproduction of the IoT device_reports table from the 504 incident.

This mirrors the MySQL schema in middleware/mysql/master-init.sql. SQLite is used
so the lab runs anywhere (no MySQL/Docker required) while still producing real
query-plan and timing differences between a missing index and a composite index.

Usage:
    python setup_db.py --out reports.db --rows 200000
"""

from __future__ import annotations

import argparse
import random
import sqlite3
import sys
import time
from datetime import datetime, timedelta, timezone

METRICS = ["voltage", "current", "temperature", "power", "energy"]


def build(db_path: str, rows: int, seed: int = 42) -> None:
    random.seed(seed)
    start = time.perf_counter()

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("DROP TABLE IF EXISTS device_reports")
    # Intentionally NO index here — the incident is caused by the missing index.
    cur.execute(
        """
        CREATE TABLE device_reports (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id    TEXT    NOT NULL,
            metric_name  TEXT    NOT NULL,
            metric_value REAL    NOT NULL,
            reported_at  TEXT    NOT NULL
        )
        """
    )

    now = datetime.now(timezone.utc)
    batch: list[tuple] = []
    for n in range(1, rows + 1):
        device = f"device-{((n % 500) + 1):04d}"
        metric = METRICS[n % len(METRICS)]
        value = round(random.uniform(0, 1000), 2)
        reported = (now - timedelta(minutes=n % 10080)).isoformat(sep=" ")
        batch.append((device, metric, value, reported))
        if len(batch) >= 5000:
            cur.executemany(
                "INSERT INTO device_reports (device_id, metric_name, metric_value, reported_at) "
                "VALUES (?, ?, ?, ?)",
                batch,
            )
            batch.clear()

    if batch:
        cur.executemany(
            "INSERT INTO device_reports (device_id, metric_name, metric_value, reported_at) "
            "VALUES (?, ?, ?, ?)",
            batch,
        )

    conn.commit()
    # No secondary index is created on purpose. The incident was caused by a
    # query on device_id + reported_at with NO supporting index -> full scan.
    conn.close()

    elapsed = time.perf_counter() - start
    print(f"[setup] inserted {rows:,} rows into {db_path} in {elapsed:.2f}s")
    print("[setup] schema has NO secondary index -> device/time queries full-scan (by design)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="reports.db", help="SQLite database path")
    parser.add_argument("--rows", type=int, default=200_000, help="number of rows to generate")
    parser.add_argument("--seed", type=int, default=42, help="random seed for reproducibility")
    args = parser.parse_args()

    if args.rows < 1:
        print("error: --rows must be >= 1", file=sys.stderr)
        return 2

    build(args.out, args.rows, args.seed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
