#!/system/bin/sh
# Per-app profile listener (event-driven, NO polling).
#   watcher.sh start | stop | sync | status | probe | auto on|off
#   watcher.sh run            (internal: the listener process)
#   watcher.sh event <pkg>    (internal: one foreground change)
#
# Mechanism: one blocking `logcat -b events` stream filtered to the
# `wm_set_resumed_activity` event (emitted by Android's activity manager when
# the foreground activity changes). The listener sleeps in read() between
# events and spawns a short-lived shell only when the foreground PACKAGE
# changes. It exists only while ALL of these hold: auto switching is on, the
# module is enabled, and at least one valid profile exists (`sync` enforces it).
#
# Behavior: foreground app has a profile -> its saturation is applied through
# the normal backend (transaction 1022) WITHOUT touching the saved global state
# (state.conf). Foreground app has no profile -> the saved global value is
# restored. The backend is called only when the required value changes.
DIR="$(dirname "$0")"
. "$DIR/common.sh"
WLOCK="$STATEDIR/.watcher.lock"       # single-instance lock (dir); WLOCK/pid = listener pid
AUTOF="$STATEDIR/autoswitch"          # "0" = off; absent/anything else = on
RUN_PRIMARY="${RUNSTATE_FILE:-/dev/.risu_watch_state}"   # tmpfs; written on foreground transitions only
RUN_FALLBACK="$STATEDIR/.runstate"
EVENT_TAG="wm_set_resumed_activity"
MAX_RESTARTS=5

auto_enabled() { [ "$(cat "$AUTOF" 2>/dev/null)" != "0" ]; }
supported() { command -v setsid >/dev/null 2>&1 && command -v logcat >/dev/null 2>&1; }
profile_count() { _c=$(sh "$DIR/profile.sh" list 2>/dev/null | grep -c '^profile=.*|ok|'); echo "${_c:-0}"; }
module_enabled() { read_state && validate_state && [ "$MODULE_STATE" = "enabled" ]; }

is_watcher_pid() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$1" 2>/dev/null || return 1
    tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | grep -q 'watcher\.sh'
}
running_pid() {
    _p=$(cat "$WLOCK/pid" 2>/dev/null)
    is_watcher_pid "$_p" && echo "$_p"
}

# ---- runtime debug state (tiny, tmpfs, rewritten only on foreground transitions)
read_run() {
    RUN_LAST_APP=""; RUN_PREV_APP=""; RUN_MATCH=""; RUN_MVAL=""; RUN_RESULT=""; RUN_TIME=""; RUN_REASON=""
    for _f in "$RUN_PRIMARY" "$RUN_FALLBACK"; do
        [ -f "$_f" ] || continue
        while IFS='=' read -r _k _v; do
            case "$_k" in
                last_app)   is_valid_package "$_v" && RUN_LAST_APP="$_v" ;;
                previous_app) is_valid_package "$_v" && RUN_PREV_APP="$_v" ;;
                matched_profile) { [ "$_v" = none ] || is_valid_package "$_v"; } && RUN_MATCH="$_v" ;;
                matched_value) validate_value "$_v" >/dev/null && RUN_MVAL="$(validate_value "$_v")" ;;
                last_apply_result) case "$_v" in ok|failed|skipped|none) RUN_RESULT="$_v" ;; esac ;;
                last_apply_time) case "$_v" in [0-2][0-9]:[0-5][0-9]:[0-5][0-9]) RUN_TIME="$_v" ;; esac ;;
                last_apply_reason) RUN_REASON="$(diag_clean "$_v")" ;;
            esac
        done < "$_f"
        return 0
    done
    return 1
}
write_run() { # <last> <prev> <match> <mval> <result> <reason>
    _body="last_app=$1
previous_app=$2
matched_profile=$3
matched_value=$4
last_apply_result=$5
last_apply_time=$(date '+%H:%M:%S' 2>/dev/null)
last_apply_reason=$(diag_clean "$6")"
    for _f in "$RUN_PRIMARY" "$RUN_FALLBACK"; do
        _t="$_f.tmp.$$"
        if printf '%s\n' "$_body" > "$_t" 2>/dev/null && mv -f "$_t" "$_f" 2>/dev/null; then return 0; fi
        rm -f "$_t" 2>/dev/null
    done
    return 1
}

# effective value on the backend right now: override if one is marked, else global
effective_value() {
    _e="$ACTIVE_VALUE"
    if [ -f "$OVR_FILE" ]; then
        read -r _op _os < "$OVR_FILE" 2>/dev/null
        _c=$(validate_value "$_os" 2>/dev/null) && _e="$_c"
    fi
    echo "$_e"
}
write_ovr() { _t="$OVR_FILE.tmp.$$"; echo "$1 $2" > "$_t" && mv -f "$_t" "$OVR_FILE"; }

