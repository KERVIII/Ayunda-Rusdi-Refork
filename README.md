# Ayunda Rusdi Color Enhancer

Android display color enhancement module with a WebUI for saturation
control, color presets, diagnostics, and optional animation settings.

Ayunda Rusdi is an independent fork and continued development of the
original project by **Kanagawa Yamada**.

## Features

-   Adjustable display saturation
-   18 built-in color presets
-   Custom saturation control
-   Persistent preset and saturation state
-   Reset and restore handling
-   Backend error handling
-   Input validation
-   Diagnostic reports
-   Favorite Risu display
-   Optional per-app color profiles
-   Optional system animation controls
-   KernelSU WebUI support

## Color Presets

Ayunda Rusdi currently includes 18 presets.

1.  Risu True
2.  Risu Paper
3.  Risu Natural
4.  Risu Cinema
5.  Risu Ice
6.  Risu Deep
7.  Risu P3
8.  Risu Ember
9.  Risu AMOLED
10. Risu HDR
11. Risu Game
12. Risu Vivid
13. Risu Anime
14. Risu Hyper
15. Risu Custom
16. Risu Muted
17. Risu Comic
18. Risu OLED

Presets change the saturation value used by the display backend. Names
such as HDR, P3, AMOLED, and OLED describe the intended visual profile.
They do not activate hardware HDR, a physical P3 color space, panel
calibration, or vendor-specific display modes.

## Display Backend

Ayunda Rusdi uses the Android SurfaceFlinger saturation interface:

``` text
service call SurfaceFlinger 1022 f <value>
```

The backend controls the display saturation multiplier.

The module does not add unsupported SurfaceFlinger transactions or claim
access to display controls that Android does not expose through the
supported interface.

The supported saturation range is:

``` text
0.00 - 2.50
```

The default value is:

``` text
1.00
```

## Preset Details

### Risu Muted

-   Reduced saturation
-   Less aggressive color output

### Risu Comic

-   Higher saturation
-   Stronger primary colors

### Risu OLED

-   Higher saturation
-   Stronger color separation

These profiles still use the same SurfaceFlinger saturation backend.

## Custom Saturation

The Custom preset allows a user-defined saturation value within the
supported range.

-   Minimum: `0.00`
-   Maximum: `2.50`
-   Default: `1.00`

Invalid values are rejected before they reach the backend.

## Per-App Profiles

Ayunda Rusdi supports optional per-app saturation profiles.

A profile associates an Android package with a saturation value. When
supported foreground activity detection identifies the configured
application, the module applies the corresponding value.

Per-app profiles do not replace the saved global preset.

Foreground detection depends on the Android ROM and available system
interfaces. Behavior can differ between devices.

## System Animation Controls

Ayunda Rusdi includes optional controls for Android system animation
scales.

The module handles:

``` text
window_animation_scale
transition_animation_scale
animator_duration_scale
```

Existing values are backed up before changes are applied.

Reset restores the stored values when a valid backup exists.

These settings are separate from display saturation.

## State Management

Module state is stored outside the module directory:

``` text
/data/adb/risu-color-enhancer/
```

The state includes:

-   Module state
-   Active preset
-   Active saturation value
-   Custom saturation value
-   Per-app profiles
-   Animation settings

State writes use temporary files and replacement to reduce the risk of
partial configuration writes.

The module validates stored values before applying them.

## Diagnostics

The WebUI includes diagnostic information for:

-   Module state
-   Active preset
-   Active saturation
-   Backend availability
-   Backend command results
-   Configuration state
-   Error history

Diagnostics do not claim hardware-level display information unavailable
through the Android interface.

## WebUI

The module provides a WebUI for:

-   Preset selection
-   Custom saturation
-   Per-app profiles
-   Animation settings
-   Reset controls
-   Diagnostics
-   Module information

The interface is designed for KernelSU WebUI environments.

## Requirements

-   Android device with root access
-   KernelSU or a compatible root environment
-   SurfaceFlinger saturation interface
-   Android version and ROM support for the selected features

Some optional features depend on ROM-specific behavior.

## Installation

1.  Download the release ZIP.
2.  Open your root manager.
3.  Install the module ZIP.
4.  Reboot if required by your root environment.
5.  Open the Ayunda Rusdi WebUI.
6.  Select a preset or set a custom saturation value.

## Reset

Use the Reset option from the WebUI to return the display saturation to
the default value:

``` text
1.00
```

Animation settings are handled separately and restore their backed-up
values when available.

## Limitations

Ayunda Rusdi does not provide:

-   Hardware panel calibration
-   True HDR activation
-   DCI-P3 hardware mode switching
-   Vendor-specific color engine controls
-   RGB channel calibration
-   Gamma calibration
-   Hardware black-level control
-   Hardware white-balance control
-   Guaranteed compatibility with every Android ROM

The available display control depends on the Android SurfaceFlinger
implementation on the device.

## Credits

**Original Developer:** Kanagawa Yamada

**Fork & Maintenance:** KERVIII

Ayunda Rusdi is an independent fork and is not affiliated with the
original developer.

## License

See the repository license file for licensing information.
