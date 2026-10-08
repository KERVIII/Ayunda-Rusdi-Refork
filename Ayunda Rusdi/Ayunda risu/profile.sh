#!/system/bin/sh
# Per-app profiles: package -> preset id OR saturation value.
#   profile.sh list      -> profiles_dropped=N and profile=pkg|kind|value|resolved|ok|installed
#   profile.sh set <package> preset <preset_id>
#   profile.sh set <package> sat <0.00-2.50>
#   profile.sh delete <package> | clear
#   profile.sh apply <package>     one-shot apply: makes the profile your CURRENT
#                                  global setting (committed state)
#   profile.sh resolve <package>   print the profile's saturation (used by the
#                                  listener; read-only), exit 1 if none/broken
# Automatic switching when an app opens is done by watcher.sh (event-driven).
# File: $STATEDIR/profiles.conf  lines: package|preset|<id>  or  package|sat|<value>
# Presets are referenced by id and resolved through presets.conf at apply
# time (no duplicated values).
DIR="$(dirname "$0")"
. "$DIR/common.sh"
PF="$STATEDIR/profiles.conf"
MAX_PROFILES=64

fail() { echo "error: $1" >&2; exit "${2:-1}"; }

# valid rows only (malformed/duplicate/unresolvable-kind rows are dropped)
prof_clean() {
    [ -f "$PF" ] || return 0
    while IFS='|' read -r _p _k _v _x; do
        [ -z "$_x" ] || continue
        is_valid_package "$_p" || continue
        case "$_k" in
            preset) is_valid_id "$_v" || continue ;;
            sat)    validate_value "$_v" >/dev/null || continue; _v=$(validate_value "$_v") ;;
            *) continue ;;
        esac
        printf '%s|%s|%s\n' "$_p" "$_k" "$_v"
    done < "$PF" | awk -F'|' '!seen[$1]++'
}
prof_raw_count() { _n=$([ -f "$PF" ] && grep -avc '^#\|^$' "$PF" 2>/dev/null); echo "${_n:-0}"; }
prof_write() { _t="${PF}.tmp.$$"; { echo "# per-app profiles"; cat; } > "$_t" && atomic_install "$_t" "$PF"; }

# resolve row -> canonical saturation (fails if preset gone / custom)
prof_resolve() { # <kind> <value>
    if [ "$1" = sat ]; then validate_value "$2"; return; fi
    _r=$(get_preset_value "$2") || return 1
    [ "$_r" = custom ] && return 1
    validate_value "$_r"
}

