# Ayunda Rusdi Color Enhancer — Risu Color Presets

Magisk / KernelSU / APatch root module. **v6.4** replaces only the bottom
navigation bar (a Kowsu-referenced floating pill with a single moving
liquid-glass lens) and adds an About page, on top of the unchanged v6.3
Huashu-ported Home/Presets/Custom/Status pages and the unchanged, hardened
v6.2 backend. See "Changelog" at the bottom for the full history.

## What this module actually does

This module controls exactly **one** real, verified Android parameter:

```
service call SurfaceFlinger 1022 f <value>
```

This is SurfaceFlinger's global saturation multiplier. `1.00` is native/
untouched saturation; values above `1.00` increase saturation, values below
`1.00` reduce it. It is applied compositor-wide, in real time, no reboot
required, and it is the *only* dynamically-adjustable color/display
mechanism present anywhere in this project's shell scripts, service, or
WebUI — there is no separate contrast, white-balance/color-temperature,
gamma, black-level, or HDR control implemented here.

Before every call, `service check SurfaceFlinger` confirms the service is
actually registered. This is a standard, read-only diagnostic subcommand —
not a new or unverified transaction — used purely to fail safely when the
backend isn't available.

## Risu Color Presets

| Preset       | Description (as shown in the UI)                          | Value | Aggressiveness |
|--------------|-------------------------------------------------------------|-------|-----------------|
| Risu Natural | Balanced colors with a clean, neutral look.                 | 1.05  | Low             |
| Risu Vivid   | Stronger saturation with punchier colors.                   | 1.55  | High            |
| Risu AMOLED  | Deep blacks with enhanced OLED contrast.                     | 1.40  | Medium-High     |
| Risu P3      | Wide-gamut tuning for richer color reproduction.             | 1.30  | Medium          |
| Risu Cinema  | Warm tones with a smooth cinematic look.                     | 1.12  | Low             |
| Risu Anime   | Bold colors with strong primary color separation.            | 1.75  | Very High       |
| Risu Game    | Higher contrast with clear and punchy colors.                | 1.50  | High            |
| Risu HDR     | Enhanced highlights and stronger shadow separation.          | 1.45  | Medium-High     |
| Risu Deep    | Deeper blacks with a stronger contrast profile.              | 1.25  | Medium          |
| Risu True    | Neutral tuning focused on natural color reproduction.        | 1.00  | None (native)   |
| Risu Paper   | Soft contrast with a comfortable reading-focused look.       | 0.90  | Reduced         |
| Risu Ice     | Cooler tones with a crisp, clean appearance.                 | 1.18  | Low-Medium      |
| Risu Ember   | Warm tones with richer reds and oranges.                     | 1.35  | Medium          |
| Risu Hyper   | Maximum color intensity with aggressive contrast.            | 2.20  | Maximum         |
| Risu Custom  | Fully adjustable color profile for your own tuning.          | 0.00–2.50 | User-set    |

### Important — read this before assuming a preset does more than saturation

