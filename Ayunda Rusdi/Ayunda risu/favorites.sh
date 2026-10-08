#!/system/bin/sh
# Pinned (favorite) presets. Stores ONLY preset ids (never definitions);
# presets.conf stays the single source of truth for names/values.
#   favorites.sh list | pin <id> | unpin <id> | clear
# File: $STATEDIR/favorites.conf, one id per line, atomic replace.
DIR="$(dirname "$0")"
. "$DIR/common.sh"
FAV_FILE="$STATEDIR/favorites.conf"

# print valid, unique ids in pin order (unknown/malformed lines skipped)
fav_clean() {
    [ -f "$FAV_FILE" ] || return 0
    while IFS= read -r _l; do
        case "$_l" in ''|'#'*) continue ;; esac
        is_valid_id "$_l" || continue
        get_preset_value "$_l" >/dev/null || continue
        printf '%s\n' "$_l"
    done < "$FAV_FILE" | awk '!seen[$0]++'
}

fav_write() { # stdin = ids
    _t="${FAV_FILE}.tmp.$$"
    { echo "# pinned preset ids"; cat; } > "$_t" && atomic_install "$_t" "$FAV_FILE"
}

fail() { echo "error: $1" >&2; exit "${2:-1}"; }

case "$1" in
    list) fav_clean; exit 0 ;;
    pin|unpin)
        ID="$2"
        is_valid_id "$ID" || fail "invalid preset id" 1
        validate_presets_conf 2>/dev/null || fail "presets.conf failed integrity check" 1
        get_preset_value "$ID" >/dev/null || fail "unknown preset id: $ID" 1
        acquire_lock || fail "could not acquire state lock" 7
        CUR=$(fav_clean)
        if [ "$1" = pin ]; then
            { [ -n "$CUR" ] && echo "$CUR"; echo "$ID"; } | awk '!seen[$0]++' | fav_write || fail "could not write favorites" 4
        else
            { [ -n "$CUR" ] && echo "$CUR"; } | awk -v id="$ID" '$0!=id' | fav_write || fail "could not write favorites" 4
        fi
        # read back and verify
        if [ "$1" = pin ]; then fav_clean | grep -qx "$ID" || fail "favorite verify failed" 4
        else fav_clean | grep -qx "$ID" && fail "favorite verify failed" 4; fi
        echo "OK $1 $ID"; exit 0 ;;
    clear)
        acquire_lock || fail "could not acquire state lock" 7
        : | fav_write || fail "could not write favorites" 4
        echo "OK clear"; exit 0 ;;
    *) fail "usage: favorites.sh list|pin <id>|unpin <id>|clear" 1 ;;
esac
