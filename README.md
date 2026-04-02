# GZW Cache Autofix

Steam launch script for Gray Zone Warfare (Linux/Proton) that prevents cache file
corruption caused by incomplete writes during game shutdown.
You can also run the script manually in the console and verify detection via the log file afterwards.

## What it does

- Restores clean cache backups before each launch
- Validates backup integrity via SHA256 before trusting it
- Detects game updates by combining the Steam `buildid` with all depot manifest IDs from the `InstalledDepots` block of the ACF — depot manifests change on every content update regardless of the build tag

## Requirements

- `libnotify` optional — if not installed, all output is also written to `gzw_autofix.log` in the script directory (`sudo pacman -S libnotify` on Arch-based distros)

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

Example:

```
PROTON_ENABLE_NVAPI=1 ~/gscript/gzw_autofix.sh mangohud obs-vkcapture %command%
```

## Files

**Placed by the user:**
- `~/gscript/gzw_autofix.sh` — the script

**Created by the script:**
- `~/gscript/gzw_autofix.log` — log file (appended on every launch, capped at 100 lines by default)
- `<cache>/.last_known_state` — last known game state (build ID + depot manifest IDs)
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
| `NOTIFY` | `false` | Set to `true` to enable desktop notifications |
| `LOG_MAX_LINES` | `100` | Maximum number of lines retained in the log file |

## Disclaimer

Provided as-is, no warranty. The author is not responsible for data loss or file
corruption. Keep your own backups before using third-party scripts.

## License

MIT © xEnSei
