#!/usr/bin/env bash
# Keepalived track_script: demote this node if Nginx or the local app is unhealthy.
# A common mistake is checking only the nginx PID; here we also check that Nginx
# can actually serve a request, which catches "process alive but worker stuck".
set -euo pipefail

FAILURES=0
MAX_FAILURES=3

for i in $(seq 1 "$MAX_FAILURES"); do
  if curl -fsS --max-time 2 http://127.0.0.1/healthz >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

# Health check failed: stop nginx so keepalived releases the VIP and the peer takes over.
systemctl stop nginx 2>/dev/null || pkill -x nginx 2>/dev/null || true
exit 1
