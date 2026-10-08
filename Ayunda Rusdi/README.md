# Ayunda Rusdi Color Enhancer 7.0

Magisk / KernelSU / APatch module that adjusts display **saturation** through
SurfaceFlinger, with an optional **System UI animation-scale tweak**, pinned presets, per-app profiles and a shareable diagnostic. Fork of
Ayunda Risu Color Enhancer by Kanagawa Yamada, maintained by KERVIII.

## What it actually controls

| Feature | Mechanism |
|---|---|
| Color | `service call SurfaceFlinger 1022 f <value>` — global saturation, `1.00` = native, valid range `0.00–2.50` |
| System UI Tweaks | `settings put global window_animation_scale / transition_animation_scale / animator_duration_scale` (default tweak `0.85`, valid `0.25–2.00`) |

There is **no** independent contrast, gamma, RGB, white-balance, black-level,
HDR or P3 control. Every preset is a saturation profile; descriptions name the
visual target and are not claims of hardware color-space switching. The
accepted range (0.00–2.50) is this module's own limit.

## Presets (18)

Defined once in `AyundaRisu/presets.conf` (`id|name|description|value`); the
WebUI and the shell scripts both read this file.

| # | Preset | Saturation |
|---|---|---|
| 1 | Risu True | 1.00 |
| 2 | Risu Paper | 0.90 |
| 3 | Risu Natural | 1.05 |
| 4 | Risu Cinema | 1.12 |
| 5 | Risu Ice | 1.18 |
| 6 | Risu Deep | 1.25 |
| 7 | Risu P3 | 1.30 |
| 8 | Risu Ember | 1.35 |
| 9 | Risu AMOLED | 1.40 |
| 10 | Risu HDR | 1.45 |
| 11 | Risu Game | 1.50 |
| 12 | Risu Vivid | 1.55 |
| 13 | Risu Anime | 1.75 |
| 14 | Risu Hyper | 2.20 |
| 15 | Risu Custom | user value 0.00–2.50 (default 1.00) |
| 16 | Risu Muted | 0.75 |
| 17 | Risu Comic | 1.90 |
| 18 | Risu OLED | 1.20 |

Risu HDR is a saturation profile, **not real HDR**. Risu P3 does **not** switch to a DCI-P3 color space. Risu AMOLED / OLED / Deep give **no** hardware black-level control. Values for presets 1–14 are unchanged from V6.7. Muted, Comic and OLED are new
in V7.0; their values are saturation choices, not measured color science.


## Pinned presets (favorites)

Tap the star on a preset card to pin it. Pinned presets appear as one-tap chips
on Home and Presets. Stored as preset **ids only** in
`/data/adb/risu-color-enhancer/favorites.conf` (atomic write, read-back
verified, malformed lines ignored); names and values always come from
`presets.conf`. Survives WebUI reloads, reboots, module updates and Reset.

## Per-App Profiles

A profile maps an Android package (e.g. `com.example.game`) to either a preset
or a saturation value (0.00–2.50). Create, edit, apply and delete from
**Controls → Per-App Profiles**; package names and values are validated, and
when the package manager can answer, the package must be installed. Stored in
`profiles.conf` (max 64, atomic, malformed rows ignored, never required for
boot).

### Automatic switching

When an app with a profile comes to the foreground, its saturation is applied
through the normal backend (`service call SurfaceFlinger 1022 f <value>`, reply
checked); when you leave it, your saved setting is restored. Your saved global
preset/state (`state.conf`) is **never modified** by this. Profiles are not
applied while the module is disabled (Disable / Reset); selecting a preset
re-enables it.

How it works (no polling): `AyundaRisu/watcher.sh` keeps one blocking
`logcat -b events` stream open, filtered to the `wm_set_resumed_activity`
event that Android's activity manager emits when the foreground activity
changes. It sleeps in `read()` between events and spawns a short-lived shell
only when the foreground **package** changes (repeated events for the same
package are ignored). It runs only while auto switching is on **and** at least
one profile exists — with no profiles there is no process. It starts at boot
from `service.sh` and is stopped by deleting the last profile, turning auto
switching off, or uninstalling (all of which restore your global setting).
The Controls tab shows the real state: Auto switching, Listener
(Running / Not running / Off / Unsupported), **Last app seen**, and the
profile currently in effect.

