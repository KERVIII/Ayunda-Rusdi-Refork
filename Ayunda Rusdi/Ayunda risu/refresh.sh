#!/system/bin/sh
# Force Peak Refresh Rate (opt-in). Independent of the color backend.
#   refresh.sh status    cheap: backup + live check, only when we applied something
#   refresh.sh probe     reads the display's real supported modes (dumpsys display)
#   refresh.sh on        raise peak_refresh_rate + min_refresh_rate to the highest mode
#   refresh.sh off       restore the originals we backed up (only keys still at our value)
#   refresh.sh restore   same as off, silent no-op when nothing was applied (uninstall)
# Mechanism: the AOSP Settings.System keys peak_refresh_rate / min_refresh_rate that
# DisplayModeDirector reads (Android 10+). `settings put` only; no daemon, no loop,
# no boot hook (Android persists the values). Some ROMs ignore these keys, so the
# UI reports the setting and the mode seen at the last probe separately.
# Originals are backed up before the first write; every write is read back and any
# mismatch rolls everything back.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

RF_FILE="$STATEDIR/refresh.conf"
RF_MIN_SDK=29

rf_get() { settings get system "$1" 2>/dev/null; }
rf_put() { # <key> <value|null>
    if [ "$2" = "null" ]; then settings delete system "$1" >/dev/null 2>&1
    else settings put system "$1" "$2" >/dev/null 2>&1; fi
}
rf_clean() { # null or a plain number; anything else is BAD
    case "$1" in
        null|'') echo null ;;
        *[!0-9.]*|*.*.*|.*) echo BAD ;;
        *) echo "$1" ;;
    esac
}
rf_same() { # numeric equality within 0.5 Hz; null==null
    if [ "$1" = "null" ] || [ "$2" = "null" ]; then [ "$1" = "$2" ]; return; fi
    awk -v a="$1" -v b="$2" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<0.5)}'
}
rf_load_backup() {
    BK_PEAK=""; BK_MIN=""; BK_VAL=""; _ap=""
    [ -f "$RF_FILE" ] || return 1
    while IFS='=' read -r _k _v; do
        case "$_k" in
            applied) _ap="$_v" ;;
            orig_peak) BK_PEAK="$_v" ;;
            orig_min) BK_MIN="$_v" ;;
            value) BK_VAL="$_v" ;;
        esac
    done < "$RF_FILE"
    [ "$_ap" = "1" ] || return 1
    [ -n "$BK_PEAK" ] && [ -n "$BK_MIN" ] && [ -n "$BK_VAL" ] || return 1
    [ "$(rf_clean "$BK_PEAK")" != BAD ] && [ "$(rf_clean "$BK_MIN")" != BAD ] && [ "$(rf_clean "$BK_VAL")" != BAD ] && [ "$BK_VAL" != null ]
}
rf_write_backup() { # <orig_peak> <orig_min> <value>
    _t="${RF_FILE}.tmp.$$"
    printf 'applied=1\norig_peak=%s\norig_min=%s\nvalue=%s\n' "$1" "$2" "$3" > "$_t" \
        && mv -f "$_t" "$RF_FILE" || { rm -f "$_t"; return 1; }
}

cmd_status() {
    if ! command -v settings >/dev/null 2>&1; then echo "refresh_cmd=0"; return 0; fi
    echo "refresh_cmd=1"
    if rf_load_backup; then
        _p=$(rf_clean "$(rf_get peak_refresh_rate)"); _m=$(rf_clean "$(rf_get min_refresh_rate)")
        echo "refresh_value=$BK_VAL"
        echo "refresh_live_peak=$_p"; echo "refresh_live_min=$_m"
        if rf_same "$_p" "$BK_VAL" && rf_same "$_m" "$BK_VAL"; then echo "refresh_applied=1"
        else echo "refresh_applied=0"; echo "refresh_drift=1"; fi   # changed since we applied it
    else
        echo "refresh_applied=0"
    fi
}

# Reads real display modes. Highest rate is taken among modes at the ACTIVE resolution,
# because the system will not switch resolution to satisfy a refresh-rate request.
cmd_probe() {
    command -v settings >/dev/null 2>&1 || { echo "refresh_supported=0"; echo "refresh_reason=the settings command is unavailable"; return 0; }
    _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
    case "$_sdk" in ''|*[!0-9]*) echo "refresh_supported=0"; echo "refresh_reason=Android version could not be read"; return 0 ;; esac
    if [ "$_sdk" -lt "$RF_MIN_SDK" ]; then echo "refresh_supported=0"; echo "refresh_reason=needs Android 10 or newer (found API $_sdk)"; return 0; fi
    command -v dumpsys >/dev/null 2>&1 || { echo "refresh_supported=0"; echo "refresh_reason=dumpsys is unavailable, display modes cannot be read"; return 0; }
    _info=$(dumpsys display 2>/dev/null | awk '
        BEGIN { act = -1 }
        {
            line = $0
            if (act < 0 && match(line, /[mM]?[aA]ctiveModeId[=: ]+[0-9]+/)) { s = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); act = s + 0 }
            while (match(line, /id=[0-9]+, width=[0-9]+, height=[0-9]+, (fps|refreshRate)=[0-9.]+/)) {
                t = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
                n = split(t, a, /[=, ]+/)
                W[a[2]] = a[4]; H[a[2]] = a[6]; F[a[2]] = a[8]; seen = 1
            }
        }
        END {
            if (!seen) { print "none"; exit }
            aw = -1
            if (act in W) { aw = W[act]; ah = H[act]; cur = F[act] }
            max = 0
            for (i in W) if (aw < 0 || (W[i] == aw && H[i] == ah)) if (F[i] + 0 > max) max = F[i] + 0
            printf "max=%.0f cur=%s", max, (cur == "" ? "" : sprintf("%.0f", cur))
        }')
    case "$_info" in
        none|'') echo "refresh_supported=0"; echo "refresh_reason=no display modes could be read from this ROM"; return 0 ;;
    esac
    _max=${_info#max=}; _max=${_max%% *}
    _cur=${_info#*cur=}
    [ "$_cur" = "$_info" ] && _cur=""
    case "$_max" in ''|*[!0-9]*) echo "refresh_supported=0"; echo "refresh_reason=display modes could not be parsed"; return 0 ;; esac
    echo "refresh_max=$_max"
    [ -n "$_cur" ] && echo "refresh_current=$_cur"
    echo "refresh_peak=$(rf_clean "$(rf_get peak_refresh_rate)")"
    echo "refresh_min=$(rf_clean "$(rf_get min_refresh_rate)")"
    if [ "$_max" -le 60 ]; then
        echo "refresh_supported=0"; echo "refresh_reason=the display exposes no mode above 60 Hz"
    else
        echo "refresh_supported=1"
    fi
}

