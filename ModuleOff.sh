#!/system/bin/sh
# Module Off: restore native saturation and mark disabled, keeping the
# saved preset/value/custom_value intact as ONE unchanged-except-module_state
# atomic commit - re-selecting a preset later re-enables and reapplies.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

apply_saturation 1.00
RC=$?
if [ $RC -ne 0 ]; then
    echo "error: failed to restore native saturation (rc=$RC)" >&2
    exit $RC
fi

read_state
if ! commit_state "disabled" "$ACTIVE_PRESET" "$ACTIVE_VALUE" "$CUSTOM_VALUE"; then
    echo "error: applied native saturation but failed to commit/verify disabled state" >&2
    exit 4
fi

echo "OK disabled"
exit 0
