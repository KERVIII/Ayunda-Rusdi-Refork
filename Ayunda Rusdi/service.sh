#!/system/bin/sh
MODULE_DIR="${0%/*}"
# Wait for boot, then re-apply the persisted preset (no loops after that).
n=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
    n=$((n + 1))
    [ "$n" -ge 120 ] && exit 0   # give up after ~10 min instead of looping forever
done
sleep 3
# bounded retry (max 3 tries) in case SurfaceFlinger is not ready yet
for _try in 1 2 3; do
    sh "$MODULE_DIR/AyundaRisu/ModuleOn.sh" && break
    sleep 5
done
# per-app profile listener: starts only if automatic switching is on and a profile exists
sh "$MODULE_DIR/AyundaRisu/watcher.sh" sync >/dev/null 2>&1
