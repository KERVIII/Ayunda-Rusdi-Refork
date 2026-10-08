#!/system/bin/sh
# Ayunda Rusdi Color Enhancer V7.0 - shared helpers.
# Sourced by ModuleOn/ModuleOff/apply_preset/reset/status/ui_tweaks.
# The ONLY place defining: paths, validation, preset lookup, state
# read/write/verify, locking, and the backend call.

# --- Paths -------------------------------------------------------------
MODDIR="${MODDIR:-/data/adb/modules/AyundaRusdi/AyundaRisu}"
STATEDIR="${STATEDIR:-/data/adb/risu-color-enhancer}"
STATE_FILE="$STATEDIR/state.conf"
LOCK_DIR="$STATEDIR/.lock"
CONF="$MODDIR/presets.conf"

MIN_VAL="0.00"
MAX_VAL="2.50"
NATIVE_VAL="1.00"
EXPECTED_PRESET_COUNT=18

# --- Validation ----------------------------------------------------------
# Plain non-negative decimal, max 8 chars. No sign, exponent, NaN, Inf.
is_valid_number() {
    case "$1" in
        ''|*[!0-9.]*|.*|*.|*.*.*) return 1 ;;
    esac
    [ "${#1}" -le 8 ]
}

# validate_value <v>: prints canonical %.2f and returns 0 only if the value
# is a valid number WITHIN [MIN_VAL, MAX_VAL]. Out-of-range is rejected.
validate_value() {
    is_valid_number "$1" || return 1
    awk -v v="$1" -v lo="$MIN_VAL" -v hi="$MAX_VAL" 'BEGIN{
        v += 0
        if (v < lo || v > hi) exit 1
        printf "%.2f", v
    }'
}

# preset ids: lowercase letters/digits/underscore only
is_valid_id() {
    case "$1" in
        ''|*[!a-z0-9_]*) return 1 ;;
    esac
    [ "${#1}" -le 32 ]
}

# --- presets.conf (awk exact-match; no regex on user input) ---------------
validate_presets_conf() {
    [ -f "$CONF" ] || { echo "error: presets.conf missing" >&2; return 1; }
    awk -F'|' -v expect="$EXPECTED_PRESET_COUNT" -v lo="$MIN_VAL" -v hi="$MAX_VAL" '
        /^#/ || NF==0 { next }
        {
            if (NF != 4) { print "malformed row: " $0 > "/dev/stderr"; bad=1; next }
            id=$1
            if (id !~ /^[a-z0-9_]+$/) { print "bad id: " id > "/dev/stderr"; bad=1; next }
            if (id in seen) { print "duplicate preset id: " id > "/dev/stderr"; bad=1; next }
            seen[id]=1
            if ($2 == "" || $3 == "" || $4 == "") { print "missing field(s): " id > "/dev/stderr"; bad=1; next }
            if (id == "risu_custom") {
                if ($4 != "custom") { print "risu_custom must be custom" > "/dev/stderr"; bad=1 }
            } else if ($4 !~ /^[0-9]+(\.[0-9]+)?$/ || $4+0 < lo || $4+0 > hi) {
                print "invalid value for " id ": " $4 > "/dev/stderr"; bad=1
            }
        }
        END {
            if (bad) exit 1
            if (length(seen) != expect) { print "expected " expect " presets, found " length(seen) > "/dev/stderr"; exit 1 }
            if (!("risu_custom" in seen)) { print "risu_custom missing" > "/dev/stderr"; exit 1 }
        }
    ' "$CONF"
}

get_preset_value() {
    awk -F'|' -v want="$1" '
        /^#/ || NF==0 { next }
        NF==4 && $1==want { print $4; found=1; exit }
        END { exit !found }
    ' "$CONF"
}

# --- Locking (mkdir is atomic). Stale locks (dead pid) are reclaimed. ------
acquire_lock() {
    mkdir -p "$STATEDIR" 2>/dev/null || return 1
    _i=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        _pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
            rm -rf "$LOCK_DIR"
            continue
        fi
        _i=$((_i + 1))
        [ "$_i" -ge 50 ] && return 1
        sleep 0.1
    done
    echo "$$" > "$LOCK_DIR/pid"
    trap 'release_lock' EXIT
    return 0
}
release_lock() { rm -rf "$LOCK_DIR" 2>/dev/null; }

# --- State: ONE file, replaced by one atomic rename ----------------------
read_state() {
    MODULE_STATE=""; ACTIVE_PRESET=""; ACTIVE_VALUE=""; CUSTOM_VALUE=""
    [ -f "$STATE_FILE" ] || return 1
    while IFS='=' read -r _key _val; do
        case "$_key" in
            module_state)  MODULE_STATE="$_val" ;;
            active_preset) ACTIVE_PRESET="$_val" ;;
            active_value)  ACTIVE_VALUE="$_val" ;;
            custom_value)  CUSTOM_VALUE="$_val" ;;
        esac
    done < "$STATE_FILE"
    return 0
}

write_state() {
    _tmp="${STATE_FILE}.tmp.$$"
    {
        printf 'module_state=%s\n'  "$1"
        printf 'active_preset=%s\n' "$2"
        printf 'active_value=%s\n'  "$3"
        printf 'custom_value=%s\n'  "$4"
    } > "$_tmp" || { rm -f "$_tmp"; return 1; }
    mv -f "$_tmp" "$STATE_FILE" || { rm -f "$_tmp"; return 1; }
}

