#!/usr/bin/env python3
"""Log analysis tool — from the resume ("Python 脚本实现日志分析").

Parses Nginx JSON access logs and answers:
  - error rate by status code
  - slowest requests (by request_time)
  - top talkers by remote_addr
  - traffic per hour

Usage:
    python log_analyzer.py --log sample.log --slow-top 5
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict


def load(path: str) -> list[dict]:
    records: list[dict] = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
    return records


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--log", required=True)
    ap.add_argument("--slow-top", type=int, default=5)
    args = ap.parse_args()

    recs = load(args.log)
    if not recs:
        print("no valid JSON log records found")
        return 1

    total = len(recs)
    statuses = Counter(str(r.get("status")) for r in recs)
    clients = Counter(r.get("remote_addr", "?") for r in recs)
    hours = Counter((r.get("time", "")[:13]) for r in recs)

    print(f"Analyzed {total:,} requests\n")

    print("Status distribution:")
    for code, n in sorted(statuses.items()):
        print(f"  {code}: {n:>6}  ({n / total * 100:5.1f}%)")

    print("\nSlowest requests:")
    slow = sorted(recs, key=lambda r: float(r.get("request_time", 0)), reverse=True)[: args.slow_top]
    for r in slow:
        req = r.get("request", "?")
        print(f"  {r.get('request_time', 0):>7.3f}s  {r.get('status')}  {req}")

    print("\nTop clients:")
    for ip, n in clients.most_common(5):
        print(f"  {ip:<20} {n:>6}")

    print("\nTraffic by hour:")
    for h, n in sorted(hours.items()):
        print(f"  {h}:00  {n:>6}  {'#' * min(60, n // 10)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
