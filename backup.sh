#!/bin/bash
# Local, full-directory backup (no rsync): save-off -> flush -> copy -> save-on

set -euo pipefail

### === CONFIG ===
MC_DIR="/home/klab/Servers/EvoMC"          # server folder (server.jar, world/, logs/, etc.)
BACKUP_ROOT="/home/klab/Servers/Backups"   # where timestamped copies go
SCREEN_NAME="minecraft"                    # GNU screen session name
LOG_FILE="$MC_DIR/logs/latest.log"         # server log to watch for "Saved..."
SAY_PREFIX="[KLABNET]"                     # chat prefix

### === DEPS / GUARDS ===
die(){ echo "error: $*" >&2; exit 1; }
command -v screen >/dev/null || die "gnu screen not found"

[ -d "$MC_DIR" ]   || die "MC_DIR not found: $MC_DIR"
[ -f "$LOG_FILE" ] || die "LOG_FILE not found: $LOG_FILE"

# ensure a screen session named exactly $SCREEN_NAME exists
screen -ls | grep -q "[.]${SCREEN_NAME}[[:space:]]" || die "screen session '${SCREEN_NAME}' not running"

mkdir -p "$BACKUP_ROOT"

### === HELPERS ===
mc_cmd(){ screen -S "$SCREEN_NAME" -p 0 -X stuff "$1$(printf '\r')"; }

# always try to re-enable saving on exit, even on failure
restore_saving(){ mc_cmd "save-on" >/dev/null 2>&1 || true; }
trap restore_saving EXIT

### === ANNOUNCE + QUIESCE ===
mc_cmd "say ${SAY_PREFIX} world backup starting — pausing autosave…"
mc_cmd "save-off"
sleep 1
mc_cmd "say ${SAY_PREFIX} flushing chunks to disk…"
mc_cmd "save-all"

# unique marker so we only trust 'Saved' lines after this exact point
MARK="evbot-save-$(date +%s)"
printf "%s\n" "$MARK" >> "$LOG_FILE"

# wait up to 60s for 'Saved' after the marker (vanilla/paper log lines contain 'Saved')
if ! timeout 60 bash -c \
  "awk -v mark='$MARK' '
     \$0 ~ mark { seen=1; next }
     seen && /Saved/ { exit 0 }
   END { exit 1 }' <(tail -n 0 -F \"$LOG_FILE\")" ; then
  echo "warn: timed out waiting for save confirmation — proceeding anyway"
fi

### === COPY THE ENTIRE SERVER DIRECTORY (LOCAL ONLY) ===
TS="$(date '+%Y-%m-%d_%H-%M-%S')"
BACKUP_DIR="${BACKUP_ROOT}/${TS}"
mkdir -p "$BACKUP_DIR"

mc_cmd "say ${SAY_PREFIX} copying server directory to backups (${TS})…"

# two safe paths:
# 1) normal: BACKUP_ROOT is outside MC_DIR -> simple cp -a (includes dotfiles using /.)
# 2) edge:   BACKUP_ROOT inside MC_DIR -> tar pipe excluding BACKUP_ROOT to avoid recursion
if [[ "$BACKUP_ROOT" == "$MC_DIR"* ]]; then
  # compute path relative to MC_DIR to exclude from copy
  rel_exclude="${BACKUP_ROOT#${MC_DIR}/}"
  echo "warn: BACKUP_ROOT is inside MC_DIR — excluding '$rel_exclude' during copy"
  (
    cd "$MC_DIR"
    # exclude the backups dir; copy everything else via local tar pipe
    tar --exclude="./${rel_exclude}" -cf - . | (cd "$BACKUP_DIR" && tar -xf -)
  )
else
  # plain local copy, preserving attrs; /.` ensures dotfiles are included
  cp -a "$MC_DIR"/. "$BACKUP_DIR"/
fi

# tiny manifest
{
  echo "source: $MC_DIR"
  echo "backup_dir: $BACKUP_DIR"
  echo "timestamp: $TS"
  echo "log_marker: $MARK"
} > "$BACKUP_DIR/.backup-manifest.txt"

### === DONE ===
mc_cmd "say ${SAY_PREFIX} server backup complete → ${TS}"
mc_cmd "save-on"
trap - EXIT
echo "done: $BACKUP_DIR"
