#!/system/bin/sh
# System UI Tweaks: window/transition/animator duration scales.
#   ui_tweaks.sh status
#   ui_tweaks.sh apply [scale]     (default 0.85, allowed 0.25-2.00)
#   ui_tweaks.sh reset            (restore originals / Android default)
#   ui_tweaks.sh restore          (restore only if a tweak is applied)
# Uses only `settings put/get global` - persistent across reboots by Android
# itself, so there is NO daemon, loop, or boot hook. Originals are backed up
# once (first apply) and restored on reset/uninstall. Every write is read
# back; any failure rolls all three keys back to their previous values.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

TW_FILE="$STATEDIR/ui_tweaks.conf"
TW_KEYS="window_animation_scale transition_animation_scale animator_duration_scale"
TW_DEFAULT="0.85"; TW_MIN="0.25"; TW_MAX="2.00"; ANDROID_DEFAULT="1.0"

tw_validate() {
    is_valid_number "$1" || return 1
    awk -v v="$1" -v lo="$TW_MIN" -v hi="$TW_MAX" 'BEGIN{v+=0; if(v<lo||v>hi) exit 1; printf "%.2f", v}'
}
tw_get() { settings get global "$1" 2>/dev/null; }
# tw_put <key> <value|null>
tw_put() {
    if [ "$2" = "null" ]; then settings delete global "$1" >/dev/null 2>&1
    else settings put global "$1" "$2" >/dev/null 2>&1; fi
}
# tw_same <a> <b>: numeric equality within 0.001; null==null
tw_same() {
    [ "$1" = "null" ] || [ "$2" = "null" ] && { [ "$1" = "$2" ]; return; }
    awk -v a="$1" -v b="$2" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<0.001)}'
}
tw_clean() { # keep only null or a plain number from a settings read
    case "$1" in
        null|'') echo null ;;
        *[!0-9.]*|*.*.*|.*) echo BAD ;;
        *) echo "$1" ;;
    esac
}
tw_restore() { # tw_restore <o1> <o2> <o3>
    set -- "$1" "$2" "$3"; _n=1; _rc=0
    for _k in $TW_KEYS; do
        eval "_o=\${$_n}"; tw_put "$_k" "$_o"
        _r=$(tw_clean "$(tw_get "$_k")")
        tw_same "$_r" "$_o" || _rc=1
        _n=$((_n + 1))
    done
    return $_rc
}
tw_load_backup() {
    BK_APPLIED=""; BK_1=""; BK_2=""; BK_3=""; BK_VAL=""
    [ -f "$TW_FILE" ] || return 1
    while IFS='=' read -r _k _v; do
        case "$_k" in
            applied) BK_APPLIED="$_v" ;;
            orig_window) BK_1="$_v" ;;
            orig_transition) BK_2="$_v" ;;
            orig_animator) BK_3="$_v" ;;
            value) BK_VAL="$_v" ;;
        esac
    done < "$TW_FILE"
    [ "$BK_APPLIED" = "1" ] || return 1
    for _x in "$BK_1" "$BK_2" "$BK_3"; do [ "$(tw_clean "$_x")" = "BAD" ] && return 1; [ -n "$_x" ] || return 1; done
    return 0
}
tw_write_backup() { # <o1> <o2> <o3> <value>
    _t="${TW_FILE}.tmp.$$"
    { printf 'applied=1\norig_window=%s\norig_transition=%s\norig_animator=%s\nvalue=%s\n' "$1" "$2" "$3" "$4"; } > "$_t" \
        && mv -f "$_t" "$TW_FILE" || { rm -f "$_t"; return 1; }
}

cmd_status() {
    command -v settings >/dev/null 2>&1 || { echo "tweaks_supported=0"; return 0; }
    echo "tweaks_supported=1"
    echo "window=$(tw_clean "$(tw_get window_animation_scale)")"
    echo "transition=$(tw_clean "$(tw_get transition_animation_scale)")"
    echo "animator=$(tw_clean "$(tw_get animator_duration_scale)")"
    if tw_load_backup; then echo "tweaks_applied=1"; echo "tweaks_value=$BK_VAL"; else echo "tweaks_applied=0"; fi
    echo "tweaks_default=$TW_DEFAULT"
}

