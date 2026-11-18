#!/usr/bin/env bash
# API health check — from the resume ("Python/Shell 实现 API 健康检查").
# Works with curl; exits non-zero on failure so cron/CI can alert.
set -euo pipefail

URL="${URL:-http://127.0.0.1/healthz}"
RETRIES="${RETRIES:-3}"
INTERVAL="${INTERVAL:-2}"
TIMEOUT="${TIMEOUT:-5}"
QUIET=0

usage() { echo "Usage: $0 --url URL [--retries N] [--interval SEC] [--quiet]"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --retries) RETRIES="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1"; usage; exit 2 ;;
  esac
done

for i in $(seq 1 "$RETRIES"); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$URL" 2>/dev/null || echo 000)
  if [ "$code" = "200" ]; then
    [ "$QUIET" -eq 0 ] && echo "OK $URL (attempt $i, HTTP $code)"
    exit 0
  fi
  [ "$QUIET" -eq 0 ] && echo "FAIL $URL (attempt $i, HTTP $code)"
  [ "$i" -lt "$RETRIES" ] && sleep "$INTERVAL"
done

exit 1