Several preset descriptions above ("Deep blacks", "Wide-gamut", "Enhanced
highlights and shadow separation", "Higher contrast") describe display
characteristics that **cannot be independently controlled** with the
mechanism this module has access to. Every preset — including those — is a
real, distinct, working *saturation* profile calibrated to visually lean in
the direction its description suggests. None of them are:

- true DCI-P3 / wide-gamut activation,
- true HDR tone-mapping,
- independent OLED black-level control, or
- a separate contrast curve.

This is disclosed in the WebUI itself (directly under the preset grid), not
just here. If your device/ROM exposes additional verified SurfaceFlinger or
display HAL controls, they were not present or confirmed working in this
codebase, so they were intentionally **not** added — this module does not
write unverified system properties or invented transaction codes.

## State model

Every script sources `AyundaRisu/common.sh`, the single place that defines
paths, validation, preset lookup, state I/O, and the backend call.

State lives in **one file**, `state.conf`, not four separate files:

```
module_state=enabled
active_preset=risu_natural
active_value=1.05
custom_value=1.00
```

This is the v6.2 hardening fix: with four separate files, a process killed
mid-update could leave `active_preset` updated but `module_state` stale —
a real mixed-state hazard. With one file, `write_state()` builds the
complete new content in memory and commits it with a single `mv -f`
rename, so the state is either entirely the old version or entirely the
new one — never a mix. `commit_state()` additionally reads the file back
after writing and confirms it matches before any script reports success.

State is explicit, never inferred from a file's absence, and **internally
cross-validated**: `validate_state()` doesn't just check that
`active_value` is a well-formed number in range — it recomputes the
*canonical* value for `active_preset` from `presets.conf` (or from
`custom_value` for Risu Custom) and requires `active_value` to actually
equal it. A state file with `active_preset=risu_natural` but
`active_value=1.90` is individually well-formed but internally
inconsistent, and is rejected — this is stricter than v6.1, which only
checked each field in isolation.

**Module Off** → applies native (`1.0`) immediately, commits `module_state=disabled`
while *keeping* `active_preset`/`active_value`/`custom_value` unchanged.
**Reset** → applies native (`1.0`) immediately, commits a fully cleared
state (`disabled`, all other fields empty), then re-reads and explicitly
verifies the clear actually landed.
**Selecting any preset** → applies it, then commits `module_state=enabled`
with the new preset/value as one atomic unit. This is the only way to
re-enable after Off or Reset.
**Boot** (`ModuleOn.sh`, via `service.sh`) → applies the persisted value
*only if* the whole state passes `validate_state()` **and**
`module_state` is exactly `enabled`. Missing, corrupt, or internally
inconsistent state self-heals to a safe cleared/disabled state (so the
same corruption isn't re-evaluated every boot) and applies nothing.
`ModuleOn.sh`'s exit code reflects whether the backend call itself
succeeded — it no longer unconditionally exits `0`.

## Validation

One function, `validate_and_clamp()` in `common.sh`, is the only place that
accepts or rejects a saturation value. It requires an unsigned integer or
decimal matching `^[0-9]+(\.[0-9]+)?$` — this rejects empty input, `.`,
`..`, `1.2.3`, letters, signs, and anything else malformed — then clamps
the result to `0.00`–`2.50`. This same function is used for preset values,
custom values, and persisted values read at boot. There is no second,
looser validation path anywhere else.

## Apply order (fail-safe by design)

`apply_preset.sh` (and `reset.sh`/`ModuleOff.sh` analogously) follow this
order, and only this order:

1. Validate the preset id exists (exact match, no regex on user input)
2. Resolve the raw value (from `presets.conf`, or the custom argument)
3. Validate/clamp the final value
4. Confirm `SurfaceFlinger` is registered
5. Apply the value, check its real exit code
6. Only on confirmed success: `commit_state()` the complete new state as
   one atomic, verified unit
7. Report success (`OK <id> <value>`) or a specific error to stderr

If any step fails, **nothing is committed** — `state.conf` is left
byte-for-byte untouched, and the previous known-good state stays active on
disk and in the WebUI.

## WebUI

Rebuilt in v6.3 on a design system ported from a supplied Huashu WebUI
reference (a different, unrelated Magisk module's frontend): pure-black
canvas, paper-elevated cards, numbered section headers ("01 / 02 / 03"),
horizontal bar telemetry, technical monospace labels, a toast for success
feedback, and a modal confirm sheet for the one destructive action
(Reset). Recolored to the established Risu rose accent instead of the
reference's terracotta so it reads as its own product. This **superseded**
an earlier "AZenith-inspired" direction from v6.2 — that reference turned
out to ship a native Kotlin/Compose app with no WebUI source to study, so
v6.2's WebUI was built from generic conventions instead; v6.3 replaces it
entirely with the Huashu port described here.

The reference module's own backend (a `cgi-bin/api.sh` + battery/CPU/app
optimization feature set) was **not** ported — only its frontend
structure/visual language. Every element below still talks exclusively to
Ayunda's own hardened backend via `ksu.exec`; nothing here depends on that
reference module's config paths, CGI endpoints, or feature set.

- Fully offline: no CDN, no Google Fonts, no external JS/CSS. Display and
  monospace type use system font stacks (`-apple-system`/`Segoe UI`/
  `Roboto` and `ui-monospace`/`SF Mono`/`Roboto Mono`) rather than the
  reference's network-loaded fonts.
- Preset names/descriptions and all backend output are inserted via
  `textContent`/DOM creation, never `innerHTML`.
- `state.conf` is read as one file; a failed read (`errno != 0`, or an
  empty/unparseable result) is treated as a distinct **"Unable to read
  state"** condition — shown on the hero card, the header status dot, and
  the Status tab, never silently presented as "native" or "disabled". A
  persistent error card with an explicit **Retry** button follows the user
  to whichever tab they're on, for both initial-load and later-action
  failures. Errors use a persistent card rather than the toast, since a
  toast auto-dismisses and the module must not let a failure go unnoticed.
- Every backend call's `errno` is checked. On failure, the UI re-reads
  state from the backend (never trusts what it sent), keeps showing
  whatever that re-read confirms, and surfaces the actual `stderr` message.
  Success is confirmed with a toast; failure never is.
- `presets.conf` parsing is defensive independently of the shell-side
  validation: missing file, malformed rows, wrong field counts, duplicate
  ids, and out-of-range/non-numeric values are each skipped with a warning
  rather than crashing the preset list.
- Animations are CSS `transform`/`opacity`/`width` transitions only (no JS
  animation loops, no continuous polling); `prefers-reduced-motion: reduce`
  collapses all transition/animation durations to ~0 while preserving full
  functionality.
- Layout is fluid (`minmax()` grid, `env(safe-area-inset-*)`, no fixed
  pixel widths past mobile breakpoints) and was verified to produce zero
  horizontal overflow at 360/390/412/432px, on both the Home and Presets
  (widest content) tabs — see Testing below.
- No profile/avatar/banner system, theme picker, or font picker: the
  reference module has all three, but Ayunda has no equivalent feature for
  any of them, so per the porting brief they were left out entirely rather
  than shipped as unused UI.

## Persistence across upgrades

User state (`module_state`, `active_preset`, `active_value`, `custom_value`)
lives in `/data/adb/risu-color-enhancer/`, **outside** the module's own
directory. Magisk/KernelSU/APatch replace the module's payload
(`/data/adb/modules/AyundaRusdi/`) wholesale on every update — anything
stored inside it does not survive an upgrade. `customize.sh` initializes
this directory on first install, and never overwrites it if already
present, so upgrades and reinstalls preserve your selection.

If you're upgrading from a v6.0 install (which stored state inside the
module directory), `customize.sh` migrates it into the new location
automatically, once.

On a full module removal (not an upgrade), `uninstall.sh` removes
`/data/adb/risu-color-enhancer/` and restores native saturation.

## Compatibility

- Requires Magisk, KernelSU, or APatch with a working `service` binary and
  a SurfaceFlinger that honors transaction code `1022` (unchanged from the
  original module).
- If `service check SurfaceFlinger` reports the service isn't registered,
  every script fails safely: no call is attempted, no state is written,
  and a clear error is returned to the WebUI.
- No unrelated system components, daemons, or background services. No
  polling — the value is only (re)applied on boot, preset change, Module
  Off, or Reset.

## Installation

Flash the zip in Magisk/KernelSU/APatch Manager, reboot. On first install a
KSU WebUI companion app is installed automatically if not already present.
Open the module's WebUI action to pick a preset.

## Testing

Backend scripts are tested in a sandbox by placing the real shipped files
at their actual absolute paths (`/data/adb/modules/AyundaRusdi/AyundaRisu`,
`/data/adb/risu-color-enhancer`) with a stubbed `service`/`service check`
binary — not copies in a scratch directory. This covers all 15 presets
individually, malformed/edge-case input, reset/off/preset + reboot
persistence, SurfaceFlinger-unavailable and missing-binary paths, cross-
field state corruption, and migration from both prior layouts. It cannot
cover real on-device SurfaceFlinger behavior, the real `ksu.exec` bridge,
or SELinux/install-time behavior — those require actual hardware.

The WebUI is tested with headless Chromium (Playwright) loading the
**actual shipped** `index.html`/`app.js`/`style.css`, with only the
`ksu.exec` bridge and `fetch("/presets.conf")` mocked by a small
test-only script (never included in the flashable zip) that mirrors
`common.sh`'s exact validation/state logic. As of v6.3 this covers: tab
navigation across all four views, all 15 presets rendering and applying,
the "Native" quick action, Disable + re-enable-via-preset-selection,
the Reset confirm sheet (both Cancel and Confirm paths), toast feedback on
success, the persistent error card (not toast) on failure — including a
state-read failure that happens *after* an action rather than on initial
load, and that it follows the user across tab switches — Retry recovery,
zero horizontal overflow at 360/390/412/432px on both Home and the
preset-grid-heavy Presets tab, and `prefers-reduced-motion` support.
Screenshots were captured and visually inspected at each stage (hero card,
preset grid, custom slider, status table, confirm sheet), not just
DOM-asserted.

## Navigation

v6.4 replaced only the bottom nav (About added); v6.5 refined its
contrast/geometry and added swipe; v6.6 fixed real rendering/interaction
bugs found on an actual device that the prior passes' testing missed (see
Changelog). Home/Presets/Custom/Status page content itself is byte-for-
byte the v6.3 Huashu-ported UI throughout.