cmd_on() {
    command -v settings >/dev/null 2>&1 || { echo "error: settings command unavailable" >&2; return 3; }
    _pr=$(cmd_probe)
    case "$_pr" in
        *refresh_supported=1*) ;;
        *) echo "error: not supported here: $(echo "$_pr" | sed -n 's/^refresh_reason=//p' | head -n 1)" >&2; return 3 ;;
    esac
    MAXHZ=$(echo "$_pr" | sed -n 's/^refresh_max=//p' | head -n 1)
    case "$MAXHZ" in ''|*[!0-9]*) echo "error: could not determine the highest refresh rate" >&2; return 3 ;; esac

    HAD_BACKUP=0
    if rf_load_backup; then HAD_BACKUP=1; O_PEAK="$BK_PEAK"; O_MIN="$BK_MIN"
    else
        O_PEAK=$(rf_clean "$(rf_get peak_refresh_rate)"); O_MIN=$(rf_clean "$(rf_get min_refresh_rate)")
        if [ "$O_PEAK" = BAD ] || [ "$O_MIN" = BAD ]; then echo "error: unexpected current refresh settings; refusing to modify" >&2; return 4; fi
    fi
    P_PEAK=$(rf_clean "$(rf_get peak_refresh_rate)"); P_MIN=$(rf_clean "$(rf_get min_refresh_rate)")

    rf_write_backup "$O_PEAK" "$O_MIN" "$MAXHZ" || { echo "error: could not write backup" >&2; return 5; }

    for _k in peak_refresh_rate min_refresh_rate; do   # peak first so peak >= min at every step
        rf_put "$_k" "$MAXHZ"
        _r=$(rf_clean "$(rf_get "$_k")")
        if ! rf_same "$_r" "$MAXHZ"; then
            rf_put peak_refresh_rate "$P_PEAK"; rf_put min_refresh_rate "$P_MIN"
            [ "$HAD_BACKUP" = 1 ] || rm -f "$RF_FILE"
            echo "error: read-back mismatch on $_k (wanted $MAXHZ, got $_r); rolled back" >&2
            return 6
        fi
    done
    echo "OK refresh $MAXHZ"
}

# restore a key only if it still holds our value; never overwrite a later user choice
rf_restore_key() { # <key> <orig> <ours>
    _cur=$(rf_clean "$(rf_get "$1")")
    if rf_same "$_cur" "$3"; then
        rf_put "$1" "$2"
        rf_same "$(rf_clean "$(rf_get "$1")")" "$2" || return 1
    else
        RF_KEPT="$RF_KEPT $1"
    fi
    return 0
}
cmd_off() {
    command -v settings >/dev/null 2>&1 || { echo "error: settings command unavailable" >&2; return 3; }
    if ! rf_load_backup; then echo "OK refresh none"; return 0; fi   # nothing we applied: do not guess
    RF_KEPT=""
    rf_restore_key peak_refresh_rate "$BK_PEAK" "$BK_VAL" || { echo "error: restore read-back mismatch on peak_refresh_rate; backup kept" >&2; return 6; }
    rf_restore_key min_refresh_rate "$BK_MIN" "$BK_VAL" || { echo "error: restore read-back mismatch on min_refresh_rate; backup kept" >&2; return 6; }
    rm -f "$RF_FILE"
    if [ -n "$RF_KEPT" ]; then echo "OK refresh restored (left${RF_KEPT} as changed since)"; else echo "OK refresh restored"; fi
}
cmd_restore() { if rf_load_backup; then cmd_off; else echo "OK refresh none"; fi; }

mkdir -p "$STATEDIR" 2>/dev/null
rf_guard() { # <label> <cmd...>: record the real failure reason in the bounded error history
    _lbl="$1"; shift
    _et="$STATEDIR/.rf_err.$$"
    "$@" 2>"$_et"; _rc=$?
    cat "$_et" >&2
    [ "$_rc" -ne 0 ] && log_error "Refresh rate ($_lbl)" "" "$(head -n 1 "$_et" | sed 's/^error: //')"
    rm -f "$_et"
    return "$_rc"
}
case "$1" in
    status)  cmd_status ;;
    probe)   cmd_probe ;;
    on)      acquire_lock || { echo "error: could not acquire lock" >&2; exit 7; }; rf_guard on cmd_on ;;
    off)     acquire_lock || { echo "error: could not acquire lock" >&2; exit 7; }; rf_guard off cmd_off ;;
    restore) acquire_lock || { echo "error: could not acquire lock" >&2; exit 7; }; rf_guard restore cmd_restore ;;
    *) echo "usage: refresh.sh status|probe|on|off" >&2; exit 1 ;;
esac
