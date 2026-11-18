#!/usr/bin/env bash
# One-click application release — the Shell automation from the resume
# ("应用一键发布 30分钟 -> 5分钟").
# Pulls the tag, builds, and rolls the service with a health-gated strategy.
set -euo pipefail

APP="${APP:-showcase-api}"
TAG="${1:-latest}"
RELEASES_DIR="${RELEASES_DIR:-/opt/releases}"
CURRENT="$RELEASES_DIR/current"

log() { echo "[deploy $(date +%H:%M:%S)] $*"; }

usage() { echo "Usage: $0 <tag>  (e.g. $0 v1.2.0)"; }

[ $# -ge 1 ] || { usage; exit 2; }

log "target app=$APP tag=$TAG"

# 1. Fetch release artifact (in real life: from Nexus/Harbor via curl)
log "fetching artifact..."
DEPLOY_DIR="$RELEASES_DIR/$APP-$TAG"
mkdir -p "$DEPLOY_DIR"
# echo "$TAG" > "$DEPLOY_DIR/VERSION"   # uncomment for real artifact

# 2. Pre-deploy health snapshot so we can compare after
log "recording pre-deploy state..."
bash "$(dirname "$0")/health_check.sh" --url http://127.0.0.1/healthz --quiet || true

# 3. Atomic symlink switch (zero-downtime release pattern)
log "switching symlink..."
ln -sfn "$DEPLOY_DIR" "$CURRENT.tmp"
mv -Tf "$CURRENT.tmp" "$CURRENT"

# 4. Post-deploy health gate with rollback on failure
log "post-deploy health check..."
if bash "$(dirname "$0")/health_check.sh" --url http://127.0.0.1/healthz --retries 6; then
  log "SUCCESS: $APP@$TAG is live"
else
  log "FAILED: rolling back to previous release"
  PREV=$(ls -1dt "$RELEASES_DIR/$APP"-* 2>/dev/null | sed -n '2p' || true)
  [ -n "$PREV" ] && ln -sfn "$PREV" "$CURRENT"
  exit 1
fi
