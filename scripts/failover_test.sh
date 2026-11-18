#!/usr/bin/env bash
# Keepalived failover drill — verify the VIP moves when the master's Nginx dies.
# This is the executable proof of "主导搭建 Nginx + Keepalived 高可用集群".
#
# Prereqs: two nodes running keepalived with a shared VIP.
# Usage: VIP=172.20.0.100 MASTER=node1 BACKUP=node2 bash failover_test.sh
set -euo pipefail

VIP="${VIP:-172.20.0.100}"
MASTER="${MASTER:-node1}"
CHECK_URL="http://${VIP}/healthz"

log() { echo "[failover $(date +%H:%M:%S)] $*"; }

# Resolve which node currently owns the VIP via ARP.
vip_owner() {
  ip neigh show "$VIP" 2>/dev/null | grep -oE 'dev [^ ]+' | head -1 || echo "unknown"
}

log "step 0: baseline — VIP $VIP should answer"
curl -fsS --max-time 3 "$CHECK_URL" && log "baseline OK"

log "step 1: confirm ping to VIP works"
ping -c 2 -W 1 "$VIP" && log "VIP reachable"

log "step 2: STOP nginx on MASTER ($MASTER) to trigger keepalived demotion"
echo "  >>> run on $MASTER:  systemctl stop nginx"
echo "  >>> check_nginx.sh will fail 3x, keepalived lowers priority, VIP migrates"
read -r -p "  Press Enter after stopping nginx on master ..."

log "step 3: wait for ARP convergence and verify VIP still answers"
for i in $(seq 1 10); do
  if curl -fsS --max-time 2 "$CHECK_URL" >/dev/null 2>&1; then
    log "PASS: VIP still serving after master failure (attempt $i) — failover succeeded"
    exit 0
  fi
  sleep 1
done

log "FAIL: VIP did not recover within 10s — check keepalived logs on both nodes"
exit 1

# Restore: start nginx on master, VIP fails back (preempt) per priority settings.
