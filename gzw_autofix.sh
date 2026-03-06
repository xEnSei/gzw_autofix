#!/bin/bash

TARGET_DIR="/mnt/ssd1tb/SteamLibrary/steamapps/common/Gray Zone Warfare/GZW/Content/SKALLA/PrebuildWorldData/World/cache/"
FILES=("0xaf497c273f87b6e4_0x7a22fc105639587d.dat" "0xb9af63cee2e43b6c_0x3cb3b3354fb31606.dat")

CHECKSUM_FILE="${TARGET_DIR}.clean_checksums"
MANIFEST="/mnt/ssd1tb/SteamLibrary/steamapps/appmanifest_2479810.acf"
VERSION_FILE="${TARGET_DIR}.last_known_buildid"

# FIX: Check if manifest exists before reading it
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

    # Check if source file exists at all
    if [ ! -f "$FULL_PATH" ]; then
        echo "WARNING: Game file not found: $FULL_PATH — skipping."
        continue
    fi

    if [ ! -f "$BACKUP_PATH" ] || [ "$UPDATE_DETECTED" = true ]; then
        cp "$FULL_PATH" "$BACKUP_PATH" || { echo "ERROR: Backup copy failed for $FILE"; continue; }

        # FIX: Use -F (fixed string) to avoid regex dot-wildcard bug
        # FIX: Rebuild checksum file cleanly to avoid duplicate entries
        grep -vF "$FILE.clean" "$CHECKSUM_FILE" > "${CHECKSUM_FILE}.tmp" 2>/dev/null
        sha256sum "$BACKUP_PATH" >> "${CHECKSUM_FILE}.tmp"
        mv "${CHECKSUM_FILE}.tmp" "$CHECKSUM_FILE"

        echo "Backup created/updated for $FILE (BuildID: $CURRENT_BUILDID)"
        continue  # File is fresh from Steam, no restore needed
    fi

    # FIX: Use -F (fixed string) and -m1 (max 1 match) to avoid duplicate-entry issues
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

    # Restore clean file before game starts
    cp "$BACKUP_PATH" "$FULL_PATH" || { echo "ERROR: Restore failed for $FILE"; continue; }
    echo "Restored clean version of $FILE"
done

# Save current build ID for next launch
echo "$CURRENT_BUILDID" > "$VERSION_FILE"

# Launch game with all passed arguments
"$@"

# Flush write buffers after game exits
sync
