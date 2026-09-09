#!/system/bin/sh
# Applies the persisted preset at boot (invoked by service.sh) or on demand.
#
# Exit code is meaningful: 0 only when either (a) we correctly did nothing
# because state is disabled/absent, or (b) we applied and the backend
# confirmed success. Non-zero means the backend call itself failed - this
# script does NOT swallow that into a fake success.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

if ! read_state || ! validate_state; then
    # Missing, corrupt, or internally inconsistent state (e.g. active_value
    # doesn't actually correspond to active_preset). Never apply an
    # unverified value. Self-heal to a safe disabled state so the same
    # corruption isn't re-evaluated on every future boot - this write does
    # not itself touch saturation, which is already native.
    commit_state "disabled" "" "" "" >/dev/null 2>&1
    exit 0
fi

[ "$MODULE_STATE" = "enabled" ] || exit 0

apply_saturation "$ACTIVE_VALUE"
exit $?