case "$1" in
    list)
        ROWS=$(prof_clean); N=0; [ -n "$ROWS" ] && N=$(printf '%s\n' "$ROWS" | wc -l)
        echo "profiles_dropped=$(( $(prof_raw_count) - N ))"
        # one package-manager call for all rows: installed=1, 0 (not installed) or ? (cannot tell)
        PKGS=""; PMOK=0
        if [ -n "$ROWS" ] && command -v pm >/dev/null 2>&1; then
            PKGS=$(pm list packages 2>/dev/null) && [ -n "$PKGS" ] && PMOK=1
        fi
        [ -n "$ROWS" ] && printf '%s\n' "$ROWS" | while IFS='|' read -r p k v; do
            if [ "$PMOK" = 1 ]; then
                if printf '%s\n' "$PKGS" | grep -qxF "package:$p"; then I=1; else I=0; fi
            else I='?'; fi
            if r=$(prof_resolve "$k" "$v"); then echo "profile=$p|$k|$v|$r|ok|$I"; else echo "profile=$p|$k|$v||broken|$I"; fi
        done
        exit 0 ;;
    set)
        PKG="$2"; KIND="$3"; VAL="$4"
        is_valid_package "$PKG" || fail "invalid package name" 1
        case "$KIND" in
            preset)
                is_valid_id "$VAL" || fail "invalid preset id" 1
                validate_presets_conf 2>/dev/null || fail "presets.conf failed integrity check" 1
                [ "$VAL" = risu_custom ] && fail "use a saturation profile instead of Risu Custom" 1
                get_preset_value "$VAL" >/dev/null || fail "unknown preset id: $VAL" 1 ;;
            sat) VAL=$(validate_value "$VAL") || fail "invalid or out-of-range saturation (allowed $MIN_VAL-$MAX_VAL)" 2 ;;
            *) fail "kind must be preset or sat" 1 ;;
        esac
        # NOTE: an uninstalled package is still stored (it may be installed later);
        # `list` reports installed=0 so the UI can show it as unavailable.
        acquire_lock || fail "could not acquire state lock" 7
        CUR=$(prof_clean)
        EXISTS=$(printf '%s\n' "$CUR" | awk -F'|' -v p="$PKG" '$1==p' | wc -l)
        N=0; [ -n "$CUR" ] && N=$(printf '%s\n' "$CUR" | wc -l)
        [ "$EXISTS" -gt 0 ] || [ "$N" -lt "$MAX_PROFILES" ] || fail "profile limit reached ($MAX_PROFILES)" 9
        { [ -n "$CUR" ] && printf '%s\n' "$CUR" | awk -F'|' -v p="$PKG" '$1!=p'; printf '%s|%s|%s\n' "$PKG" "$KIND" "$VAL"; } | prof_write || fail "could not write profiles" 4
        prof_clean | grep -qxF "$PKG|$KIND|$VAL" || fail "profile verify failed" 4
        release_lock; trap - EXIT; sh "$DIR/watcher.sh" sync >/dev/null 2>&1
        echo "OK set $PKG"; exit 0 ;;
    delete)
        PKG="$2"; is_valid_package "$PKG" || fail "invalid package name" 1
        acquire_lock || fail "could not acquire state lock" 7
        CUR=$(prof_clean)
        printf '%s\n' "$CUR" | awk -F'|' -v p="$PKG" 'NF && $1!=p' | prof_write || fail "could not write profiles" 4
        prof_clean | awk -F'|' -v p="$PKG" '$1==p' | grep -q . && fail "profile verify failed" 4
        release_lock; trap - EXIT; sh "$DIR/watcher.sh" sync >/dev/null 2>&1
        echo "OK delete $PKG"; exit 0 ;;
    clear)
        acquire_lock || fail "could not acquire state lock" 7
        : | prof_write || fail "could not write profiles" 4
        release_lock; trap - EXIT; sh "$DIR/watcher.sh" sync >/dev/null 2>&1
        echo "OK clear"; exit 0 ;;
    resolve)
        PKG="$2"; is_valid_package "$PKG" || exit 1
        ROW=$(prof_clean | awk -F'|' -v p="$PKG" '$1==p {print; exit}')
        [ -n "$ROW" ] || exit 1
        prof_resolve "$(echo "$ROW" | cut -d'|' -f2)" "$(echo "$ROW" | cut -d'|' -f3)" || exit 1
        exit 0 ;;
    apply)
        PKG="$2"; is_valid_package "$PKG" || fail "invalid package name" 1
        ROW=$(prof_clean | awk -F'|' -v p="$PKG" '$1==p {print; exit}')
        [ -n "$ROW" ] || fail "no profile for $PKG" 1
        KIND=$(echo "$ROW" | cut -d'|' -f2); VAL=$(echo "$ROW" | cut -d'|' -f3)
        SAT=$(prof_resolve "$KIND" "$VAL") || { log_error "Per-app profile apply" "" "profile is broken (preset missing or invalid value)"; fail "profile for $PKG is broken (preset missing or invalid value)" 1; }
        if [ "$KIND" = preset ]; then TARGET="$VAL"; ARG=""; else TARGET="risu_custom"; ARG="$SAT"; fi
        # skip redundant backend calls
        if read_state && [ "$MODULE_STATE" = enabled ] && [ "$ACTIVE_PRESET" = "$TARGET" ] && [ "$(validate_value "$ACTIVE_VALUE" 2>/dev/null)" = "$SAT" ]; then
            echo "OK unchanged $TARGET $SAT"; exit 0
        fi
        exec sh "$DIR/apply_preset.sh" "$TARGET" $ARG ;;
    *) fail "usage: profile.sh list|set|delete|clear|apply" 1 ;;
esac
