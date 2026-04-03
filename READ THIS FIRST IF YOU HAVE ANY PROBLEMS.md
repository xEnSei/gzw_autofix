Here's how to set it up from scratch:

**1. Clean up old files**

Delete this files:
```
<cache>/.last_known_buildid — last known Steam build ID
<cache>/.clean_checksums — SHA256 checksums of the backup files
<cache>/0xaf497c273f87b6e4_0x7a22fc105639587d.dat.clean — backup of cache file 1
<cache>/0xb9af63cee2e43b6c_0x3cb3b3354fb31606.dat.clean — backup of cache file 2
```
Where ```<cache>``` expands to:
```<Steam library>/steamapps/common/Gray Zone Warfare/GZW/Content/SKALLA/PrebuildWorldData/World/cache/```

Then in Steam: right-click Gray Zone Warfare → Properties → Local Files → **Verify integrity of game files**. This makes sure the cache files are clean before the script runs for the first time.

**2. Download the script**
Run these three lines one at a time, pressing Enter after each:
```
mkdir -p ~/gscript
curl -o ~/gscript/gzw_autofix.sh https://raw.githubusercontent.com/xEnSei/gzw_autofix/main/gzw_autofix.sh
chmod +x ~/gscript/gzw_autofix.sh
```

**3. Set Steam launch options**
Right-click Gray Zone Warfare → Properties → General → Launch Options.

Enter exactly this (nothing else):
```
~/gscript/gzw_autofix.sh %command%
```
If you also want mangohud:
```
~/gscript/gzw_autofix.sh mangohud %command%
```

**4. Test the script**
Before launching the game, run the script once directly in the terminal:
```
~/gscript/gzw_autofix.sh
```
Then check the log:
```
cat ~/gscript/gzw_autofix.log
```
If you see `Backup created: ...` and no `ERROR`, everything is set up correctly.

**5. Launch the game**
Start normally through Steam.

