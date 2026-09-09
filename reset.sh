#!/system/bin/sh
# Reset: restore native saturation, then commit a fully cleared/disabled
# state as ONE atomic unit, and verify the commit actually landed before
# reporting success.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

apply_saturation 1.00
RC=$?
if [ $RC -ne 0 ]; then
    echo "error: failed to restore native saturation (rc=$RC); state unchanged" >&2
    exit $RC
fi

if ! commit_state "disabled" "" "" ""; then
    echo "error: applied native saturation but failed to commit/verify cleared state" >&2
    exit 4
fi

# Explicit cleanup verification (belt-and-suspenders beyond commit_state's
# own read-back): re-read once more and confirm nothing was left active.
read_state
if [ "$MODULE_STATE" != "disabled" ] || [ -n "$ACTIVE_PRESET" ] || [ -n "$ACTIVE_VALUE" ] || [ -n "$CUSTOM_VALUE" ]; then
    echo "error: reset verification failed - state not fully cleared" >&2
    exit 5
fi

echo "OK reset"
exit 0
