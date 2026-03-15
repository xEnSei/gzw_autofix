# GZW Cache Autofix

Steam launch script for Gray Zone Warfare (Linux/Proton) that prevents cache file
corruption caused by incomplete writes during game shutdown.

## What it does

- Restores clean cache backups before each launch
- Validates backup integrity via SHA256 before trusting it
- Reads Steam's `appmanifest` build ID to detect game updates and refresh backups automatically

## Usage

Steam launch options:
```
~/gscript/gzw_autofix.sh %command%
```

Example with additional tools:
```
PROTON_ENABLE_NVAPI=1 ~/gscript/gzw_autofix.sh gamemoderun mangohud obs-vkcapture %command%
```

## Logging

Errors and warnings are shown as desktop notifications via `notify-send`.  
Full log per session: `/tmp/gzw_autofix.log`

## Disclaimer

Provided as-is, no warranty. The author is not responsible for data loss or file
corruption. Keep your own backups before using third-party scripts.

## License

MIT © xEnSei
