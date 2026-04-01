## The new gzw_autofix.sh
**Improved update detection**
The new script detects updates via the `buildid` field in the Steam ACF manifest. Valve does not increment `buildid` on every depot-level change, so stealth fixes (new file content, same build tag) go undetected.

The new version additionally reads all depot manifest IDs from the `InstalledDepots` block of the ACF and combines them into a single state string (`buildid:manifestA:manifestB:...`). Depot manifests change on every content update regardless of the build tag.

**State file rename**
`.last_known_buildid` → `.last_known_state`. The format is incompatible with the old file; the first run initializes a new baseline automatically. The old file does not need to be deleted.

# GZW Cache Autofix

Steam launch script for Gray Zone Warfare (Linux/Proton) that prevents cache file
corruption caused by incomplete writes during game shutdown.
You can also run the script normally in the console and see if it detects everything correctly; just check the log file later.

## What it does

- Restores clean cache backups before each launch
- Validates backup integrity via SHA256 before trusting it
- Reads Steam's `appmanifest` build ID to detect game updates and refresh backups automatically

## Requirements

- `libnotify` optional — if not installed, all output is written to `gzw_autofix.log` in the script directory (`sudo pacman -S libnotify` on Arch-based distros)

## Installation

1. Have Steam re-verify the game files via *Properties → Local Files → Verify integrity*
2. Download the script and make it executable:

```bash
mkdir -p ~/gscript
curl -o ~/gscript/gzw_autofix.sh https://raw.githubusercontent.com/xEnSei/gzw_autofix/main/gzw_autofix.sh
chmod +x ~/gscript/gzw_autofix.sh
```

3. Set the Steam launch options for Gray Zone Warfare:

```
~/gscript/gzw_autofix.sh %command%
```

Example with additional tools:

```
PROTON_ENABLE_NVAPI=1 ~/gscript/gzw_autofix.sh mangohud obs-vkcapture %command%
```

## Files

**Placed by the user:**
- `~/gscript/gzw_autofix.sh` — the script

**Created by the script:**
- `~/gscript/gzw_autofix.log` — log file (appended on every launch, capped at 100 lines by default)
- `<cache>/.last_known_buildid` — last known Steam build ID
- `<cache>/.clean_checksums` — SHA256 checksums of the backup files
- `<cache>/0xaf497c273f87b6e4_0x7a22fc105639587d.dat.clean` — backup of cache file 1
- `<cache>/0xb9af63cee2e43b6c_0x3cb3b3354fb31606.dat.clean` — backup of cache file 2

Where `<cache>` expands to:
```
<Steam library>/steamapps/common/Gray Zone Warfare/GZW/Content/SKALLA/PrebuildWorldData/World/cache/
```

## Logging

Each run is appended to `~/gscript/gzw_autofix.log` and separated by a timestamped header.
Desktop notifications are shown via `notify-send` if installed.

Two options can be configured at the top of the script:

| Option | Default | Description |
|---|---|---|
| `NOTIFY` | `false` | Set to `true` to disable desktop notifications |
| `LOG_MAX_LINES` | `100` | Maximum number of lines retained in the log file |

## Disclaimer

Provided as-is, no warranty. The author is not responsible for data loss or file
corruption. Keep your own backups before using third-party scripts.

## License

MIT © xEnSei
