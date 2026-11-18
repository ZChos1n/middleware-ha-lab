"""Tests for the log-analysis and health-check tools (run with pytest)."""

import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable
INCIDENT = os.path.join(ROOT, "troubleshooting", "504-incident")


def _run(script, *args):
    return subprocess.run([PY, script, *args], capture_output=True, text=True)


def test_log_analyzer(tmp_path):
    log = tmp_path / "access.log"
    rows = [
        {"time": "2026-04-10T09:00:00", "remote_addr": "10.0.0.1", "request": "GET /a HTTP/1.1",
         "status": 200, "request_time": 0.1},
        {"time": "2026-04-10T09:00:01", "remote_addr": "10.0.0.1", "request": "GET /a HTTP/1.1",
         "status": 504, "request_time": 3.5},
    ]
    log.write_text("\n".join(json.dumps(r) for r in rows), encoding="utf-8")
    r = _run(os.path.join(ROOT, "scripts", "python", "log_analyzer.py"), "--log", str(log))
    assert r.returncode == 0
    assert "Analyzed 2 requests" in r.stdout
    assert "504" in r.stdout


def test_benchmark_produces_index_comparison(tmp_path):
    db = tmp_path / "t.db"
    setup = _run(os.path.join(INCIDENT, "setup_db.py"), "--out", str(db), "--rows", "5000")
    assert setup.returncode == 0, setup.stderr
    bench = _run(os.path.join(INCIDENT, "benchmark.py"), "--db", str(db), "--runs", "2")
    assert bench.returncode == 0, bench.stderr
    assert "SCAN device_reports" in bench.stdout
    assert "SEARCH device_reports USING INDEX" in bench.stdout
    assert "faster" in bench.stdout


def test_nginx_log_analysis_ranks_errors():
    r = _run(os.path.join(INCIDENT, "analyze_nginx_log.py"),
             "--log", os.path.join(INCIDENT, "sample_access.log"), "--top", "3")
    assert r.returncode == 0
    assert "/api/dashboard/realtime" in r.stdout
