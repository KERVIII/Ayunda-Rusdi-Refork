#!/system/bin/sh
# Runs only on explicit module removal (not on updates).
MD="$(dirname "$0")/AyundaRisu"
[ -d "$MD" ] || MD=/data/adb/modules/AyundaRusdi/AyundaRisu
sh "$MD/watcher.sh" stop >/dev/null 2>&1       # stop the per-app listener first
sh "$MD/ui_tweaks.sh" reset >/dev/null 2>&1   # restore original animation scales if we changed them
service call SurfaceFlinger 1022 f 1.0 >/dev/null 2>&1
rm -rf "${STATEDIR:-/data/adb/risu-color-enhancer}"
