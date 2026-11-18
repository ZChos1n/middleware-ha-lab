#!/usr/bin/env python3
"""Reproduce the 504 root cause: missing index -> full table scan -> slow query.

Runs the SAME logical query twice against reports.db:
  (A) before fix: no index on (device_id, reported_at) -> scan
  (B) after fix:  composite index created -> index lookup

Prints EXPLAIN QUERY PLAN and measured latency for each, so the numbers tell
the story. This is the executable version of the resume's claim:
    "interface response 3.5s -> 800ms, slow queries -99%"

Usage:
    python setup_db.py --out reports.db --rows 200000
    python benchmark.py --db reports.db --runs 5
"""

from __future__ import annotations

import argparse
import sqlite3
import statistics
import sys
import time

# The exact query shape from the incident: the dashboard aggregates one device's
# readings in a time window. It sorts + aggregates many rows, which is exactly the
# work an index on (device_id, reported_at) eliminates.
QUERY = """
SELECT metric_name, COUNT(*) AS cnt, AVG(metric_value) AS avg_v
FROM device_reports
WHERE device_id = ?
  AND reported_at >= ?
GROUP BY metric_name
ORDER BY cnt DESC
"""

# 500 devices share the table; this device has ~1/N of rows. A full scan still
# touches all rows to find it — that is the point.
SLOW_DEVICE = "device-0500"
SLOW_SINCE = "1970-01-01 00:00:00"  # match ALL rows for this device -> worst case full scan

INDEX_SQL = "CREATE INDEX IF NOT EXISTS idx_device_time ON device_reports(device_id, reported_at)"


def explain(conn: sqlite3.Connection, label: str) -> None:
    rows = conn.execute("EXPLAIN QUERY PLAN " + QUERY, (SLOW_DEVICE, SLOW_SINCE)).fetchall()
    print(f"  [{label}] query plan:")
    for r in rows:
        print(f"      {r[3]}")


def measure(conn: sqlite3.Connection, runs: int) -> list[float]:
    timings: list[float] = []
    for _ in range(runs):
        t0 = time.perf_counter()
        conn.execute(QUERY, (SLOW_DEVICE, SLOW_SINCE)).fetchall()
        timings.append((time.perf_counter() - t0) * 1000)
    return timings


def report(label: str, timings: list[float]) -> float:
    median = statistics.median(timings)
    print(f"  [{label}] median {median:.1f} ms  (runs: {', '.join(f'{t:.1f}' for t in timings)})")
    return median


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default="reports.db")
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()

    try:
        conn = sqlite3.connect(args.db)
        conn.execute("SELECT 1 FROM device_reports LIMIT 1")
    except sqlite3.Error as e:
        print(f"error: cannot open {args.db}: {e}", file=sys.stderr)
        print("hint: run setup_db.py first", file=sys.stderr)
        return 2

    print("=" * 68)
    print(" 504 INCIDENT REPRODUCTION — missing index vs composite index")
    print("=" * 68)

    print("\n[A] BEFORE FIX (no index on device_id + reported_at)")
    explain(conn, "before")
    before = report("before", measure(conn, args.runs))

    print("\n--- applying composite index: CREATE INDEX idx_device_time ---")
    t0 = time.perf_counter()
    conn.execute(INDEX_SQL)
    conn.commit()
    print(f"  index built in {(time.perf_counter() - t0) * 1000:.0f} ms")

    print("\n[B] AFTER FIX (composite index present)")
    explain(conn, "after")
    after = report("after", measure(conn, args.runs))

    print("\n" + "=" * 68)
    if after > 0:
        print(f" RESULT: {before:.1f} ms -> {after:.1f} ms  ({before / after:.1f}x faster)")
    print(" Takeaway: one missing composite index turned into 504 timeouts under concurrency.")
    print("=" * 68)

    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