The floating navbar and its single moving "liquid-glass" lens are
referenced from KOWX712/KernelSU's `FloatingBottomBar.kt`/`Lens.kt`
(Apache-2.0) — a real AGSL runtime-shader pixel-refraction effect that has
no CSS/WebView equivalent. The starting geometry (64px pill / 56px row)
and the critically-damped zero-overshoot spring (`dampingRatio=1,
stiffness=1000`, approximated with a `cubic-bezier(.16,1,.3,1)` transform
transition) were matched from that source; current geometry is a 60px
pill with 58px items (298px total for 5 items), tuned across two rounds
of visual comparison against screenshots rather than assumed correct on
the first pass. One lens sized to a tab's width (not a small dot) is used
throughout — never per-item backgrounds. The lens is deliberately
CRISP rather than heavily blurred: a real 1.5px border defines its true
edge, `backdrop-filter` blur is kept to 3px, and shadow/glow radii stay
small enough to remain within the box — v6.6 fixed a real regression
where a wider glow + heavier blur with no strong border let the lens
dissolve into a shapeless halo on an actual device (not reproduced in
earlier desktop-viewport screenshots). The lens moves via `transform:
translate3d()` driven by a single CSS custom property (`--knav-idx`); the
bar's own width/position never changes when switching tabs. A
`@supports not (backdrop-filter: ...)` rule falls back to a plain dark
translucent bar if blur isn't supported, so navigation never breaks. Both
`body` and `#app` use `100dvh` (with a `100vh` fallback) rather than bare
`100vh`, since real mobile browsers resize the visible viewport as the
URL bar shows/hides — a likely contributor to a reported navbar/content
collision that didn't reproduce in desktop testing.

