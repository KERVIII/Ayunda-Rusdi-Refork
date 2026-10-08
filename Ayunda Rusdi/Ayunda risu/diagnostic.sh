#!/system/bin/sh
# Diagnostic log for Ayunda Rusdi.
#   diagnostic.sh print    write the report text to stdout (what Copy uses)
#   diagnostic.sh save     save the SAME text as a new file in
#                          Download/AyundaRusdi Logs/ (never overwrites)
# One-shot: no daemon, no polling. The report contains only module/state
# information: no package names, no paths, no accounts, no environment,
# no process list, no Android logcat dump.
DIR="$(dirname "$0")"
. "$DIR/common.sh"
LOG_FOLDER_NAME="AyundaRusdi Logs"

# ---- gather (single snapshot from status.sh + one on-demand event-source probe)
snap=$(sh "$DIR/status.sh" 2>/dev/null)
v() { printf '%s\n' "$snap" | grep -m1 "^$1=" | cut -d= -f2-; }   # first value of key
cnt() { printf '%s\n' "$snap" | grep -c "^$1="; }
unk() { [ -n "$1" ] && printf '%s' "$1" || printf 'Unknown'; }
na()  { [ -n "$1" ] && printf '%s' "$1" || printf 'Not available'; }
num() { _x=$(validate_value "$1" 2>/dev/null) && printf '%s' "$_x" || printf 'Not available'; }
tw()  { case "$1" in null) printf 'default (not set)' ;; '') printf 'Not available' ;; *) num "$1" ;; esac; }
preset_name() { printf '%s\n' "$snap" | grep -m1 "^preset=$1|" | cut -d'|' -f2; }

build_report() {
    ver=$(v version); sdk=$(v sdk); and=$(v android)
    st_read=$(v state_read); st_valid=$(v state_valid); mod=$(v module_state)
    pid=$(v active_preset); pval=$(v active_value)
    echo "Ayunda Rusdi Color Enhancer $(unk "$ver")"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo Unknown)"
    echo
    echo "=== DEVICE ==="
    if [ -n "$and" ]; then echo "Android: $and${sdk:+ (API $sdk)}"; else echo "Android: Unknown"; fi
    echo "Device: $(unk "$(v model)")"
    echo "Root: $(unk "$(v root | sed 's/^unknown$//')")"
    echo
    echo "=== BACKEND ==="
    echo "Backend: SurfaceFlinger"
    echo "Transaction: 1022"
    case "$(v backend)" in 1) echo "Availability: available" ;; 0) echo "Availability: UNAVAILABLE" ;; *) echo "Availability: Unknown" ;; esac
    echo "Verification: $([ "$(v verify)" = PASS ] && echo PASS || echo FAIL)"
    echo
    echo "=== COLOR STATE ==="
    if [ "$st_read" = 1 ]; then
        echo "Module: $mod"
        if [ -n "$pid" ]; then echo "Preset: $(unk "$(preset_name "$pid")")"; else echo "Preset: None (native)"; fi
        if [ "$mod" = enabled ]; then echo "Value: $(num "$pval")"; else echo "Value: 1.00 (native, module disabled)"; fi
        echo "State: $([ "$st_valid" = 1 ] && echo consistent || echo INCONSISTENT)"
    else
        echo "Module: Unknown"; echo "Preset: Unknown"; echo "Value: Unknown"; echo "State: state file unreadable"
    fi
    echo
    echo "=== SYSTEM UI ==="
    if [ "$(v tweaks_supported)" = 1 ]; then
        echo "Window animation: $(tw "$(v window)")"
        echo "Transition animation: $(tw "$(v transition)")"
        echo "Animator duration: $(tw "$(v animator)")"
        if [ "$(v tweaks_applied)" = 1 ]; then echo "Tweaks: applied ($(num "$(v tweaks_value)"))"; else echo "Tweaks: not applied"; fi
    else
        echo "Window animation: Not available"; echo "Transition animation: Not available"; echo "Animator duration: Not available"; echo "Tweaks: Not available (settings command missing)"
    fi
    echo
    echo "=== FEATURES ==="
    echo "Pinned presets: $(cnt favorite)"
    echo "Per-App Profiles: $(cnt profile)"
    nope=$(printf '%s\n' "$snap" | grep -c '^profile=.*|0$')
    [ "$nope" -gt 0 ] && echo "Profiles for apps that are not installed: $nope"
    if [ "$(v watcher_supported)" = 1 ]; then
        echo "Per-App Auto Switching: $([ "$(v autoswitch)" = 1 ] && echo ON || echo OFF)"
        case "$(v watcher)" in
            running) echo "Listener: running" ;;
            stopped) echo "Listener: stopped ($(v watcher_reason | tr '_' ' '))" ;;
            *) echo "Listener: Unknown" ;;
        esac
    else
        echo "Per-App Auto Switching: Not available (setsid/logcat missing)"
    fi
    echo "Foreground event received: $([ -n "$(v last_foreground)" ] && echo yes || echo none since start)"
    case "$(v last_apply_result)" in
        ok) echo "Last profile apply: OK ($(na "$(v last_apply_time)"))" ;;
        skipped) echo "Last profile apply: no change needed ($(na "$(v last_apply_time)"))" ;;
        failed) echo "Last profile apply: FAILED ($(na "$(v last_apply_time)")): $(na "$(v last_apply_reason)")" ;;
        *) echo "Last profile apply: none yet" ;;
    esac
    echo
    echo "=== DIAGNOSTICS ==="
    echo "Backend verification: $([ "$(v verify)" = PASS ] && echo PASS || echo FAIL)"
    echo "State verification: $([ "$st_valid" = 1 ] && echo PASS || echo FAIL)"
    case "$(sh "$DIR/watcher.sh" probe 2>/dev/null | cut -d= -f2)" in
        seen) echo "Foreground event source: wm_set_resumed_activity seen in recent events buffer" ;;
        not_seen) echo "Foreground event source: wm_set_resumed_activity NOT seen in recent events buffer (inconclusive if the buffer was recently cleared)" ;;
        logcat_unavailable) echo "Foreground event source: Not available (logcat missing)" ;;
        *) echo "Foreground event source: Unknown" ;;
    esac
    echo
    echo "=== ERROR HISTORY ==="
    echo "Crash cause: Not available from collected diagnostics"
    echo "(only failures detected by this module are recorded; max $ERRLOG_MAX, newest last)"
    if [ -s "$ERRLOG" ]; then
        tail -n "$ERRLOG_MAX" "$ERRLOG" | while IFS='|' read -r _t _o _val _r; do
            echo
            echo "$(unk "$_t")"
            echo "Operation: $(unk "$_o")"
            [ -n "$_val" ] && echo "Value: $_val"
            echo "Result: FAILED"
            echo "Reason: $(na "$_r")"
        done
    else
        echo "No failures recorded."
    fi
}