# restore_if_override: caller holds the lock and has called read_state.
# Sets RESTORED=1 when it actually changed the backend; RESTORE_ERR on failure.
restore_if_override() {
    RESTORED=0; RESTORE_ERR=""
    [ -f "$OVR_FILE" ] || return 0
    _t="$NATIVE_VAL"
    if validate_state && [ "$MODULE_STATE" = "enabled" ]; then _t="$ACTIVE_VALUE"; fi
    if apply_saturation "$_t"; then rm -f "$OVR_FILE"; RESTORED=1; return 0; fi
    RESTORE_ERR="$LAST_BACKEND_MSG"; return 1
}

cmd_event() {
    _pkg="$1"
    is_valid_package "$_pkg" || return 1
    acquire_lock || return 7
    read_run; _prev="$RUN_LAST_APP"
    _res="skipped"; _why=""; _match="none"; _mval=""
    read_state
    if ! validate_state || [ "$MODULE_STATE" != "enabled" ]; then
        _why="module disabled or state invalid"
        if ! restore_if_override; then _res="failed"; _why="restore failed: $RESTORE_ERR"; log_error "Per-app restore" "$NATIVE_VAL" "$RESTORE_ERR"; fi
    else
        _sat=$(sh "$DIR/profile.sh" resolve "$_pkg" 2>/dev/null) || _sat=""
        if [ -n "$_sat" ]; then
            _match="$_pkg"; _mval="$_sat"
            if [ "$_sat" = "$(effective_value)" ]; then
                _why="value already in effect (no backend call)"
                [ -f "$OVR_FILE" ] && write_ovr "$_pkg" "$_sat"
            elif apply_saturation "$_sat"; then
                write_ovr "$_pkg" "$_sat"; _res="ok"
            else
                _res="failed"; _why="$LAST_BACKEND_MSG"; log_error "Per-app profile apply" "$_sat" "$LAST_BACKEND_MSG"
            fi
        elif restore_if_override; then
            [ "$RESTORED" = 1 ] && { _res="ok"; _why="restored saved global value"; } || _why="no profile for this app"
        else
            _res="failed"; _why="restore failed: $RESTORE_ERR"; log_error "Per-app restore" "$ACTIVE_VALUE" "$RESTORE_ERR"
        fi
    fi
    write_run "$_pkg" "$_prev" "$_match" "$_mval" "$_res" "$_why"
    return 0
}

cmd_loop() {
    _last=""
    while IFS= read -r _line; do
        case "$_line" in *"$EVENT_TAG"*"["*) ;; *) continue ;; esac
        _rest=${_line#*\[}; _rest=${_rest#*,}; _pkg=${_rest%%/*}
        is_valid_package "$_pkg" || continue
        [ "$_pkg" = "$_last" ] && continue          # unchanged package: nothing to do
        _last="$_pkg"
        sh "$DIR/watcher.sh" event "$_pkg" >/dev/null 2>&1
    done
}

cmd_run() {
    mkdir -p "$STATEDIR" 2>/dev/null
    # single instance: atomic mkdir lock; a live watcher wins, a dead one is reclaimed
    _tries=0
    while ! mkdir "$WLOCK" 2>/dev/null; do
        _p=$(cat "$WLOCK/pid" 2>/dev/null)
        if [ -z "$_p" ] && [ "$_tries" -lt 5 ]; then sleep 0.1; _tries=$((_tries + 1)); continue; fi   # owner may still be writing its pid
        is_watcher_pid "$_p" && exit 0
        rm -rf "$WLOCK"; _tries=$((_tries + 1)); [ "$_tries" -gt 8 ] && exit 0
    done
    trap 'rm -rf "$WLOCK"; exit 0' TERM INT HUP EXIT
    echo "$$" > "$WLOCK/pid.tmp" && mv -f "$WLOCK/pid.tmp" "$WLOCK/pid" || exit 1
    clear_override
    _n=0
    while [ "$_n" -lt "$MAX_RESTARTS" ]; do    # bounded restarts, never an endless loop
        logcat -b events -T 1 -v brief "$EVENT_TAG:I" '*:S' 2>/dev/null | cmd_loop
        _n=$((_n + 1)); sleep 5
    done
}

cmd_start() {
    supported || { echo "error: automatic switching unsupported here (setsid/logcat not found)" >&2; return 3; }
    if running_pid >/dev/null; then echo "OK listener running"; return 0; fi
    mkdir -p "$STATEDIR" 2>/dev/null
    setsid sh "$DIR/watcher.sh" run >/dev/null 2>&1 </dev/null &
    _i=0
    while [ "$_i" -lt 30 ]; do
        running_pid >/dev/null && { echo "OK listener started"; return 0; }
        sleep 0.1; _i=$((_i + 1))
    done
    echo "error: listener failed to start" >&2; return 6
}