# write + read back + compare
commit_state() {
    write_state "$1" "$2" "$3" "$4" || return 1
    read_state || return 1
    [ "$MODULE_STATE" = "$1" ]  || return 1
    [ "$ACTIVE_PRESET" = "$2" ] || return 1
    [ "$ACTIVE_VALUE" = "$3" ]  || return 1
    [ "$CUSTOM_VALUE" = "$4" ]  || return 1
    return 0
}

# validate_state: full coherence of the loaded state.
#  - no preset: only valid while disabled, active_value empty or 1.00,
#    custom_value empty or a valid in-range number (post-Reset shape)
#  - preset set: active_value must equal that preset's real value
validate_state() {
    case "$MODULE_STATE" in enabled|disabled) ;; *) return 1 ;; esac

    if [ -n "$CUSTOM_VALUE" ]; then
        validate_value "$CUSTOM_VALUE" >/dev/null || return 1
    fi

    if [ -z "$ACTIVE_PRESET" ]; then
        [ "$MODULE_STATE" = "disabled" ] || return 1
        if [ -n "$ACTIVE_VALUE" ]; then
            [ "$(validate_value "$ACTIVE_VALUE")" = "$NATIVE_VAL" ] || return 1
        fi
        return 0
    fi

    is_valid_id "$ACTIVE_PRESET" || return 1
    validate_presets_conf >/dev/null 2>&1 || return 1

    if [ "$ACTIVE_PRESET" = "risu_custom" ]; then
        _canon=$(validate_value "$CUSTOM_VALUE") || return 1
    else
        _raw=$(get_preset_value "$ACTIVE_PRESET") || return 1
        _canon=$(validate_value "$_raw") || return 1
    fi
    _stored=$(validate_value "$ACTIVE_VALUE") || return 1
    [ "$_stored" = "$_canon" ]
}

# --- Android package names -----------------------------------------------
# letters/digits/underscore segments separated by dots, >=2 segments, each
# starting with a letter, <=200 chars. Newlines/quotes/;|$ etc are rejected
# by the character whitelist before the structural check.
is_valid_package() {
    case "$1" in
        ''|*[!A-Za-z0-9_.]*) return 1 ;;
    esac
    [ "${#1}" -le 200 ] || return 1
    printf '%s' "$1" | awk 'BEGIN{ok=0} /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/{ok=1} END{exit !ok}'
}

# atomic replace of a list file from stdin content already in $2 (a temp)
# usage: atomic_install <tmpfile> <destfile>
atomic_install() { mv -f "$1" "$2" || { rm -f "$1"; return 1; }; }

# --- Backend -------------------------------------------------------------
service_available() {
    command -v service >/dev/null 2>&1 || return 1
    _out=$(service check SurfaceFlinger 2>/dev/null)
    case "$_out" in
        *"not found"*) return 1 ;;
        *"found"*)     return 0 ;;
        *)             return 1 ;;
    esac
}

# apply_saturation <validated value>
# Fails (non-zero) if: value fails validation, service missing, the
# command exits non-zero, or the reply is not a clean Parcel result.
# rc: 2 backend unavailable, 5 bad value, 6 backend reported failure
# On failure LAST_BACKEND_MSG holds a short, sanitized, real reason.
LAST_BACKEND_MSG=""
diag_clean() { printf '%s' "$1" | tr '\n' ' ' | tr -cd '[:print:]' | tr '|' '/' | cut -c1-100; }
apply_saturation() {
    LAST_BACKEND_MSG=""
    _v=$(validate_value "$1") || { LAST_BACKEND_MSG="value rejected by validation"; return 5; }
    service_available || { LAST_BACKEND_MSG="SurfaceFlinger service not available"; return 2; }
    _res=$(service call SurfaceFlinger 1022 f "$_v" 2>&1) || { LAST_BACKEND_MSG="service call failed: $(diag_clean "$_res")"; return 6; }
    case "$_res" in
        *"Result: Parcel("*) ;;
        *) LAST_BACKEND_MSG="unexpected reply: $(diag_clean "$_res")"; return 6 ;;
    esac
    case "$_res" in
        *[Ee]rror*|*[Ee]xception*) LAST_BACKEND_MSG="backend reported: $(diag_clean "$_res")"; return 6 ;;
    esac
    return 0
}

# --- Runtime override marker + bounded error history --------------------------
# OVR_FILE: "<pkg> <sat>" while a per-app profile value is on the backend.
# Anything that sets the backend itself (preset apply, reset, disable, boot)
# must clear it so the marker never claims a value that is no longer applied.
OVR_FILE="$STATEDIR/override"
clear_override() { rm -f "$OVR_FILE" 2>/dev/null; }

# ERRLOG: last 20 FAILURES only. Format: time|operation|value|reason
# (no package names, no paths, no arbitrary command output). Best effort.
ERRLOG="$STATEDIR/errors.log"
ERRLOG_MAX=20
log_error() { # <operation> <value|""> <reason>
    mkdir -p "$STATEDIR" 2>/dev/null
    _l="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)|$(diag_clean "$1")|$(diag_clean "$2")|$(diag_clean "$3")"
    _t="$ERRLOG.tmp.$$"
    { cat "$ERRLOG" 2>/dev/null; echo "$_l"; } | tail -n "$ERRLOG_MAX" > "$_t" 2>/dev/null && mv -f "$_t" "$ERRLOG" 2>/dev/null || rm -f "$_t" 2>/dev/null
    return 0
}
