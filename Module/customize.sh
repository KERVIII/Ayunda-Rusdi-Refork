ui_print "------------------------------------"
ui_print "      Ayunda Risu Color Enhancer    "
ui_print "------------------------------------"
ui_print "         By: Kanagawa Yamada        "
ui_print "------------------------------------"
ui_print "      READ THE TELEGRAM MESSAGE     "
ui_print "------------------------------------"
ui_print " "
sleep 1.5

ui_print "------------------------------------"
ui_print "            DEVICE INFO             "
ui_print "------------------------------------"
ui_print "DEVICE : $(getprop ro.build.product) "
ui_print "MODEL : $(getprop ro.product.model) "
ui_print "MANUFACTURE : $(getprop ro.product.system.manufacturer) "
ui_print "PROC : $(getprop ro.product.board) "
ui_print "CPU : $(getprop ro.hardware) "
ui_print "ANDROID VER : $(getprop ro.build.version.release) "
ui_print "KERNEL : $(uname -r) "
ui_print "RAM : $(free | grep Mem |  awk '{print $2}') "
ui_print " "
sleep 1.5

ui_print "------------------------------------"
ui_print "            MODULE INFO             "
ui_print "------------------------------------"
ui_print "Name : Rusdi Color Enhancer"
ui_print "Version : 6.7"
ui_print "Support Root : Magisk / KernelSU / APatch"
ui_print " "
sleep 1.5

ui_print "      DON'T BLAME ME IF YOUR        "
ui_print "         SCREEN GETS BLACK          "
ui_print " "
sleep 3

ui_print "      Installing Ayunda Risu        "
sleep 3

unzip -o "$ZIPFILE" "webroot/*" -d "$MODPATH" >&2
unzip -o "$ZIPFILE" 'AyundaRisu/*' -d $MODPATH >&2
set_perm_recursive $MODPATH/AyundaRisu 0 0 0755 0755

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

# presets.conf is authored once under AyundaRisu/ (read by the shell backend)
# and mirrored into webroot/ so the WebUI can fetch the exact same data
# instead of hardcoding a second copy.
cp -f "$MODPATH/AyundaRisu/presets.conf" "$MODPATH/webroot/presets.conf"

if [ "$(which magisk)" ]; then
	extract "$ZIPFILE" 'action.sh' $MODPATH

	if ! pm list packages | grep -q io.github.a13e300.ksuwebui; then
		ui_print "- Magisk detected, Installing KSU WebUI for Magisk"
        cp "$MODPATH"/webui.apk /data/local/tmp >/dev/null 2>&1
        pm install /data/local/tmp/webui.apk >/dev/null 2>&1
        rm /data/local/tmp/webui.apk >/dev/null 2>&1
	fi

	if ! pm list packages | grep -q io.github.a13e300.ksuwebui; then
		ui_print "! Can't install KSU WebUI due to selinux restrictions"
		ui_print "! Please install the app manually after installation."
	else
		ui_print "- Please grant root permission for KSU WebUI"
	fi
fi

am start -a android.intent.action.VIEW -d "https://github.com/KERVIII/Ayunda-Rusdi-Refork" >/dev/null 2>&1