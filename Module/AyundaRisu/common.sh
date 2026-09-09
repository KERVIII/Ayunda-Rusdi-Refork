#!/system/bin/sh
# Risu Color Presets - shared helpers (v6.2).
# Sourced by ModuleOn.sh, ModuleOff.sh, apply_preset.sh, reset.sh.
# The ONLY place that defines: paths, validation, preset lookup, state
# read/write/verify, and the backend apply call.

# --- Paths -------------------------------------------------------------
MODDIR="/data/adb/modules/AyundaRusdi/AyundaRisu"
STATEDIR="/data/adb/risu-color-enhancer"
STATE_FILE="$STATEDIR/state.conf"
CONF="$MODDIR/presets.conf"

MIN_VAL="0.00"
MAX_VAL="2.50"
EXPECTED_PRESET_COUNT=15

# --- Validation ----------------------------------------------------------
# is_valid_number <value>
#   valid:   0  0.5  1  1.00  1.25  2.5  2.50
#   invalid: (empty)  .  ..  1.2.3  abc  1x  --  ++1
is_valid_number() {
    printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'
}

# clamp_value <value>: caller must have already confirmed is_valid_number.
clamp_value() {
    awk -v v="$1" -v lo="$MIN_VAL" -v hi="$MAX_VAL" 'BEGIN{
        if (v+0 < lo) v = lo;
        if (v+0 > hi) v = hi;
        printf "%.2f", v+0;
    }'
}

# validate_and_clamp <value>: prints the clamped value, returns 0 on
# success. Returns 1 (prints nothing) if not a valid number at all.
validate_and_clamp() {
    is_valid_number "$1" || return 1
    clamp_value "$1"
}

# --- presets.conf parsing (awk only, exact-match, no regex on user input) -
validate_presets_conf() {
    [ -f "$CONF" ] || { echo "error: presets.conf missing" >&2; return 1; }
    awk -F'|' -v expect="$EXPECTED_PRESET_COUNT" '
        /^#/ || NF==0 { next }
        {
            if (NF != 4) { print "malformed row: " $0 > "/dev/stderr"; bad=1; next }
            id=$1
            if (id in seen) { print "duplicate preset id: " id > "/dev/stderr"; bad=1; next }
            seen[id]=1
            if ($2 == "" || $3 == "" || $4 == "") {
                print "missing field(s) for preset: " id > "/dev/stderr"; bad=1
            }
        }
        END {
            if (bad) exit 1
            if (length(seen) != expect) {
                print "expected " expect " presets, found " length(seen) > "/dev/stderr"
                exit 1
            }
        }
    ' "$CONF"
}

# get_preset_value <id>: exact-id lookup only. Prints the raw value field
# and returns 0 on a single exact match; returns 1 otherwise.
get_preset_value() {
    awk -F'|' -v want="$1" '
        /^#/ || NF==0 { next }
        NF==4 && $1==want { print $4; found=1; exit }
        END { exit !found }
    ' "$CONF"
}

# --- State (single file, atomic whole-state commit) -----------------------
# State is ONE file: module_state / active_preset / active_value /
# custom_value are written and replaced together, never individually, so a
# partial update (some fields new, some old) is structurally impossible -
# either the whole file is replaced by one atomic rename, or nothing is.

# read_state: populates MODULE_STATE / ACTIVE_PRESET / ACTIVE_VALUE /
# CUSTOM_VALUE from STATE_FILE. Never evaluates the file as shell code -
# only these four keys are recognized, anything else is ignored. Returns 1
# if the file doesn't exist (caller should treat that as "no state yet").
read_state() {
    MODULE_STATE=""
    ACTIVE_PRESET=""
    ACTIVE_VALUE=""
    CUSTOM_VALUE=""
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

# write_state <module_state> <active_preset> <active_value> <custom_value>
# Builds the complete new state in memory, writes it to a temp file in the
# same directory, then commits it with ONE rename. Never partially visible.
write_state() {
    _tmp="${STATE_FILE}.tmp.$$"
    {
        printf 'module_state=%s\n'  "$1"
        printf 'active_preset=%s\n' "$2"
        printf 'active_value=%s\n'  "$3"
        printf 'custom_value=%s\n'  "$4"
    } > "$_tmp" || return 1
    mv -f "$_tmp" "$STATE_FILE"
}

# commit_state <module_state> <active_preset> <active_value> <custom_value>
# write_state, then reads the result back and confirms it matches, so
# callers never report success on a write that silently failed/partially
# landed (e.g. out of disk space, filesystem remounted read-only mid-write).
commit_state() {
    write_state "$1" "$2" "$3" "$4" || return 1
    read_state || return 1
    [ "$MODULE_STATE" = "$1" ]  || return 1
    [ "$ACTIVE_PRESET" = "$2" ] || return 1
    [ "$ACTIVE_VALUE" = "$3" ]  || return 1
    [ "$CUSTOM_VALUE" = "$4" ]  || return 1
    return 0
}

# validate_state: call after read_state. Checks the CURRENTLY LOADED state
# (MODULE_STATE/ACTIVE_PRESET/ACTIVE_VALUE/CUSTOM_VALUE) for full internal
# coherence - not just "is each field individually well-formed" but "does
# active_value actually correspond to active_preset". A tampered/corrupt
# file with a valid-looking but WRONG active_value (e.g. active_preset=
# risu_natural but active_value=1.90) is rejected here, not just a
# malformed one.
validate_state() {
    case "$MODULE_STATE" in
        enabled|disabled) ;;
        *) return 1 ;;
    esac

    if [ -z "$ACTIVE_PRESET" ]; then
        # No preset selected is only valid while disabled (post-Reset).
        [ "$MODULE_STATE" = "disabled" ] && return 0
        return 1
    fi

    validate_presets_conf || return 1

    if [ "$ACTIVE_PRESET" = "risu_custom" ]; then
        _canon=$(validate_and_clamp "$CUSTOM_VALUE") || return 1
    else
        _raw=$(get_preset_value "$ACTIVE_PRESET") || return 1
        _canon=$(validate_and_clamp "$_raw") || return 1
    fi

    _stored=$(validate_and_clamp "$ACTIVE_VALUE") || return 1
    [ "$_stored" = "$_canon" ] || return 1

    return 0
}

# --- Backend -----------------------------------------------------------
# service_available: confirms `service` exists and SurfaceFlinger is
# registered before attempting the real transaction. Read-only, standard
# `service check` subcommand - not a new/unverified transaction.
service_available() {
    command -v service >/dev/null 2>&1 || return 1
    _out=$(service check SurfaceFlinger 2>/dev/null)
    case "$_out" in
        *"not found"*) return 1 ;;
        *"found"*)     return 0 ;;
        *)             return 1 ;;
    esac
}

# apply_saturation <value>: THE verified backend call. Caller must pass an
# already-validated/clamped value. Returns non-zero if SurfaceFlinger is
# unavailable or the call failed at the shell level - this return code is
# authoritative and must not be discarded by any caller.
apply_saturation() {
    service_available || return 2
    service call SurfaceFlinger 1022 f "$1" >/dev/null 2>&1
}
