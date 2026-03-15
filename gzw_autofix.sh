#!/bin/bash
set -uo pipefail

# ─── Logging / Notification ───────────────────────────────────────────────────
# Warnungen und Fehler werden als Desktop-Notification angezeigt (notify-send)
# sowie in /tmp/gzw_autofix.log geschrieben.

LOG_FILE="/tmp/gzw_autofix.log"
: > "$LOG_FILE"

log_info() {
    local msg="$1"
    echo "[INFO]  $msg" >> "$LOG_FILE"
    notify-send -a "GZW Autofix" -i dialog-information "GZW Autofix" "$msg" 2>/dev/null || true
}

log_warn() {
    local msg="$1"
    echo "[WARN]  $msg" >> "$LOG_FILE"
    notify-send -a "GZW Autofix" -i dialog-warning -u normal "GZW Autofix – Warnung" "$msg" 2>/dev/null || true
}

log_error() {
    local msg="$1"
    echo "[ERROR] $msg" >> "$LOG_FILE"
    notify-send -a "GZW Autofix" -i dialog-error -u critical "GZW Autofix – Fehler" "$msg" 2>/dev/null || true
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

ALL_CANDIDATES=("${STEAM_CANDIDATES[@]}" "${LIBRARYFOLDER_CANDIDATES[@]}")

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
    log_error "GZW-Installation nicht gefunden. Durchsucht: ${ALL_CANDIDATES[*]}"
    exit 1
fi

log_info "GZW gefunden: $TARGET_DIR"

# ─── Guard: Script requires a launch command ─────────────────────────────────

if [ $# -eq 0 ]; then
    log_warn "Kein Startbefehl übergeben — Dateien werden wiederhergestellt, Spiel wird nicht gestartet."
fi

# ─── Main logic ───────────────────────────────────────────────────────────────

FILES=("0xaf497c273f87b6e4_0x7a22fc105639587d.dat" "0xb9af63cee2e43b6c_0x3cb3b3354fb31606.dat")

CHECKSUM_FILE="${TARGET_DIR}.clean_checksums"
VERSION_FILE="${TARGET_DIR}.last_known_buildid"

if [ ! -f "$MANIFEST" ]; then
    log_error "Steam-Manifest nicht gefunden: $MANIFEST"
    exit 1
fi

# FIX: -m1 verhindert mehrzeiligen CURRENT_BUILDID bei mehrfachem "buildid"-Key im ACF
CURRENT_BUILDID=$(grep -m1 "buildid" "$MANIFEST" | awk -F'"' '{print $4}')

if [ -z "$CURRENT_BUILDID" ]; then
    log_error "BuildID konnte nicht aus dem Manifest gelesen werden."
    exit 1
fi

LAST_BUILDID=$(cat "$VERSION_FILE" 2>/dev/null || echo "")

UPDATE_DETECTED=false
if [ "$CURRENT_BUILDID" != "$LAST_BUILDID" ]; then
    log_info "Neuer Build erkannt: $CURRENT_BUILDID (vorher: ${LAST_BUILDID:-keiner})"
    UPDATE_DETECTED=true
fi

for FILE in "${FILES[@]}"; do
    FULL_PATH="${TARGET_DIR}${FILE}"
    BACKUP_PATH="${FULL_PATH}.clean"

    if [ ! -f "$FULL_PATH" ]; then
        log_warn "Spieldatei nicht gefunden: $FULL_PATH — übersprungen."
        continue
    fi

    if [ ! -f "$BACKUP_PATH" ] || [ "$UPDATE_DETECTED" = true ]; then
        if [ ! -f "$BACKUP_PATH" ]; then
            log_warn "Kein Backup für $FILE — wird aus aktuellem Zustand erstellt. Falls das Spiel bereits gelaufen ist, ist dieses Backup möglicherweise nicht sauber."
        fi

        cp "$FULL_PATH" "$BACKUP_PATH" || { log_error "Backup fehlgeschlagen für $FILE"; continue; }

        grep -vF "$FILE.clean" "$CHECKSUM_FILE" > "${CHECKSUM_FILE}.tmp" 2>/dev/null
        sha256sum "$BACKUP_PATH" >> "${CHECKSUM_FILE}.tmp"
        mv "${CHECKSUM_FILE}.tmp" "$CHECKSUM_FILE"

        log_info "Backup erstellt/aktualisiert: $FILE (BuildID: $CURRENT_BUILDID)"
        continue
    fi

    EXPECTED=$(grep -F "$FILE.clean" "$CHECKSUM_FILE" | head -n1 | awk '{print $1}')
    ACTUAL=$(sha256sum "$BACKUP_PATH" | awk '{print $1}')

    if [ -z "$EXPECTED" ]; then
        log_warn "Kein Checksum für $FILE — Backup wird neu erstellt. Falls das Spiel bereits gelaufen ist, ist dieses Backup möglicherweise nicht sauber."
        cp "$FULL_PATH" "$BACKUP_PATH" || { log_error "Backup fehlgeschlagen für $FILE"; continue; }
        sha256sum "$BACKUP_PATH" >> "$CHECKSUM_FILE"
        continue
    fi

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        log_warn "Backup für $FILE ist beschädigt! Lösche ${BACKUP_PATH} um beim nächsten Start zurückzusetzen."
        continue
    fi

    cp "$BACKUP_PATH" "$FULL_PATH" || { log_error "Wiederherstellen fehlgeschlagen für $FILE"; continue; }
    log_info "Saubere Version wiederhergestellt: $FILE"
done

# Build ID für nächsten Start speichern
echo "$CURRENT_BUILDID" > "$VERSION_FILE"

# exec ersetzt den Shell-Prozess — Steam erkennt den Spielprozess korrekt
if [ $# -gt 0 ]; then
    exec "$@"
fi#!/bin/bash

# ─── Auto-detect Steam library containing Gray Zone Warfare ───────────────────

# FIX: GAME_SUBPATH must NOT start with steamapps/ — that is appended separately
GAME_SUBPATH="common/Gray Zone Warfare/GZW/Content/SKALLA/PrebuildWorldData/World/cache"
MANIFEST_NAME="appmanifest_2479810.acf"

# Common Steam library locations
STEAM_CANDIDATES=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"  # Flatpak
)

# FIX: Deduplicate candidates by resolving symlinks before comparing
declare -A SEEN_VDFS
LIBRARYFOLDER_CANDIDATES=()
for BASE in "${STEAM_CANDIDATES[@]}"; do
    VDF="$BASE/steamapps/libraryfolders.vdf"
    [ ! -f "$VDF" ] && continue

    # FIX: Resolve symlinks to avoid parsing the same VDF twice
    REAL_VDF=$(realpath "$VDF" 2>/dev/null || echo "$VDF")
    [ "${SEEN_VDFS[$REAL_VDF]+set}" = "set" ] && continue
    SEEN_VDFS["$REAL_VDF"]=1

    # FIX: Use awk instead of grep -oP (no PCRE dependency)
    while IFS= read -r line; do
        PATH_VAL=$(echo "$line" | awk -F'"' '/"path"/{print $4}')
        if [ -n "$PATH_VAL" ]; then
            LIBRARYFOLDER_CANDIDATES+=("$PATH_VAL")
        fi
    done < "$VDF"
done

# Merge all candidates
ALL_CANDIDATES=("${STEAM_CANDIDATES[@]}" "${LIBRARYFOLDER_CANDIDATES[@]}")

# Find the actual library containing GZW
# FIX: Only one check needed — $CANDIDATE/steamapps/$GAME_SUBPATH is always the correct structure
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
    echo "ERROR: Gray Zone Warfare installation not found."
    echo "       Searched in: ${ALL_CANDIDATES[*]}"
    exit 1
fi

echo "Found GZW at: $TARGET_DIR"

# ─── Main logic ───────────────────────────────────────────────────────────────

FILES=("0xaf497c273f87b6e4_0x7a22fc105639587d.dat" "0xb9af63cee2e43b6c_0x3cb3b3354fb31606.dat")

CHECKSUM_FILE="${TARGET_DIR}.clean_checksums"
VERSION_FILE="${TARGET_DIR}.last_known_buildid"

# Check if manifest exists
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: Steam manifest not found at $MANIFEST — aborting."
    exit 1
fi

# Read current Steam build ID from manifest
CURRENT_BUILDID=$(grep "buildid" "$MANIFEST" | awk -F'"' '{print $4}')

if [ -z "$CURRENT_BUILDID" ]; then
    echo "ERROR: Could not read buildid from manifest — aborting."
    exit 1
fi

LAST_BUILDID=$(cat "$VERSION_FILE" 2>/dev/null || echo "")

UPDATE_DETECTED=false
if [ "$CURRENT_BUILDID" != "$LAST_BUILDID" ]; then
    echo "New build detected: $CURRENT_BUILDID (was: ${LAST_BUILDID:-none})"
    UPDATE_DETECTED=true
fi

for FILE in "${FILES[@]}"; do
    FULL_PATH="${TARGET_DIR}${FILE}"
    BACKUP_PATH="${FULL_PATH}.clean"

    if [ ! -f "$FULL_PATH" ]; then
        echo "WARNING: Game file not found: $FULL_PATH — skipping."
        continue
    fi

    if [ ! -f "$BACKUP_PATH" ] || [ "$UPDATE_DETECTED" = true ]; then
        cp "$FULL_PATH" "$BACKUP_PATH" || { echo "ERROR: Backup copy failed for $FILE"; continue; }

        grep -vF "$FILE.clean" "$CHECKSUM_FILE" > "${CHECKSUM_FILE}.tmp" 2>/dev/null
        sha256sum "$BACKUP_PATH" >> "${CHECKSUM_FILE}.tmp"
        mv "${CHECKSUM_FILE}.tmp" "$CHECKSUM_FILE"

        echo "Backup created/updated for $FILE (BuildID: $CURRENT_BUILDID)"
        continue
    fi

    EXPECTED=$(grep -F "$FILE.clean" "$CHECKSUM_FILE" | head -n1 | awk '{print $1}')
    ACTUAL=$(sha256sum "$BACKUP_PATH" | awk '{print $1}')

    if [ -z "$EXPECTED" ]; then
        echo "WARNING: No checksum found for $FILE — recreating backup."
        cp "$FULL_PATH" "$BACKUP_PATH" || { echo "ERROR: Backup copy failed for $FILE"; continue; }
        sha256sum "$BACKUP_PATH" >> "$CHECKSUM_FILE"
        continue
    fi

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "WARNING: Backup for $FILE is corrupted!"
        echo "         Delete ${BACKUP_PATH} to force reset on next launch."
        continue
    fi

    cp "$BACKUP_PATH" "$FULL_PATH" || { echo "ERROR: Restore failed for $FILE"; continue; }
    echo "Restored clean version of $FILE"
done

# Save current build ID for next launch
echo "$CURRENT_BUILDID" > "$VERSION_FILE"

# Launch game
"$@"

# Flush write buffers after game exits
sync
