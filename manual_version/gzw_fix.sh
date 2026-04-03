#!/bin/bash
set -uo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_FILE="$SCRIPT_DIR/gzw_fix.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Defaults — overridden by config
NOTIFY=false
LOG_MAX_LINES=100
TARGET_DIR=""
MANIFEST=""
FILES=()

# shellcheck source=gzw_fix.conf
source "$CONFIG_FILE"

# ─── Config validation ────────────────────────────────────────────────────────

CONFIG_ERROR=false

if [ -z "$TARGET_DIR" ]; then
    echo "[ERROR] TARGET_DIR is not set." >&2
    CONFIG_ERROR=true
fi

if [ -z "$MANIFEST" ]; then
    echo "[ERROR] MANIFEST is not set." >&2
    CONFIG_ERROR=true
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "[ERROR] FILES is empty." >&2
    CONFIG_ERROR=true
fi

[ "$CONFIG_ERROR" = true ] && exit 1

# Normalize trailing slash
TARGET_DIR="${TARGET_DIR%/}/"

# ─── Logging / Notification ───────────────────────────────────────────────────

LOG_FILE="$SCRIPT_DIR/gzw_fix.log"

_ts() { date "+%Y-%m-%d %H:%M:%S"; }

{
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  GZW Fix — $(_ts)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
} >> "$LOG_FILE"

if [ -f "$LOG_FILE" ]; then
    CURRENT_LINES=$(wc -l < "$LOG_FILE")
    if [ "$CURRENT_LINES" -gt "$LOG_MAX_LINES" ]; then
        tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
fi

log_info() {
    local msg="$1"
    echo "[$(_ts)] [INFO]  $msg" >> "$LOG_FILE"
    if [ "$NOTIFY" = true ]; then
        notify-send -a "GZW Fix" -i dialog-information "GZW Fix" "$msg" 2>/dev/null || true
    fi
}

log_warn() {
    local msg="$1"
    echo "[$(_ts)] [WARN]  $msg" >> "$LOG_FILE"
    if [ "$NOTIFY" = true ]; then
        notify-send -a "GZW Fix" -i dialog-warning -u normal "GZW Fix – Warning" "$msg" 2>/dev/null || true
    fi
}

log_error() {
    local msg="$1"
    echo "[$(_ts)] [ERROR] $msg" >> "$LOG_FILE"
    if [ "$NOTIFY" = true ]; then
        notify-send -a "GZW Fix" -i dialog-error -u critical "GZW Fix – Error" "$msg" 2>/dev/null || true
    fi
}

# ─── Guard: script requires a launch command ──────────────────────────────────