**Swipe**: Pointer Events on the navbar itself (per the brief's explicit
instruction — not a page-wide gesture), with progressive direction-lock
(10px) so a horizontal drag is confirmed before a 40px threshold triggers
navigation, ignores vertical-dominant drags so it never fights page
scroll, no wraparound at the first (Home) or last (About) tab, and drives
the exact same `switchTab()` function taps use rather than a parallel
navigation path. `setPointerCapture()` is applied only once a drag is
confirmed horizontal, never on a plain `pointerdown` — capturing
unconditionally was the v6.5 bug that silently broke ordinary taps (see
Changelog).

About (`Home → Presets → Custom → Status → About`) reuses the existing
page-head/numbered-section/card visual language — no new visual system,
one small `.about-card` class for prose. It has no backend behavior: it
doesn't call `apply_preset.sh`/`ModuleOff.sh`/`reset.sh`, so a state-read
failure elsewhere in the app still follows the user there (via the same
per-tab error-slot pattern as the other four tabs) but there's nothing on
the page itself that can fail.

## Before/After preview (v6.5)

A frontend-only visual demo on Home, using the module's own pre-existing
`webroot/bg1.4b3c90a5.jpg`/`bg2.98502a4b.jpg` (shipped since the original
v5.0 release, confirmed byte-identical via MD5, never recompressed). A
drag divider (Pointer Events, `clip-path` reveal, no continuous animation
loop) compares the unmodified image against the same image with
`filter: saturate(var(--preview-sat))` applied — `--preview-sat` is set
directly from `App.state.active_value` (or `1.00` when disabled), the
exact same state this file already reads for Home/Status. It does not
introduce a second color-control system and never calls the backend: only
`apply_preset.sh`/`ModuleOff.sh`/`reset.sh` count as mutating backend
calls, and scene-switching/dragging make zero of them. Carries the
required disclaimer verbatim: "Visual preview only. Actual display output
depends on your device, panel, ROM, and display pipeline."