Additional behavior: the listener runs only while **auto switching is on, the
module is enabled (Disable/Reset stop it; selecting a preset re-enables it) and
at least one valid profile exists**. A single-instance lock prevents duplicate
listeners (a stale lock from a dead process is reclaimed; unrelated processes
are never touched). The backend is called only when the required value actually
changes, and the saved global value (not a fixed 1.00) is what gets restored.
A profile for an app that is not installed is still stored and shown as
`NOT INSTALLED` (the installed flag comes from one `pm list packages` call; if
`pm` is unavailable it is unknown, not claimed). The Controls card shows Auto
switching, Listener, Last app seen, Active profile, Active value and the real
result of the last apply (PASS / FAIL with the backend's message). To check
whether your ROM emits the foreground event, press **Save Logs** / **Copy** and
read "Foreground event source" (one-shot dump of the events buffer, no
streaming).

Costs and limits, honestly:
- It is one resident `sh` + `logcat` pair while profiles exist. It wakes for
  each entry in Android's events log buffer (typically a few per second) and
  does nothing for entries that are not foreground changes.
- It depends on the ROM emitting `wm_set_resumed_activity`. **This was tested
  with a simulated event stream only, not on a real device.** If "Last app
  seen" stays empty after you switch apps, your ROM does not provide the event
  and automatic switching cannot work there; turn it off, or use Apply or an
  automation tool running
  `sh /data/adb/modules/AyundaRusdi/AyundaRisu/profile.sh apply <package>`
  (this one **sets the profile as your current global setting**).
- Needs `setsid` and `logcat`; if missing the Listener shows "Unsupported".
- The first matching app wins; switching directly between two profiled apps
  applies the second one's value without passing through the global value.

## Diagnostic Log

**Controls → Diagnostic Log** shows a report generated by
`AyundaRisu/diagnostic.sh` from the live module state, with two buttons:

- **Copy** copies exactly the text the file would contain (clipboard, with a
  fallback; a failure is reported as a failure).
- **Save Logs** writes the report to **`Download/AyundaRusdi Logs/`** (created
  automatically in the Android shared Download folder). The first save is
  `logs.txt`; every later save is `logs_YYYY-MM-DD_HHMMSS.txt` (a counter is
  added if two saves land in the same second). An existing file is **never
  overwritten**: the file is created exclusively, written, size-verified, and
  removed again if anything fails. The WebUI shows the saved path only after
  the file exists and is verified, otherwise `Failed to save logs:` plus the
  real reason. There is no Share button and no Web Share API use.

What the report contains: module name and version, Android release/API, device
model, root manager, backend (SurfaceFlinger, transaction 1022, availability),
verification (state consistent AND backend reachable), module state, preset,
value, System UI animation scales, counts of pinned presets and profiles,
auto-switching state, whether the listener received any foreground event,
the result of the last profile apply (without package names), a one-shot check
whether the ROM's events buffer contains the foreground event, and the **error
history**. Anything that cannot be read is written as `Unknown` or
`Not available`; nothing is guessed.

**Error history:** only failures this module detects itself are recorded
(a failed SurfaceFlinger apply with the real backend message, a state commit
failure, an unreadable/inconsistent state at boot, a profile apply/restore
failure, a System UI tweak failure). It is a small file
(`/data/adb/risu-color-enhancer/errors.log`) capped at the **last 20 entries**,
written only when a failure happens, never while idle. The report always says
`Crash cause: Not available from collected diagnostics`: the module receives no
crash reports, so it does not claim to know why anything crashed, and if the
WebUI itself dies before you press Save Logs nothing can be reconstructed.

Intentionally excluded: package names (profile counts only), file paths,
accounts, tokens, environment variables, the process list, and any Android
logcat dump. "Verification: PASS" does not read the live screen value
(SurfaceFlinger has no read-back).

Not verified on a device: that files written to
`/storage/emulated/0/Download` by the root shell are visible in your file
manager (they are written through the normal shared-storage path, not
`/data/media`).

## Preview scenes

Three bundled scenes (`scene1.jpg`, `scene2.jpg`, `scene3.jpg`) with a
before/after slider that applies CSS `saturate()` for the current value. It is
a visual aid only and never sends a backend command. Scene 1 is the supplied
reference artwork; Scenes 2 and 3 are the project's existing preview images.

## State and persistence

One file, `/data/adb/risu-color-enhancer/state.conf` (outside the module
directory, so it survives updates): `module_state`, `active_preset`,
`active_value`, `custom_value`. Writes go to a temp file, are renamed
atomically, then read back and compared. Writers take a `mkdir` lock
(stale locks from dead PIDs are reclaimed). The file is parsed as data, never
sourced. On boot `ModuleOn.sh` re-applies the saved preset only if the whole
state validates (including that `active_value` matches the preset's real
value); a corrupt state is never applied and self-heals to disabled/native.

- **Reset**: applies `1.00`, then persists `module_state=disabled`, no preset,
  `active_value=1.00`, `custom_value=1.00`, and restores System UI animation
  scales if this module changed them. Pinned presets and profiles are kept.
  Reports success only if verified.
- **Disable**: applies `1.00`, keeps the saved preset for re-enabling.
- **Failure handling**: a script prints `OK ...` and exits 0 only if the
  SurfaceFlinger reply was a clean Parcel result *and* state was committed and
  read back. The WebUI shows a success toast only on that; otherwise it shows
  the error and re-reads real state. If the state commit fails after the
  backend call, the previous backend value is restored.

## System UI Tweaks

`ui_tweaks.sh status | apply [scale] | reset`. First apply backs up the three
original values (including "unset") to `ui_tweaks.conf`; each write is read
back; any mismatch rolls all three back and reports the error. Reset (and
uninstall) restore the originals. No daemon, no loop, no boot hook — Android
persists these settings itself.

## WebUI

Tabs: **Home · Presets · Controls · About**. Controls holds Risu Custom (shown
when Custom is the active preset; applies on slider release), System UI
Tweaks, Per-App Profiles, and Diagnostics + Diagnostic Log (version from `module.prop`, state validity, backend
availability, root manager, Android/API, device model — only what is
detected). All state comes from one `status.sh` call after every action and on
focus. No frameworks, no CDN, no `innerHTML`.

## Install / uninstall

Flash the ZIP in Magisk, KernelSU or APatch. On Magisk the bundled KSU WebUI
APK is installed if missing. Uninstall restores native saturation and original
animation scales and removes the state directory.

## Tests

`tests/` (removed from the device at install): `test_backend.sh`,
`test_tweaks.sh`, `test_features.sh`, `webui_test.js`, `webui_v7_test.js`
(headless Chromium, real shipped webroot, `ksu.exec` bridged to the real
scripts with stub `service`/`settings`/`pm`), `test_package.sh`. Run `bash tests/run_all.sh`. Device-level behavior is not
covered; see `REPORT.md` for NOT TESTED items.

## Credits

Original: Kanagawa Yamada (LoggingNewMemory/AyundaRisuColorEnhancer).
Fork: KERVIII (github.com/KERVIII). Not affiliated with the original developer.
