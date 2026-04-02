#!/bin/bash
set -uo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

NOTIFY=false        # Desktop notifications via notify-send — set to false to disable
LOG_MAX_LINES=100   # Maximum number of lines to keep in the log file — oldest lines are removed

# ─── Logging / Notification ───────────────────────────────────────────────────

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LOG_FILE="$SCRIPT_DIR/gzw_autofix.log"

_ts() { date "+%Y-%m-%d %H:%M:%S"; }

{
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  GZW Autofix — $(_ts)"
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
        notify-send -a "GZW Autofix" -i dialog-information "GZW Autofix" "$msg" 2>/dev/null || true
    fi
}

log_warn() {
    local msg="$1"
    echo "[$(_ts)] [WARN]  $msg" >> "$LOG_FILE"
    if [ "$NOTIFY" = true ]; then
        notify-send -a "GZW Autofix" -i dialog-warning -u normal "GZW Autofix – Warning" "$msg" 2>/dev/null || true
    fi
}

log_error() {
    local msg="$1"
    echo "[$(_ts)] [ERROR] $msg" >> "$LOG_FILE"
    if [ "$NOTIFY" = true ]; then
        notify-send -a "GZW Autofix" -i dialog-error -u critical "GZW Autofix – Error" "$msg" 2>/dev/null || true
    fi
}

# ─── Auto-detect Steam library containing Gray Zone Warfare ───────────────────

GAME_SUBPATH="common/Gray Zone Warfare/GZW/Content/SKALLA/PrebuildWorldData/World/cache"
MANIFEST_NAME="appmanifest_2479810.acf"

STEAM_CANDIDATES=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"  # Flatpak
)

declare -A SEEN_VDFS
LIBRARYFOLDER_CANDIDATES=()
for BASE in "${STEAM_CANDIDATES[@]}"; do
    VDF="$BASE/steamapps/libraryfolders.vdf"
    [ ! -f "$VDF" ] && continue

    REAL_VDF=$(realpath "$VDF" 2>/dev/null || echo "$VDF")
    [ "${SEEN_VDFS[$REAL_VDF]+set}" = "set" ] && continue
    SEEN_VDFS["$REAL_VDF"]=1

    while IFS= read -r line; do
        PATH_VAL=$(echo "$line" | awk -F'"' '/"path"/{print $4}')
        if [ -n "$PATH_VAL" ]; then
            LIBRARYFOLDER_CANDIDATES+=("$PATH_VAL")
        fi
    done < "$VDF"
done

ALL_CANDIDATES=("${STEAM_CANDIDATES[@]}" ${LIBRARYFOLDER_CANDIDATES[@]+"${LIBRARYFOLDER_CANDIDATES[@]}"})

TARGET_DIR=""
MANIFEST=""
for CANDIDATE in "${ALL_CANDIDATES[@]}"; do
    if [ -d "$CANDIDATE/steamapps/$GAME_SUBPATH" ]; then
        TARGET_DIR="$CANDIDATE/steamapps/$GAME_SUBPATH/"
        MANIFEST="$CANDIDATE/steamapps/$MANIFEST_NAME"
        break
    fi
done

if [ -z "$TARGET_DIR" ]; then
    log_error "GZW installation not found. Searched in: ${ALL_CANDIDATES[*]}"
    exit 1
fi

log_info "GZW found at: $TARGET_DIR"

# ─── Guard: Script requires a launch command ─────────────────────────────────

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

    echo "${buildid}:${depot_manifests}"
}

# ─── Main logic ───────────────────────────────────────────────────────────────

FILES=("0xaf497c273f87b6e4_0x7a22fc105639587d.dat" "0xb9af63cee2e43b6c_0x3cb3b3354fb31606.dat")

CHECKSUM_FILE="${TARGET_DIR}.clean_checksums"
# Renamed from .last_known_buildid — format has changed, old file is incompatible.
# Delete .last_known_buildid manually if present to force a clean baseline on first run.
VERSION_FILE="${TARGET_DIR}.last_known_state"

if [ ! -f "$MANIFEST" ]; then
    log_error "Steam manifest not found: $MANIFEST"
    exit 1
fi

CURRENT_STATE=$(_read_game_state "$MANIFEST")

