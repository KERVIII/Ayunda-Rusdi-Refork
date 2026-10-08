#!/system/bin/sh
# Usage: apply_preset.sh <preset_id> [custom_value]
# For risu_custom with no value, the stored custom value (default 1.00) is used.
# Order: validate -> resolve -> lock -> apply -> commit+verify.
# On any failure after the backend call, the previous backend value is restored
# and the previous state file is left untouched.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

PRESET_ID="$1"
CUSTOM_RAW="$2"

fail() { echo "error: $1" >&2; exit "${2:-1}"; }

[ -n "$PRESET_ID" ] || fail "no preset id given" 1
is_valid_id "$PRESET_ID" || fail "invalid preset id" 1
validate_presets_conf 2>/dev/null || fail "presets.conf failed integrity check" 1
RAW_VALUE=$(get_preset_value "$PRESET_ID") || fail "unknown preset id: $PRESET_ID" 1

acquire_lock || fail "could not acquire state lock" 7
read_state
PREV_STATE="$MODULE_STATE"; PREV_VALUE="$ACTIVE_VALUE"; PREV_CUSTOM="$CUSTOM_VALUE"

if [ "$PRESET_ID" = "risu_custom" ]; then
    if [ -n "$CUSTOM_RAW" ]; then
        RAW_VALUE="$CUSTOM_RAW"
    elif [ -n "$PREV_CUSTOM" ]; then
        RAW_VALUE="$PREV_CUSTOM"
    else
        RAW_VALUE="$NATIVE_VAL"
    fi
fi

VAL=$(validate_value "$RAW_VALUE") || fail "invalid or out-of-range value: '$RAW_VALUE' (allowed $MIN_VAL-$MAX_VAL)" 2

apply_saturation "$VAL"
RC=$?
if [ $RC -ne 0 ]; then
    log_error "SurfaceFlinger apply" "$VAL" "$LAST_BACKEND_MSG"
    fail "SurfaceFlinger apply failed (rc=$RC); previous state kept" 3
fi

NEW_CUSTOM="$PREV_CUSTOM"
[ "$PRESET_ID" = "risu_custom" ] && NEW_CUSTOM="$VAL"
[ -n "$NEW_CUSTOM" ] || NEW_CUSTOM="$NATIVE_VAL"

if ! commit_state "enabled" "$PRESET_ID" "$VAL" "$NEW_CUSTOM"; then
    # roll back backend to what the (unchanged) persisted state implies
    if [ "$PREV_STATE" = "enabled" ] && [ -n "$PREV_VALUE" ]; then
        apply_saturation "$PREV_VALUE"
    else
        apply_saturation "$NATIVE_VAL"
    fi
    log_error "State commit" "$VAL" "state write/read-back failed; backend rolled back"
    fail "applied to backend but failed to commit/verify state; backend rolled back" 4
fi

clear_override
# the module is enabled now: start the per-app listener if profiles exist
release_lock; trap - EXIT
[ -s "$STATEDIR/profiles.conf" ] && sh "$DIR/watcher.sh" sync >/dev/null 2>&1
echo "OK $PRESET_ID $VAL"
exit 0
