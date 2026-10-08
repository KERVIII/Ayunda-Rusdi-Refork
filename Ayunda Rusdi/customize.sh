ui_print "------------------------------------"
ui_print "   Ayunda Rusdi Color Enhancer V7.0 "
ui_print "------------------------------------"
ui_print " Fork: KERVIII | Original: Kanagawa Yamada"
ui_print "------------------------------------"
ui_print "DEVICE : $(getprop ro.build.product)"
ui_print "MODEL : $(getprop ro.product.model)"
ui_print "ANDROID VER : $(getprop ro.build.version.release)"
ui_print "KERNEL : $(uname -r)"
ui_print "Version : ${MODVER:-$(grep -m1 '^version=' "$MODPATH/module.prop" 2>/dev/null | cut -d= -f2-)}"
ui_print "Support Root : Magisk / KernelSU / APatch"
ui_print " "
ui_print "  Only SurfaceFlinger saturation is changed."
ui_print "  Use Reset in the WebUI if colors look wrong."
ui_print " "
sleep 1

# Files are extracted to $MODPATH by the root manager (SKIPUNZIP is not set).
set_perm_recursive "$MODPATH/AyundaRisu" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

# Persistent user state lives OUTSIDE the module payload so it survives
# module upgrades/reinstalls (Magisk/KernelSU/APatch replace $MODPATH
# wholesale on every flash - anything stored inside it would be lost).
# v6.2: state is ONE file (state.conf) so the whole state commits or
# doesn't - never a mix of old/new fields across separate files.
STATEDIR=/data/adb/risu-color-enhancer
mkdir -p "$STATEDIR"
set_perm_recursive "$STATEDIR" 0 0 0755 0644

STATE_FILE="$STATEDIR/state.conf"
if [ ! -f "$STATE_FILE" ]; then
	MIGRATED=0

	# Path A: upgrading from a v6.1 install, which stored state as four
	# separate files directly in STATEDIR.
	LEGACY_V61="$STATEDIR"
	if [ -f "$LEGACY_V61/module_state" ] && [ -f "$LEGACY_V61/active_preset" ] && [ -f "$LEGACY_V61/active_value" ]; then
		ui_print "- Migrating preset selection from a v6.1 install"
		_ms=$(cat "$LEGACY_V61/module_state" 2>/dev/null)
		_ap=$(cat "$LEGACY_V61/active_preset" 2>/dev/null)
		_av=$(cat "$LEGACY_V61/active_value" 2>/dev/null)
		_cv=$(cat "$LEGACY_V61/custom_value" 2>/dev/null)
		{
			printf 'module_state=%s\n'  "$_ms"
			printf 'active_preset=%s\n' "$_ap"
			printf 'active_value=%s\n'  "$_av"
			printf 'custom_value=%s\n'  "$_cv"
		} > "$STATE_FILE"
		rm -f "$LEGACY_V61/module_state" "$LEGACY_V61/active_preset" "$LEGACY_V61/active_value" "$LEGACY_V61/custom_value"
		MIGRATED=1
	fi

	# Path B: upgrading from a v6.0 install, which stored state inside the
	# module directory itself.
	if [ "$MIGRATED" = "0" ]; then
		LEGACY_V60=/data/adb/modules/AyundaRusdi/AyundaRisu
		if [ -f "$LEGACY_V60/active_preset" ] && [ -f "$LEGACY_V60/active_value" ]; then
			ui_print "- Migrating preset selection from a v6.0 install"
			_ap=$(cat "$LEGACY_V60/active_preset" 2>/dev/null)
			_av=$(cat "$LEGACY_V60/active_value" 2>/dev/null)
			{
				printf 'module_state=enabled\n'
				printf 'active_preset=%s\n' "$_ap"
				printf 'active_value=%s\n'  "$_av"
				printf 'custom_value=%s\n'  "$_av"
			} > "$STATE_FILE"
			MIGRATED=1
		fi
	fi

	# Path C: fresh install - default to Risu Natural, enabled.
	if [ "$MIGRATED" = "0" ]; then
		{
			printf 'module_state=enabled\n'
			printf 'active_preset=risu_natural\n'
			printf 'active_value=1.05\n'
			printf 'custom_value=1.00\n'
		} > "$STATE_FILE"
	fi
fi

if command -v magisk >/dev/null 2>&1; then
	if ! pm list packages | grep -q io.github.a13e300.ksuwebui; then
		ui_print "- Magisk detected, installing KSU WebUI for Magisk"
		cp "$MODPATH/webui.apk" /data/local/tmp/ >/dev/null 2>&1
		pm install /data/local/tmp/webui.apk >/dev/null 2>&1
		rm -f /data/local/tmp/webui.apk >/dev/null 2>&1
	fi

	if ! pm list packages | grep -q io.github.a13e300.ksuwebui; then
		ui_print "! Can't install KSU WebUI due to selinux restrictions"
		ui_print "! Please install the app manually after installation."
	else
		ui_print "- Please grant root permission for KSU WebUI"
	fi
fi

# test suite is for development only; do not leave it on the device
rm -rf "$MODPATH/tests"
