#!/system/bin/sh
# Module Off: restore native saturation, mark disabled, keep the saved
# preset/value/custom_value (one atomic commit, only module_state changes).
DIR="$(dirname "$0")"
. "$DIR/common.sh"

acquire_lock || { echo "error: could not acquire state lock" >&2; exit 7; }

apply_saturation "$NATIVE_VAL"
RC=$?
if [ $RC -ne 0 ]; then
    log_error "Module off" "$NATIVE_VAL" "$LAST_BACKEND_MSG"
    echo "error: failed to restore native saturation (rc=$RC)" >&2
    exit $RC
fi

read_state
if ! commit_state "disabled" "$ACTIVE_PRESET" "$ACTIVE_VALUE" "$CUSTOM_VALUE"; then
    log_error "State commit" "$NATIVE_VAL" "disabled state write/read-back failed"
    echo "error: applied native saturation but failed to commit/verify disabled state" >&2
    exit 4
fi
clear_override
release_lock; trap - EXIT
# module is disabled: the per-app listener must not stay resident
[ -s "$STATEDIR/profiles.conf" ] && sh "$DIR/watcher.sh" sync >/dev/null 2>&1
echo "OK disabled"
exit 0
