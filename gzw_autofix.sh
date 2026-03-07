#!/bin/bash

# ─── Auto-detect Steam library containing Gray Zone Warfare ───────────────────

GAME_SUBPATH="steamapps/common/Gray Zone Warfare/GZW/Content/SKALLA/PrebuildWorldData/World/cache"
MANIFEST_NAME="appmanifest_2479810.acf"

# Common Steam library locations
STEAM_CANDIDATES=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"  # Flatpak
)

# Also check libraryfolders.vdf for additional Steam library paths
LIBRARYFOLDER_CANDIDATES=()
for BASE in "${STEAM_CANDIDATES[@]}"; do
    VDF="$BASE/steamapps/libraryfolders.vdf"
    if [ -f "$VDF" ]; then
        # Extract all "path" entries from libraryfolders.vdf
        while IFS= read -r line; do
            PATH_VAL=$(echo "$line" | grep -oP '(?<="path"\s{1,10}")([^"]+)')
            if [ -n "$PATH_VAL" ]; then
                LIBRARYFOLDER_CANDIDATES+=("$PATH_VAL")
            fi
        done < "$VDF"
    fi
done

# Merge all candidates
ALL_CANDIDATES=("${STEAM_CANDIDATES[@]}" "${LIBRARYFOLDER_CANDIDATES[@]}")

# Find the actual library containing GZW
TARGET_DIR=""
MANIFEST=""
for CANDIDATE in "${ALL_CANDIDATES[@]}"; do
    if [ -d "$CANDIDATE/steamapps/$GAME_SUBPATH" ] 2>/dev/null || \
       [ -d "$CANDIDATE/$GAME_SUBPATH" ] 2>/dev/null; then

        # Determine correct base
        if [ -d "$CANDIDATE/steamapps/$GAME_SUBPATH" ]; then
            TARGET_DIR="$CANDIDATE/steamapps/$GAME_SUBPATH/"
            MANIFEST="$CANDIDATE/steamapps/$MANIFEST_NAME"
        else
            TARGET_DIR="$CANDIDATE/$GAME_SUBPATH/"
            MANIFEST="$CANDIDATE/steamapps/$MANIFEST_NAME"
        fi
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
