#!/system/bin/sh
# Boot/on-demand apply of the persisted preset. Exit 0 only if it correctly
# did nothing (disabled/absent state) or the backend confirmed success.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

acquire_lock || exit 7

if ! read_state || ! validate_state; then
    # missing/corrupt/inconsistent: never apply an unverified value; self-heal
    # to a safe disabled state (native saturation already in effect).
    log_error "State validation" "" "state file missing, corrupt or inconsistent; reset to disabled/native"
    commit_state "disabled" "" "$NATIVE_VAL" "$NATIVE_VAL" >/dev/null 2>&1
    exit 0
fi

clear_override       # a reboot always starts from the saved global state
[ "$MODULE_STATE" = "enabled" ] || exit 0
apply_saturation "$ACTIVE_VALUE"
RC=$?
[ $RC -eq 0 ] || log_error "Boot apply" "$ACTIVE_VALUE" "$LAST_BACKEND_MSG"
exit $RC