cmd_stop() {
    if _p=$(running_pid); then
        kill -s TERM -- "-$_p" 2>/dev/null || kill -s TERM "$_p" 2>/dev/null
        _i=0; while [ "$_i" -lt 20 ] && kill -0 "$_p" 2>/dev/null; do sleep 0.1; _i=$((_i + 1)); done
        kill -0 "$_p" 2>/dev/null && { kill -s KILL -- "-$_p" 2>/dev/null; kill -s KILL "$_p" 2>/dev/null; }
        rm -rf "$WLOCK"
    elif [ -d "$WLOCK" ]; then
        rm -rf "$WLOCK"                         # stale lock from a dead listener
    fi
    if [ -f "$OVR_FILE" ] && acquire_lock; then
        read_state; restore_if_override || log_error "Per-app restore" "" "$RESTORE_ERR"
        release_lock; trap - EXIT
    fi
    echo "OK listener stopped"
}

# the listener must exist iff: auto on AND module enabled AND >=1 valid profile
cmd_sync() {
    if auto_enabled && module_enabled && [ "$(profile_count)" -gt 0 ]; then cmd_start; else cmd_stop; fi
}

cmd_auto() {
    case "$1" in
        on)  _v=1 ;;
        off) _v=0 ;;
        *) echo "usage: watcher.sh auto on|off" >&2; return 1 ;;
    esac
    mkdir -p "$STATEDIR" 2>/dev/null
    _t="$AUTOF.tmp.$$"; echo "$_v" > "$_t" && mv -f "$_t" "$AUTOF" || { rm -f "$_t"; echo "error: could not save setting" >&2; return 4; }
    [ "$(cat "$AUTOF" 2>/dev/null)" = "$_v" ] || { echo "error: setting read-back mismatch" >&2; return 4; }
    cmd_sync >/dev/null || { echo "error: setting saved but the listener could not be changed" >&2; return 6; }
    echo "OK auto $1"
}

# One-shot, on demand: does this ROM's recent events buffer contain the event?
cmd_probe() {
    command -v logcat >/dev/null 2>&1 || { echo "event_source=logcat_unavailable"; return 0; }
    _n=$(logcat -b events -d -t 500 2>/dev/null | grep -c "$EVENT_TAG")
    if [ "${_n:-0}" -gt 0 ]; then echo "event_source=seen"; else echo "event_source=not_seen"; fi
}

cmd_status() {
    if auto_enabled; then echo "autoswitch=1"; else echo "autoswitch=0"; fi
    if supported; then echo "watcher_supported=1"; else echo "watcher_supported=0"; fi
    if running_pid >/dev/null; then
        echo "watcher=running"
        if [ -f "$OVR_FILE" ]; then
            read -r _op _os < "$OVR_FILE" 2>/dev/null
            is_valid_package "$_op" && validate_value "$_os" >/dev/null && echo "override=$_op|$(validate_value "$_os")"
        fi
    else
        echo "watcher=stopped"
        if ! auto_enabled; then echo "watcher_reason=auto_off"
        elif ! module_enabled; then echo "watcher_reason=module_disabled"
        elif [ "$(profile_count)" -eq 0 ]; then echo "watcher_reason=no_profiles"
        else echo "watcher_reason=not_started"; fi
    fi
    if read_run; then
        [ -n "$RUN_LAST_APP" ] && echo "last_foreground=$RUN_LAST_APP"
        [ -n "$RUN_PREV_APP" ] && echo "previous_app=$RUN_PREV_APP"
        [ -n "$RUN_MATCH" ] && echo "matched_profile=$RUN_MATCH"
        [ -n "$RUN_MVAL" ] && echo "matched_value=$RUN_MVAL"
        [ -n "$RUN_RESULT" ] && echo "last_apply_result=$RUN_RESULT"
        [ -n "$RUN_TIME" ] && echo "last_apply_time=$RUN_TIME"
        [ -n "$RUN_REASON" ] && echo "last_apply_reason=$RUN_REASON"
    fi
    return 0      # a read-only report must never fail just because the last field was empty
}

case "$1" in
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    sync)   cmd_sync ;;
    status) cmd_status ;;
    probe)  cmd_probe ;;
    auto)   cmd_auto "$2" ;;
    run)    cmd_run ;;
    event)  cmd_event "$2" ;;
    *) echo "usage: watcher.sh start|stop|sync|status|probe|auto on|off" >&2; exit 1 ;;
esac
