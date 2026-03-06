# 🛡️ GZW Cache Autofix

> A Steam launch script for **Gray Zone Warfare (Linux/Proton)** that prevents cache file corruption caused by incomplete writes during game shutdown.

---

## ✨ Features

- 🔄 **Auto-restore** — Restores clean cache backups before each launch
- 🔒 **SHA256 validation** — Verifies backup integrity before trusting it
- 🔍 **Update detection** — Reads Steam's `appmanifest` build ID to detect game updates and refresh backups automatically instead of blindly overwriting them

---

## 🚀 Usage

Add to your Steam launch options:

```
~/gscript/gzw_autofix.sh %command%

My for example:
PROTON_ENABLE_NVAPI=1 ~/gscript/gzw_autofix.sh gamemoderun mangohud obs-vkcapture %command%
```

> Adjust the parameters to your own setup as needed.

---

## ⚠️ Disclaimer

This script is provided **as-is**, without any warranty of any kind.
Use it at your own risk. The author is not responsible for any data loss, game file corruption, or any other damage that may result from using this script.

> Always make sure you have your own backups before using third-party scripts.

---

## 📄 License

MIT © [xEnSei]([https://github.com/YourGitHubUsername](https://github.com/xEnSei))
