#!/system/bin/sh
# Clear Cache: removes only temporary files this module itself leaves behind.
#   cache.sh status   dry run: how many items / bytes `clear` would remove (read-only)
#   cache.sh clear
# REMOVED (all inside the module's own data dir, nothing else is ever touched):
#   - orphaned atomic-write temp files  *.tmp.<pid>  and  .tw_err.<pid> / .rf_err.<pid>,
#     only when the owning pid is no longer alive
#   - a stale per-app listener lock (.watcher.lock) whose pid is dead / not our watcher
#   - the listener's runtime snapshot (tmpfs /dev/.risu_watch_state and .runstate),
#     only when no listener is running; it is rebuilt on the next foreground change
# PRESERVED: state.conf (active preset/value), profiles.conf (app mappings), autoswitch,
#   favorites.conf, ui_tweaks.conf, refresh.conf (backups needed to restore settings),
#   override (live per-app marker), errors.log (diagnostic history), module files,
#   WebView/app data, Android caches, and every file outside the module data dir.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

N=0; BYTES=0; FAILED=0
ITEMS="/dev/.risu_cache_items.$$"   # scratch list on tmpfs; cleanup and the dry run share scan()
pid_alive() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; kill -0 "$1" 2>/dev/null; }

# scan(): list every removable path, one per line, into $ITEMS. The single source
# of truth: `status` (dry run) reports exactly what `clear` would delete.
scan() {
    : > "$ITEMS" || return 1
    # orphaned temp files: the suffix is the writer's pid
    for _f in "$STATEDIR"/*.tmp.* "$STATEDIR"/.tw_err.* "$STATEDIR"/.rf_err.*; do
        [ -f "$_f" ] || continue
        pid_alive "${_f##*.}" && continue
        echo "$_f" >> "$ITEMS"
    done
    # stale listener lock
    _wl="$STATEDIR/.watcher.lock"; _wp=""
    if [ -d "$_wl" ]; then
        _wp=$(cat "$_wl/pid" 2>/dev/null)
        if ! pid_alive "$_wp" || ! tr '\0' ' ' < "/proc/$_wp/cmdline" 2>/dev/null | grep -q 'watcher\.sh'; then
            echo "$_wl" >> "$ITEMS"; _wp=""
        fi
    fi
    # runtime snapshot: only when no listener is running
    if [ -z "$_wp" ]; then
        for _f in "${RUNSTATE_FILE:-/dev/.risu_watch_state}" "$STATEDIR/.runstate"; do
            [ -e "$_f" ] && echo "$_f" >> "$ITEMS"
        done
    fi
    return 0
}
item_bytes() { [ -f "$1" ] && wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

cmd_status() { # dry run, read-only
    [ -d "$STATEDIR" ] || { echo "cache_items=0"; echo "cache_bytes=0"; return 0; }
    scan || { rm -f "$ITEMS"; echo "cache_items=?"; return 0; }
    _n=0; _b=0
    while IFS= read -r _f; do _n=$((_n + 1)); _b=$((_b + $(item_bytes "$_f"))); done < "$ITEMS"
    rm -f "$ITEMS"
    echo "cache_items=$_n"; echo "cache_bytes=$_b"
}

cmd_clear() {
    if [ ! -d "$STATEDIR" ]; then echo "OK cache nothing to clear (no module data yet)"; return 0; fi
    scan || { echo "error: could not scan the module data directory" >&2; return 6; }
    while IFS= read -r _f; do
        [ -e "$_f" ] || continue
        _sz=$(item_bytes "$_f")
        if rm -rf "$_f" 2>/dev/null && [ ! -e "$_f" ]; then N=$((N + 1)); BYTES=$((BYTES + _sz))
        else FAILED=$((FAILED + 1)); echo "could not remove $(basename "$_f")" >&2; fi
    done < "$ITEMS"
    rm -f "$ITEMS"
    if [ "$FAILED" -gt 0 ]; then echo "error: $FAILED item(s) could not be removed ($N removed)" >&2; return 6; fi
    if [ "$N" -eq 0 ]; then echo "OK cache nothing to clear"; else echo "OK cache cleared $N item(s) ${BYTES} B"; fi
}

case "$1" in
    status)
        cmd_status ;;
    clear)
        [ -d "$STATEDIR" ] || { echo "OK cache nothing to clear (no module data yet)"; exit 0; }
        acquire_lock || { echo "error: could not acquire lock" >&2; exit 7; }
        cmd_clear; _rc=$?
        rm -f "$ITEMS"
        [ "$_rc" -ne 0 ] && log_error "Clear cache" "" "failed with code $_rc"
        exit "$_rc" ;;
    *) echo "usage: cache.sh status|clear" >&2; exit 1 ;;
esac