if [[ "$CURRENT_STATE" == ":"* ]] || [ -z "$CURRENT_STATE" ]; then
    log_error "Could not parse build ID or depot manifests from ACF. State: '${CURRENT_STATE}'"
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
        ((RESTORE_SKIP++))
        continue
    fi

    if [ ! -f "$BACKUP_PATH" ] || [ "$UPDATE_DETECTED" = true ]; then
        if [ ! -f "$BACKUP_PATH" ]; then
            log_warn "No backup found for $FILE — creating from current game file. If the game was launched before, this backup may not be clean."
            ACTION="created"
        else
            ACTION="updated"
        fi

        cp "$FULL_PATH" "$BACKUP_PATH" || { log_error "Backup failed for $FILE"; ((RESTORE_FAIL++)); continue; }

        grep -vF "$FILE.clean" "$CHECKSUM_FILE" > "${CHECKSUM_FILE}.tmp" 2>/dev/null || true
        sha256sum "$BACKUP_PATH" >> "${CHECKSUM_FILE}.tmp"
        mv "${CHECKSUM_FILE}.tmp" "$CHECKSUM_FILE"

        log_info "Backup ${ACTION}: $FILE"
        ((RESTORE_SKIP++))
        continue
    fi

    EXPECTED=$(grep -F "$FILE.clean" "$CHECKSUM_FILE" | head -n1 | awk '{print $1}')
    ACTUAL=$(sha256sum "$BACKUP_PATH" | awk '{print $1}')

    if [ -z "$EXPECTED" ]; then
        log_warn "No reference checksum found for $FILE — overwriting backup with current game file (may be dirty)."
        cp "$FULL_PATH" "$BACKUP_PATH" || { log_error "Backup failed for $FILE"; ((RESTORE_FAIL++)); continue; }
        sha256sum "$BACKUP_PATH" >> "$CHECKSUM_FILE"
        log_info "Backup overwritten and checksum stored: $FILE"
        ((RESTORE_SKIP++))
        continue
    fi

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        log_warn "Backup checksum mismatch for $FILE — expected and actual hash differ. If the file is intact, delete $CHECKSUM_FILE to rebuild the reference."
        ((RESTORE_SKIP++))
        continue
    fi

    cp "$BACKUP_PATH" "$FULL_PATH" || { log_error "Restore failed for $FILE"; ((RESTORE_FAIL++)); continue; }
    ((RESTORE_OK++))
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
#!/bin/bash
set -uo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

NOTIFY=false        # Desktop notifications via notify-send — set to false to disable
LOG_MAX_LINES=100   # Maximum number of lines to keep in the log file — oldest lines are removed

# ─── Logging / Notification ───────────────────────────────────────────────────

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LOG_FILE="$SCRIPT_DIR/gzw_autofix.log"

_ts() { date "+%Y-%m-%d %H:%M:%S"; }

{
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  GZW Autofix — $(_ts)"
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
        notify-send -a "GZW Autofix" -i dialog-information "GZW Autofix" "$msg" 2>/dev/null || true
    fi
}

log_warn() {
    local msg="$1"
    echo "[$(_ts)] [WARN]  $msg" >> "$LOG_FILE"
    if [ "$NOTIFY" = true ]; then
        notify-send -a "GZW Autofix" -i dialog-warning -u normal "GZW Autofix – Warning" "$msg" 2>/dev/null || true
    fi
}

log_error() {
    local msg="$1"
    echo "[$(_ts)] [ERROR] $msg" >> "$LOG_FILE"
    if [ "$NOTIFY" = true ]; then
        notify-send -a "GZW Autofix" -i dialog-error -u critical "GZW Autofix – Error" "$msg" 2>/dev/null || true
    fi
}

# ─── Auto-detect Steam library containing Gray Zone Warfare ───────────────────

GAME_SUBPATH="common/Gray Zone Warfare/GZW/Content/SKALLA/PrebuildWorldData/World/cache"
MANIFEST_NAME="appmanifest_2479810.acf"

STEAM_CANDIDATES=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"  # Flatpak
)

declare -A SEEN_VDFS
LIBRARYFOLDER_CANDIDATES=()
for BASE in "${STEAM_CANDIDATES[@]}"; do
    VDF="$BASE/steamapps/libraryfolders.vdf"
    [ ! -f "$VDF" ] && continue

    REAL_VDF=$(realpath "$VDF" 2>/dev/null || echo "$VDF")
    [ "${SEEN_VDFS[$REAL_VDF]+set}" = "set" ] && continue
    SEEN_VDFS["$REAL_VDF"]=1

    while IFS= read -r line; do
        PATH_VAL=$(echo "$line" | awk -F'"' '/"path"/{print $4}')
        if [ -n "$PATH_VAL" ]; then
            LIBRARYFOLDER_CANDIDATES+=("$PATH_VAL")
        fi
    done < "$VDF"
done

