#!/usr/bin/env bash
# Log rotation — from the resume ("日志切割，节省磁盘 40%").
# Compresses rotated logs and deletes old ones. Designed to be run by cron.
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/app}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
PATTERN="${PATTERN:-*.log}"

log() { echo "[logrotate $(date +%F' '%H:%M)] $*"; }

[ -d "$LOG_DIR" ] || { log "directory not found: $LOG_DIR"; exit 1; }

rotated=0
freed=0

shopt -s nullglob
for f in "$LOG_DIR"/$PATTERN; do
  [ -s "$f" ] || continue
  stamp=$(date +%Y%m%d%H%M%S)
  target="${f}.${stamp}"
  mv "$f" "$target"
  gzip "$target"
  rotated=$((rotated + 1))
  log "rotated $(basename "$f") -> $(basename "$target").gz"
done

# Delete compressed logs older than retention
while IFS= read -r -d '' old; do
  sz=$(stat -c %s "$old" 2>/dev/null || echo 0)
  freed=$((freed + sz))
  rm -f "$old"
  log "deleted $(basename "$old") (>${RETENTION_DAYS}d)"
done < <(find "$LOG_DIR" -name "$PATTERN.*.gz" -mtime "+${RETENTION_DAYS}" -print0 2>/dev/null)

log "done: $rotated rotated, ~$((freed / 1024 / 1024))MB reclaimed"

# cron example (daily 02:00):
# 0 2 * * * LOG_DIR=/var/log/app /opt/scripts/logrotate.sh >> /var/log/logrotate.log 2>&1
