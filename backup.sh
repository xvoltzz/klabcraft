#!/bin/bash

# === config ===
MC_DIR="/home/klab/Servers/EvoMC"
BACKUP_ROOT="/home/klab/Servers/Backups"
SCREEN_NAME="minecraft"

# === make sure backup root exists ===
mkdir -p "$BACKUP_ROOT"

# === get latest version from server.log ===
VERSION=$(grep -oP 'version \K[\d\.]+' "$MC_DIR/server.log" | tail -n1)
[[ -z "$VERSION" ]] && VERSION="unknown"

# === generate snapshot info ===
DATE=$(date +'%Y-%m-%d')
TIME=$(date +'%H:%M:%S')
SNAPSHOT_NAME="EvoMC (Snapshot $DATE $VERSION)"
BACKUP_DIR="$BACKUP_ROOT/$SNAPSHOT_NAME"

# === notify players in server ===
screen -S "$SCREEN_NAME" -p 0 -X stuff "say [KLABNET] Taking Server Snapshot - $VERSION $DATE $TIME\n"

# === pause world saving safely ===
screen -S "$SCREEN_NAME" -p 0 -X stuff "save-off\n"
screen -S "$SCREEN_NAME" -p 0 -X stuff "save-all\n"
sleep 5

# === create snapshot folder & back up server ===
mkdir -p "$BACKUP_DIR"
rsync -a --delete "$MC_DIR/" "$BACKUP_DIR/"

# === resume world saving ===
screen -S "$SCREEN_NAME" -p 0 -X stuff "save-on\n"

# === save snapshot metadata inside backup ===
{
  echo "Version: $VERSION"
  echo "Date: $DATE"
  echo "Time: $TIME"
} > "$BACKUP_DIR/version.txt"

# === done! notify server ===
screen -S "$SCREEN_NAME" -p 0 -X stuff "say [KLABNET] Snapshot Complete ✅\n"

