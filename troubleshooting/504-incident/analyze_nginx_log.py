#!/usr/bin/env python3
"""Step 1 of the 504 investigation: find the slow/high-frequency endpoint
from Nginx JSON access logs (the log_format in middleware/nginx/nginx.conf).

Reports, per endpoint:
  - request count
  - count and ratio of 5xx / 504 responses
  - average and p95 upstream_response_time

This mirrors the resume line: "located the high-frequency endpoint via Nginx access log".

Usage:
    python analyze_nginx_log.py --log sample_access.log --top 10
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict


def percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round(p * (len(s) - 1)))))
    return s[k]


def analyze(path: str, top: int) -> int:
    stats: dict[str, dict] = defaultdict(
        lambda: {"count": 0, "5xx": 0, "504": 0, "upstream": []}
    )
    total = 0

    try:
        fh = open(path, encoding="utf-8")
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue  # skip malformed / non-JSON lines
            total += 1
            request = rec.get("request", "").split(" ")[1] if len(rec.get("request", "").split(" ")) > 1 else "?"
            s = stats[request]
            s["count"] += 1
            status = rec.get("status", 0)
            if 500 <= status < 600:
                s["5xx"] += 1
            if status == 504:
                s["504"] += 1
            urt = rec.get("upstream_response_time", "-")
            if isinstance(urt, (int, float)):
                s["upstream"].append(float(urt))
            elif isinstance(urt, str) and urt not in ("-", ""):
                try:
                    s["upstream"].append(float(urt.split(",")[0]))
                except ValueError:
                    pass

    print(f"Parsed {total:,} requests across {len(stats)} endpoints\n")
    header = f"{'endpoint':<28} {'count':>7} {'5xx':>6} {'504':>6} {'5xx%':>7} {'avg_up':>8} {'p95_up':>8}"
    print(header)
    print("-" * len(header))

    # Rank by 5xx count first (the incident signal), then by volume.
    ranked = sorted(stats.items(), key=lambda kv: (-kv[1]["5xx"], -kv[1]["count"]))[:top]
    for endpoint, s in ranked:
        ratio = s["5xx"] / s["count"] * 100 if s["count"] else 0
        avg = sum(s["upstream"]) / len(s["upstream"]) if s["upstream"] else 0
        p95 = percentile(s["upstream"], 0.95)
        print(f"{endpoint:<28} {s['count']:>7} {s['5xx']:>6} {s['504']:>6} "
              f"{ratio:>6.1f}% {avg:>7.3f}s {p95:>7.3f}s")

    print("\nTip: the endpoint topping this table is where you run EXPLAIN next.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", default="sample_access.log")
    parser.add_argument("--top", type=int, default=10)
    return analyze(parser.parse_args().log, parser.parse_args().top)


if __name__ == "__main__":
    raise SystemExit(main())
