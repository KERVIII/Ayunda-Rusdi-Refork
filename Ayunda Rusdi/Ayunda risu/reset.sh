#!/system/bin/sh
# Reset: apply native 1.00, persist 1.00, clear the preset selection.
# Final state: module_state=disabled, active_preset empty,
# active_value=1.00, custom_value=1.00. Success only if verified.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

acquire_lock || { echo "error: could not acquire state lock" >&2; exit 7; }

apply_saturation "$NATIVE_VAL"
RC=$?
if [ $RC -ne 0 ]; then
    log_error "Reset" "$NATIVE_VAL" "$LAST_BACKEND_MSG"
    echo "error: failed to restore native saturation (rc=$RC); state unchanged" >&2
    exit $RC
fi

if ! commit_state "disabled" "" "$NATIVE_VAL" "$NATIVE_VAL"; then
    log_error "State commit" "$NATIVE_VAL" "reset state write/read-back failed"
    echo "error: applied native saturation but failed to commit/verify reset state" >&2
    exit 4
fi
clear_override
release_lock; trap - EXIT
# module is disabled now: stop the per-app listener (restores nothing: native is applied)
[ -s "$STATEDIR/profiles.conf" ] && sh "$DIR/watcher.sh" sync >/dev/null 2>&1
# also restore System UI animation scales if this module changed them
TW=$(sh "$DIR/ui_tweaks.sh" restore 2>&1)
if [ $? -ne 0 ]; then
    log_error "Reset (animation restore)" "" "$TW"
    echo "error: saturation reset to 1.00 but animation restore failed: $TW" >&2
    exit 6
fi
echo "OK reset 1.00"
exit 0
