#!/system/bin/sh
# Usage: apply_preset.sh <preset_id> [custom_value]
#
# Order (unchanged principle from v6.1, now committing ONE state file):
#   1. validate input          5. apply SurfaceFlinger value
#   2. resolve preset          6. confirm the command succeeded
#   3. validate final value    7. commit the COMPLETE new state atomically
#   4. (exact-id lookup)       8. verify the commit landed, then report
#
# If any step fails, nothing is committed - the previous state file is
# left byte-for-byte untouched.
DIR="$(dirname "$0")"
. "$DIR/common.sh"

PRESET_ID="$1"
CUSTOM_RAW="$2"

fail() {
    echo "error: $1" >&2
    exit "${2:-1}"
}

[ -n "$PRESET_ID" ] || fail "no preset id given" 1

validate_presets_conf || fail "presets.conf failed integrity check" 1

RAW_VALUE=$(get_preset_value "$PRESET_ID") || fail "unknown preset id: $PRESET_ID" 1

if [ "$PRESET_ID" = "risu_custom" ]; then
    RAW_VALUE="$CUSTOM_RAW"
fi

VAL=$(validate_and_clamp "$RAW_VALUE") || fail "invalid value: '$RAW_VALUE'" 2

apply_saturation "$VAL"
RC=$?
if [ $RC -ne 0 ]; then
    fail "SurfaceFlinger apply failed (rc=$RC); previous state kept" 3
fi

# Preserve the last custom value across preset switches unless we're the
# ones setting it right now.
read_state
NEW_CUSTOM="$CUSTOM_VALUE"
[ "$PRESET_ID" = "risu_custom" ] && NEW_CUSTOM="$VAL"

if ! commit_state "enabled" "$PRESET_ID" "$VAL" "$NEW_CUSTOM"; then
    fail "applied to backend but failed to commit/verify new state" 4
fi

echo "OK $PRESET_ID $VAL"
exit 0
