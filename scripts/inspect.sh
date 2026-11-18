#!/usr/bin/env bash
# Daily inspection / 日常巡检 — collects a health snapshot of Linux + middleware.
# From the resume ("日常巡检自动化"). Outputs a timestamped report to stdout.
set -uo pipefail

REPORT="${1:-/dev/stdout}"
run() { echo; echo "===== $1 ====="; }

{
echo "========== INSPECTION $(date '+%F %T %Z') =========="

run "HOST / UPTIME"
hostname; uptime

run "CPU (top 5)"
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -6

run "MEMORY"
free -h 2>/dev/null || echo "n/a"

run "DISK USAGE"
df -h | grep -vE 'tmpfs|devtmpfs' | head -12

run "LISTENING PORTS"
ss -tlnp 2>/dev/null | head -20 || netstat -tlnp 2>/dev/null | head -20 || echo "n/a"

run "DOCKER CONTAINERS"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo "docker not available"

run "SERVICE ENDPOINTS"
for u in http://127.0.0.1/healthz http://127.0.0.1:9090/-/healthy; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$u" 2>/dev/null || echo 000)
  echo "$code  $u"
done

run "RECENT KERNEL / AUTH ERRORS"
dmesg -T 2>/dev/null | grep -iE 'error|oom|fail' | tail -10 || echo "n/a (need root)"

echo "========== END =========="
} > "$REPORT"