## Changelog

**v6.7**
- **Navbar structurally redesigned**, not just retuned: replaced the
  translucent glass-lens approach (which kept rendering as an ill-defined
  blob across multiple fix attempts) with a solid, physical floating
  "bump" knob referenced from a Liquid Navigation demo - a raised circle
  that pops above the bar's top edge, containing the active tab's icon.
  Solid fill means there's no blur-edge-bleed failure mode to begin with.
  Geometry is exposed via CSS custom properties (`--nav-height`,
  `--nav-item-size`, `--nav-knob-size`, etc.) for easy tuning. Found and
  fixed a real bug during implementation: the icon wasn't rendering
  inside the knob at all (a guessed `translateY` offset trying to align
  two independently-positioned elements was simply wrong) - fixed by
  cloning the active tab's actual icon into the knob directly, verified
  visually via a zoomed screenshot before and after.
- **Fixed a real saturation-display bug**, traced end to end rather than
  patched at the display layer: the Custom slider's `step="0.05"` silently
  snapped any assigned value to the nearest step - confirmed with a direct
  browser test that `1.18` (Risu Ice's exact value) becomes `"1.2"`. That's
  the "1.20" the report described. Changed `step` to `0.01` (verified
  against every real preset value, all survive unchanged) and made the
  Custom page mirror the currently *active* saturation (matching Home/
  Status) instead of an independently-tracked "last custom value" that
  could silently disagree with what's actually applied - there is now
  exactly one source of truth, per the report's own requirement. Added a
  request-generation guard against any theoretical overlapping-action race
  as a second line of defense. Verified with the full reported number
  sequence (0.50 through 2.50) surviving input → apply → backend → display
  → tab-reload intact.
- Added a Ghost loader (original CSS in the spirit of BlackisPlay's
  MIT-licensed "Pac-Man Ghost Loader" on Uiverse.io - the complete source
  wasn't fully retrievable since the site's code viewer is client-
  rendered, so this reproduces its documented visual language rather than
  copying it verbatim): shown only on Presets/Custom/Status/About, never
  Home, and tied to real initialization completing (verified with an
  artificially slowed mock backend that the loader appears while waiting
  and disappears the instant readiness actually flips - not a fixed
  delay). Created once in the DOM, visibility-toggled only.
- Preset card accent color was already consistent (single `--accent-2`
  header on every card, verified by inspection - no change needed).
- Inspected the actual Zetamin V2 module (not invented): it's a separate
  module by the same original author that sets three frame-rate-related
  `resetprop`s via a compiled binary, and its own installer explicitly
  prints "DO NOT COMBINE WITH OTHER SCREEN TWEAKS." Given that, no new
  system tweaks were added under a "Zetamin compatibility" banner - added
  a factual note to About instead, stating Ayunda Rusdi's only system
  modification (the SurfaceFlinger saturation call) and Zetamin's own
  stated caution, so users can judge for themselves.
- Backend and non-navbar/non-Custom UI unchanged - reverified with 16
  backend regression tests, 17 real-touch swipe tests (expanded matrix:
  slow/fast/short/long swipes, diagonal rejection, swipe+tap combos,
  rapid swiping, vertical scroll unaffected), and 16 responsive-width
  tests, 0 failures.

**v6.6**
- Fixed a real bug the previous pass's automated tests didn't catch: the
  lens rendered as an edgeless glow/blob on real devices (confirmed from
  a user-provided on-device screenshot showing it bleeding across most of
  the bar and into content above). Root cause: an 18px ambient glow
  `box-shadow` plus 7px `backdrop-filter` blur with no strong border let
  the true 54×52px box dissolve into a shapeless halo. Fixed by adding a
  real 1.5px border, cutting the blur to 3px, removing the wide glow
  entirely, and keeping shadow/highlight radii small enough to stay
  within the box - the lens now reads as a bounded object, not a glow.
- Fixed swipe silently not working on real touch, found by testing with
  actual CDP touch-event dispatch on a real device profile instead of
  mouse-simulated drags (the gap the previous pass's testing had):
  `setPointerCapture()` was being called on every `pointerdown`, which
  retargets the eventual `pointerup` - and the browser's `click`
  synthesis with it - onto the navbar instead of the tapped button. This
  silently broke ordinary taps whenever the swipe listener was attached.
  Fixed by only capturing the pointer once a horizontal drag is
  *confirmed* (after a 10px direction-lock distance), never on a plain
  tap - verified with 16 real-touch tests via CDP `Input.dispatchTouchEvent`
  covering the full 8-swipe sequence, no-wraparound at both ends, vertical-
  gesture rejection, tiny-jitter rejection, rapid swiping, and that normal
  taps still work afterward.
- Fixed real mobile browsers computing `100vh` against a taller viewport
  than what's actually visible (the classic URL-bar-collapse issue) by
  switching to `100dvh` with a `100vh` fallback - a likely contributor to
  the reported Quick-Actions/navbar collision on an actual phone that
  didn't reproduce in desktop-viewport testing.
- Widened nav items 54px→58px for less cramped icon/label spacing, raised
  inactive icon/label opacity 0.68→0.82 for legibility, slightly reduced
  lens corner radius (18px→15px) so it reads less circular/more like a
  bounded glass pane.
- Backend, and every other page, unchanged - reverified with 16 backend
  regression tests and 74 WebUI tests (58 from before + 16 new real-touch
  tests), 0 failures.

**v6.5**
- Navbar refinement pass: narrower item width (60px→54px, 5 items now
  278px total vs. 308px before), stronger bar opacity/contrast (0.88→0.95
  alpha, blur 18px→14px) so it reads as a solid glass object instead of
  blending into page content, refined lens depth (inner rim, stronger
  specular highlight, tighter chromatic edge), and confirmed via measured
  bounding boxes (not assumption) that Quick Actions never overlaps the
  floating bar at any of the 4 required widths.
- Added swipe gesture detection on the navbar itself (Pointer Events,
  40px threshold, no wraparound at the first/last tab, ignores
  vertical-dominant drags) — reuses the exact same `switchTab()` used by
  taps, not a separate navigation system.
- Updated About page copy to the latest provided wording (Fork &
  Maintenance, Credits, and a new dedicated Updates section).
- Added an interactive Before/After color-preview to Home: a
  drag-divider comparison using the project's own pre-existing `bg1`/
  `bg2` webroot images (verified byte-identical to the original v5.0
  release via MD5, not re-encoded), with two selectable scenes. The
  "after" side applies `filter: saturate()` driven by the same
  `App.state.active_value` already used elsewhere in this file — it is
  purely a frontend CSS visualization and never calls
  `apply_preset.sh`/`ModuleOff.sh`/`reset.sh` (re-verified by counting
  mock backend calls before/after interacting with it: zero). Carries
  the required disclaimer verbatim.
- The module-manager banner requirement was already satisfied by the
  original project's own `banner=Banner.png` (in `module.prop` since
  v5.0) — confirmed intact, no change needed.
- Backend, and all of Home/Presets/Custom/Status/About beyond the above,
  unchanged — reverified with 16 backend regression tests and 58 WebUI
  tests (0 failures) after this pass.

**v6.4**
- Replaced only the bottom navigation with a Kowsu-referenced floating
  pill navbar with a single moving liquid-glass lens (see "Navigation"
  above for the full technical breakdown and what was/wasn't reproducible
  in CSS vs. the reference's actual AGSL shader).
- Added an About page/tab, reusing the existing visual system.
- Home/Presets/Custom/Status pages, and the entire backend, are unchanged
  from v6.3/v6.2 — reverified with 16 backend regression tests (0
  failures) and 45 WebUI tests covering the new nav specifically (0
  failures) after this pass.
- Fixed during testing: the floating pill's own glass was initially too
  transparent (page content read clearly through the flat areas, not just
  the lens); increased its opacity/reduced blur and boosted the lens's own
  contrast so the lens reads as the one distinct glass object, per
  screenshot inspection rather than DOM assertions alone.

**v6.3**
- WebUI rebuilt on a Huashu-ported design system (see "WebUI" above for
  the full breakdown). Backend untouched — re-verified with the full
  v6.2 test suite (33 tests) after the frontend rebuild, 0 failures.
- Reset now uses a modal confirm sheet instead of the browser's native
  `confirm()`, styled consistently with the rest of the UI.
- Added a "Native" quick action (applies the existing `risu_true` preset —
  no new backend behavior, just a shortcut to a preset that already
  existed).
- Cancelled the v6.2 "AZenith-inspired" WebUI direction entirely per this
  pass's explicit instruction; see "WebUI" above for why v6.2 ended up not
  actually resembling AZenith in the first place.

**v6.2**
- Hardened: state is now a single atomically-committed file (`state.conf`)
  instead of four separate files, eliminating the possibility of a
  partial update leaving mismatched fields.
- Hardened: boot validation now cross-checks that `active_value` actually
  corresponds to `active_preset` (not just that each field is individually
  well-formed), and self-heals to a safe disabled state on any
  inconsistency instead of applying an unverified value.
- Fixed: `ModuleOn.sh` no longer unconditionally exits `0` — its exit code
  now reflects whether the backend call actually succeeded.
- Redesigned: new original WebUI (Home/Presets/Custom/Status tabs,
  bottom nav, transform-based animations, `prefers-reduced-motion`
  support). Fixed a gap where a state-read failure occurring after an
  action (rather than on initial load) updated the inline dashboard but
  didn't surface the persistent error banner + Retry control.
- Migration: v6.1's four-file state and v6.0's in-payload state both
  migrate automatically into the new single-file format on upgrade.

**v6.1**
- Fixed: Reset followed by reboot could silently reapply Risu Natural
  instead of staying native (missing explicit enabled/disabled state).
- Fixed: saturation validation accepted malformed values like `1.2.3`.
- Fixed: state was persisted *before* confirming the backend call
  succeeded; now persistence only happens after a confirmed success.
- Fixed: user state was stored inside the module payload and would not
  have survived a module upgrade; moved to `/data/adb/risu-color-enhancer/`
  with automatic one-time migration from a v6.0 install.
- Fixed: WebUI silently assumed every backend command succeeded; now checks
  `errno` and surfaces real errors without losing the previous state.
- Removed the external Tailwind CDN dependency; WebUI now fully offline.
- Replaced `innerHTML` usage with `textContent`/DOM creation for all
  data-derived UI content.
- Stale "Version : 5.0" installer text corrected.

**v6.0**
- Introduced Risu Color Presets (15 presets + Risu Custom).