ALL_CANDIDATES=("${STEAM_CANDIDATES[@]}" ${LIBRARYFOLDER_CANDIDATES[@]+"${LIBRARYFOLDER_CANDIDATES[@]}"})

TARGET_DIR=""
MANIFEST=""
for CANDIDATE in "${ALL_CANDIDATES[@]}"; do
    if [ -d "$CANDIDATE/steamapps/$GAME_SUBPATH" ]; then
        TARGET_DIR="$CANDIDATE/steamapps/$GAME_SUBPATH/"
        MANIFEST="$CANDIDATE/steamapps/$MANIFEST_NAME"
        break
    fi
done

if [ -z "$TARGET_DIR" ]; then
    log_error "GZW installation not found. Searched in: ${ALL_CANDIDATES[*]}"
    exit 1
fi

log_info "GZW found at: $TARGET_DIR"

# ─── Guard: Script requires a launch command ─────────────────────────────────

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

    echo "${buildid}:${depot_manifests}"
}

# ─── Main logic ───────────────────────────────────────────────────────────────

FILES=("0xaf497c273f87b6e4_0x7a22fc105639587d.dat" "0xb9af63cee2e43b6c_0x3cb3b3354fb31606.dat")

CHECKSUM_FILE="${TARGET_DIR}.clean_checksums"
# Renamed from .last_known_buildid — format has changed, old file is incompatible.
# Delete .last_known_buildid manually if present to force a clean baseline on first run.
VERSION_FILE="${TARGET_DIR}.last_known_state"

if [ ! -f "$MANIFEST" ]; then
    log_error "Steam manifest not found: $MANIFEST"
    exit 1
fi

CURRENT_STATE=$(_read_game_state "$MANIFEST")

if [[ "$CURRENT_STATE" == ":"* ]] || [ -z "$CURRENT_STATE" ]; then
    log_error "Could not parse build ID or depot manifests from ACF. State: '${CURRENT_STATE}'"
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

for FILE in "${FILES[@]}"; do
    FULL_PATH="${TARGET_DIR}${FILE}"
    BACKUP_PATH="${FULL_PATH}.clean"

    if [ ! -f "$FULL_PATH" ]; then
        log_warn "Game file not found: $FULL_PATH — skipping."
        ((RESTORE_FAIL++))
        continue
    fi

    if [ ! -f "$BACKUP_PATH" ] || [ "$UPDATE_DETECTED" = true ]; then
        if [ ! -f "$BACKUP_PATH" ]; then
            log_warn "No backup found for $FILE — creating from current state. If the game was launched before, this backup may not be clean."
        fi

        cp "$FULL_PATH" "$BACKUP_PATH" || { log_error "Backup failed for $FILE"; ((RESTORE_FAIL++)); continue; }

        grep -vF "$FILE.clean" "$CHECKSUM_FILE" > "${CHECKSUM_FILE}.tmp" 2>/dev/null || true
        sha256sum "$BACKUP_PATH" >> "${CHECKSUM_FILE}.tmp"
        mv "${CHECKSUM_FILE}.tmp" "$CHECKSUM_FILE"

        log_info "Backup created/updated: $FILE"
        continue
    fi

    EXPECTED=$(grep -F "$FILE.clean" "$CHECKSUM_FILE" | head -n1 | awk '{print $1}')
    ACTUAL=$(sha256sum "$BACKUP_PATH" | awk '{print $1}')

    if [ -z "$EXPECTED" ]; then
        log_warn "No checksum found for $FILE — recreating backup. If the game was launched before, this backup may not be clean."
        cp "$FULL_PATH" "$BACKUP_PATH" || { log_error "Backup failed for $FILE"; ((RESTORE_FAIL++)); continue; }
        sha256sum "$BACKUP_PATH" >> "$CHECKSUM_FILE"
        continue
    fi

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        log_warn "Backup for $FILE is corrupted. Delete ${BACKUP_PATH} to force a reset on next launch."
        ((RESTORE_FAIL++))
        continue
    fi

    cp "$BACKUP_PATH" "$FULL_PATH" || { log_error "Restore failed for $FILE"; ((RESTORE_FAIL++)); continue; }
    ((RESTORE_OK++))
done

TOTAL=$(( RESTORE_OK + RESTORE_FAIL ))
if [ $RESTORE_FAIL -eq 0 ]; then
    log_info "Watched files ok ($RESTORE_OK/$TOTAL restored)"
fi

echo "$CURRENT_STATE" > "$VERSION_FILE"

# exec replaces the shell process — Steam correctly tracks the game process
if [ $# -gt 0 ]; then
    exec "$@"
fi