if [ $# -eq 0 ]; then
    log_warn "No launch command provided — files will be restored but the game will not start."
fi

# ─── State helper ─────────────────────────────────────────────────────────────
#
# Reads all manifest IDs from the InstalledDepots block of the ACF.
# Brace-depth tracking prevents "manifest" keys from other blocks
# (e.g. UserConfig) from being included.
# Output: buildid:manifestA:manifestB:... (sorted, deterministic)

_read_game_state() {
    local acf="$1"
    local buildid

    buildid=$(grep -m1 '"buildid"' "$acf" | awk -F'"' '{print $4}')

    local depot_manifests
    depot_manifests=$(awk '
        /"InstalledDepots"/ { in_depots=1; depth=0; next }
        in_depots && /\{/   { depth++ }
        in_depots && /\}/   { depth--; if (depth < 0) in_depots=0 }
        in_depots && /"manifest"/ {
            gsub(/"/, "")
            print $2
        }
    ' "$acf" | sort | paste -sd ':')

    if [ -z "$buildid" ] || [ -z "$depot_manifests" ]; then
        echo ""
        return
    fi

    echo "${buildid}:${depot_manifests}"
}

# ─── Main logic ───────────────────────────────────────────────────────────────

CHECKSUM_FILE="${TARGET_DIR}.clean_checksums"
VERSION_FILE="${TARGET_DIR}.last_known_state"

if [ ! -f "$MANIFEST" ]; then
    log_error "Steam manifest not found: $MANIFEST"
    exit 1
fi

log_info "TARGET_DIR: $TARGET_DIR"
log_info "MANIFEST:   $MANIFEST"

CURRENT_STATE=$(_read_game_state "$MANIFEST")

if [ -z "$CURRENT_STATE" ]; then
    log_error "Could not parse build ID or depot manifests from ACF."
    exit 1
fi

LAST_STATE=$(cat "$VERSION_FILE" 2>/dev/null || echo "")

UPDATE_DETECTED=false
if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
    if [ -n "$LAST_STATE" ]; then
        log_info "Update detected."
        log_info "  Previous state: $LAST_STATE"
        log_info "  Current state:  $CURRENT_STATE"
    else
        log_info "No previous state found. Initializing baseline."
    fi
    UPDATE_DETECTED=true
fi

RESTORE_OK=0
RESTORE_FAIL=0
RESTORE_SKIP=0

for FILE in "${FILES[@]}"; do
    FULL_PATH="${TARGET_DIR}${FILE}"
    BACKUP_PATH="${FULL_PATH}.clean"

    if [ ! -f "$FULL_PATH" ]; then
        log_warn "Game file not found: $FULL_PATH — skipping."
        RESTORE_FAIL=$((RESTORE_FAIL + 1))
        continue
    fi

    if [ ! -f "$BACKUP_PATH" ] || [ "$UPDATE_DETECTED" = true ]; then
        if [ ! -f "$BACKUP_PATH" ]; then
            log_warn "No backup found for $FILE — creating from current game file. If the game was launched before, this backup may not be clean."
            ACTION="created"
        else
            ACTION="updated"
        fi

        cp "$FULL_PATH" "$BACKUP_PATH" || { log_error "Backup failed for $FILE"; RESTORE_FAIL=$((RESTORE_FAIL + 1)); continue; }

        grep -vF "$FILE.clean" "$CHECKSUM_FILE" > "${CHECKSUM_FILE}.tmp" 2>/dev/null || true
        sha256sum "$BACKUP_PATH" >> "${CHECKSUM_FILE}.tmp"
        mv "${CHECKSUM_FILE}.tmp" "$CHECKSUM_FILE"

        log_info "Backup ${ACTION}: $FILE"
        RESTORE_SKIP=$((RESTORE_SKIP + 1))
        continue
    fi

    EXPECTED=$(grep -F "$FILE.clean" "$CHECKSUM_FILE" | head -n1 | awk '{print $1}')
    ACTUAL=$(sha256sum "$BACKUP_PATH" | awk '{print $1}')

    if [ -z "$EXPECTED" ]; then
        log_warn "No reference checksum found for $FILE — overwriting backup with current game file (may be dirty)."
        cp "$FULL_PATH" "$BACKUP_PATH" || { log_error "Backup failed for $FILE"; RESTORE_FAIL=$((RESTORE_FAIL + 1)); continue; }
        sha256sum "$BACKUP_PATH" >> "$CHECKSUM_FILE"
        log_info "Backup overwritten and checksum stored: $FILE"
        RESTORE_SKIP=$((RESTORE_SKIP + 1))
        continue
    fi

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        log_warn "Backup checksum mismatch for $FILE — expected and actual hash differ. If the file is intact, delete $CHECKSUM_FILE to rebuild the reference."
        RESTORE_SKIP=$((RESTORE_SKIP + 1))
        continue
    fi

    cp "$BACKUP_PATH" "$FULL_PATH" || { log_error "Restore failed for $FILE"; RESTORE_FAIL=$((RESTORE_FAIL + 1)); continue; }
    RESTORE_OK=$((RESTORE_OK + 1))
done

TOTAL=$(( RESTORE_OK + RESTORE_FAIL + RESTORE_SKIP ))

if [ $RESTORE_FAIL -eq 0 ] && [ $RESTORE_SKIP -eq 0 ]; then
    log_info "All files restored successfully ($RESTORE_OK/$TOTAL)."
elif [ $RESTORE_FAIL -gt 0 ]; then
    log_warn "Run completed with errors — restored: $RESTORE_OK, failed: $RESTORE_FAIL, skipped: $RESTORE_SKIP (of $TOTAL watched files)."
else
    log_info "Run completed — restored: $RESTORE_OK, skipped: $RESTORE_SKIP (of $TOTAL watched files)."
fi

echo "$CURRENT_STATE" > "$VERSION_FILE"

# exec replaces the shell process — Steam correctly tracks the game process
if [ $# -gt 0 ]; then
    exec "$@"
fi
