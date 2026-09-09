
if [ -f $INFO ]; then
  while read LINE; do
    if [ "$(echo -n $LINE | tail -c 1)" == "~" ]; then
      continue
    elif [ -f "$LINE~" ]; then
      mv -f $LINE~ $LINE
    else
      rm -f $LINE
      while true; do
        LINE=$(dirname $LINE)
        [ "$(ls -A $LINE 2>/dev/null)" ] && break 1 || rm -rf $LINE
      done
    fi
  done < $INFO
  rm -f $INFO
fi

# Risu Color Presets - full removal cleanup.
# This only runs when the module is explicitly removed, not on ordinary
# updates/reinstalls (those go through customize.sh instead), so it's safe
# to drop the persistent state directory here.
service call SurfaceFlinger 1022 f 1.0 >/dev/null 2>&1
rm -rf /data/adb/risu-color-enhancer