cmd_apply() {
    command -v settings >/dev/null 2>&1 || { echo "error: settings command unavailable" >&2; return 3; }
    V=$(tw_validate "${1:-$TW_DEFAULT}") || { echo "error: invalid scale '$1' (allowed $TW_MIN-$TW_MAX)" >&2; return 2; }

    # originals: reuse existing backup, else capture now
    HAD_BACKUP=0
    if tw_load_backup; then
        HAD_BACKUP=1; O1="$BK_1"; O2="$BK_2"; O3="$BK_3"
    else
        O1=$(tw_clean "$(tw_get window_animation_scale)")
        O2=$(tw_clean "$(tw_get transition_animation_scale)")
        O3=$(tw_clean "$(tw_get animator_duration_scale)")
        if [ "$O1" = BAD ] || [ "$O2" = BAD ] || [ "$O3" = BAD ]; then
            echo "error: unexpected current values; refusing to modify" >&2; return 4
        fi
    fi
    # previous live values, for rollback of THIS call
    P1=$(tw_clean "$(tw_get window_animation_scale)")
    P2=$(tw_clean "$(tw_get transition_animation_scale)")
    P3=$(tw_clean "$(tw_get animator_duration_scale)")

    # backup must be durable BEFORE touching settings
    tw_write_backup "$O1" "$O2" "$O3" "$V" || { echo "error: could not write backup" >&2; return 5; }

    for _k in $TW_KEYS; do
        tw_put "$_k" "$V"
        _r=$(tw_clean "$(tw_get "$_k")")
        if ! tw_same "$_r" "$V"; then
            tw_restore "$P1" "$P2" "$P3"
            [ "$HAD_BACKUP" = 1 ] || rm -f "$TW_FILE"
            echo "error: read-back mismatch on $_k (wanted $V, got $_r); rolled back" >&2
            return 6
        fi
    done
    echo "OK tweaks $V"
}

cmd_reset() {
    command -v settings >/dev/null 2>&1 || { echo "error: settings command unavailable" >&2; return 3; }
    if tw_load_backup; then
        tw_restore "$BK_1" "$BK_2" "$BK_3" || { echo "error: restore read-back mismatch; backup kept" >&2; return 6; }
    else
        # no backup: set Android's stock default and verify
        for _k in $TW_KEYS; do
            tw_put "$_k" "$ANDROID_DEFAULT"
            tw_same "$(tw_clean "$(tw_get "$_k")")" "$ANDROID_DEFAULT" || { echo "error: read-back mismatch on $_k" >&2; return 6; }
        done
    fi
    rm -f "$TW_FILE"
    echo "OK tweaks reset"
}

# restore only if this module applied a tweak (used by reset.sh); no-op otherwise
cmd_restore() {
    if tw_load_backup; then cmd_reset; else echo "OK tweaks none"; fi
}

mkdir -p "$STATEDIR" 2>/dev/null
# run a mutating command; on failure record the real reason in the bounded error history
tw_guard() { # <label> <cmd...>
    _lbl="$1"; shift
    _et="$STATEDIR/.tw_err.$$"
    "$@" 2>"$_et"; _rc=$?
    cat "$_et" >&2
    [ "$_rc" -ne 0 ] && log_error "System UI tweaks ($_lbl)" "" "$(head -n 1 "$_et" | sed 's/^error: //')"
    rm -f "$_et"
    return "$_rc"
}
case "$1" in
    restore) acquire_lock || { echo "error: could not acquire lock" >&2; exit 7; }; tw_guard restore cmd_restore ;;
    status) cmd_status ;;
    apply)  acquire_lock || { echo "error: could not acquire lock" >&2; exit 7; }; tw_guard apply cmd_apply "$2" ;;
    reset)  acquire_lock || { echo "error: could not acquire lock" >&2; exit 7; }; tw_guard reset cmd_reset ;;
    *) echo "usage: ui_tweaks.sh status|apply [scale]|reset" >&2; exit 1 ;;
esac
