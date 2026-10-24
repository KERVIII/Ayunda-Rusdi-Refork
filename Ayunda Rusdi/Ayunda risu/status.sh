#!/system/bin/sh
# Single read-only snapshot for the WebUI: key=value lines + preset rows.
# Reports only what is actually detected. Never modifies anything.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

echo "version=$(grep -m1 '^version=' "$DIR/../module.prop" 2>/dev/null | cut -d= -f2-)"
if [ -f "$STATE_FILE" ] && read_state; then
    echo "state_read=1"
    if validate_state; then echo "state_valid=1"; else echo "state_valid=0"; fi
    echo "module_state=$MODULE_STATE"
    echo "active_preset=$ACTIVE_PRESET"
    echo "active_value=$ACTIVE_VALUE"
    echo "custom_value=$CUSTOM_VALUE"
else
    echo "state_read=0"
fi
if service_available; then echo "backend=1"; else echo "backend=0"; fi
echo "transaction=1022"
echo "min=$MIN_VAL"; echo "max=$MAX_VAL"
# verification: persisted state coherent AND backend reachable. (SurfaceFlinger
# offers no saturation read-back, so the live screen value cannot be read.)
if [ -f "$STATE_FILE" ] && read_state && validate_state && service_available; then echo "verify=PASS"; else echo "verify=FAIL"; fi
echo "android=$(getprop ro.build.version.release 2>/dev/null)"
echo "sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
echo "model=$(getprop ro.product.model 2>/dev/null)"
if [ -d /data/adb/ksu ] || [ -n "$KSU" ]; then echo "root=KernelSU"
elif [ -d /data/adb/ap ]; then echo "root=APatch"
elif command -v magisk >/dev/null 2>&1; then echo "root=Magisk"
else echo "root=unknown"; fi
# The probes below are independent and read-only; several spawn slow system
# processes (settings get x3, pm list packages, dumpsys). Run them concurrently
# and print their output in the original order. Falls back to the sequential
# path if the scratch dir cannot be created.
_T="/dev/.risu_st.$$"
if mkdir "$_T" 2>/dev/null; then
    trap 'rm -rf "$_T"' EXIT
    sh "$DIR/ui_tweaks.sh" status >"$_T/1" 2>/dev/null &
    sh "$DIR/refresh.sh" status >"$_T/2" 2>/dev/null &
    sh "$DIR/favorites.sh" list >"$_T/3" 2>/dev/null &
    sh "$DIR/profile.sh" list >"$_T/4" 2>/dev/null &
    sh "$DIR/watcher.sh" status >"$_T/5" 2>/dev/null &
    # presets are a local file read: compute them while the probes run
    if validate_presets_conf 2>/dev/null; then
        _P="presets_ok=1
$(awk -F'|' '/^#/ || NF==0 {next} NF==4 {print "preset=" $0}' "$CONF")"
    else
        _P="presets_ok=0"
    fi
    wait
    cat "$_T/1" "$_T/2" 2>/dev/null
    echo "$_P"
    while IFS= read -r _f; do echo "favorite=$_f"; done < "$_T/3"
    cat "$_T/4" "$_T/5" 2>/dev/null
else
    sh "$DIR/ui_tweaks.sh" status 2>/dev/null
    sh "$DIR/refresh.sh" status 2>/dev/null
    if validate_presets_conf 2>/dev/null; then
        echo "presets_ok=1"
        awk -F'|' '/^#/ || NF==0 {next} NF==4 {print "preset=" $0}' "$CONF"
    else
        echo "presets_ok=0"
    fi
    sh "$DIR/favorites.sh" list 2>/dev/null | while IFS= read -r _f; do echo "favorite=$_f"; done
    sh "$DIR/profile.sh" list 2>/dev/null
    sh "$DIR/watcher.sh" status 2>/dev/null
fi
exit 0   # snapshot only: callers treat any non-zero exit as "cannot read state"