# ---- save: shared Download folder, never overwrite
find_download() {
    for _d in ${LOG_DOWNLOAD_BASE:-/storage/emulated/0/Download /sdcard/Download}; do
        [ -d "$_d" ] && { echo "$_d"; return 0; }
    done
    return 1
}
cmd_save() {
    DL=$(find_download) || { echo "error: Android Download folder not found" >&2; return 3; }
    OUTDIR="$DL/$LOG_FOLDER_NAME"
    mkdir -p "$OUTDIR" 2>/dev/null
    [ -d "$OUTDIR" ] || { echo "error: could not create the folder 'Download/$LOG_FOLDER_NAME'" >&2; return 4; }
    TEXT=$(build_report) || { echo "error: could not build the report" >&2; return 5; }
    WANT=$(printf '%s\n' "$TEXT" | wc -c)
    TS=$(date '+%Y-%m-%d_%H%M%S' 2>/dev/null)
    case "$TS" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) TS="unknown-time" ;; esac
    # candidates: logs.txt first, then timestamped, then timestamped with a counter
    set -- "logs.txt" "logs_$TS.txt"; _n=2
    while [ "$_n" -le 99 ]; do set -- "$@" "logs_${TS}_$_n.txt"; _n=$((_n + 1)); done
    for NAME in "$@"; do
        F="$OUTDIR/$NAME"
        [ -e "$F" ] && continue
        # 1) exclusive create (noclobber = O_EXCL): atomic, can NEVER replace an existing file.
        #    Success means this call owns the file; failure means it already exists -> next name.
        ( set -C; : > "$F" ) 2>/dev/null || { [ -e "$F" ] && continue; echo "error: could not create 'Download/$LOG_FOLDER_NAME/$NAME' (storage not writable?)" >&2; return 7; }
        # 2) write + verify; on any problem remove only the file created above
        if ! ( printf '%s\n' "$TEXT" > "$F" ) 2>/dev/null; then
            rm -f "$F"; echo "error: could not write the log file (disk full or storage error)" >&2; return 7
        fi
        GOT=$(wc -c < "$F" 2>/dev/null | tr -d ' ')
        if [ -f "$F" ] && [ "$GOT" = "$WANT" ]; then
            echo "OK saved Download/$LOG_FOLDER_NAME/$NAME"; return 0
        fi
        rm -f "$F"
        echo "error: file verification failed (expected $WANT bytes, found ${GOT:-0}); file removed" >&2; return 6
    done
    echo "error: no free log file name (99 saves in the same second?)" >&2; return 8
}

case "$1" in
    print) build_report ;;
    save)  cmd_save ;;
    *) echo "usage: diagnostic.sh print|save" >&2; exit 1 ;;
esac
