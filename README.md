# Ayunda Rusdi Color Enhancer

Android display color enhancement module with a WebUI for saturation control, color presets, preview tools, diagnostics, and optional system animation adjustments.

Ayunda Rusdi is an independent fork and continued development of the original project by **Kanagawa Yamada**.

---

## Features

### Display Color Enhancement

- Adjustable display saturation
- Preset-based saturation control
- Custom saturation value
- Persistent module state
- Preset and saturation synchronization
- Reset and restore handling
- Backend error handling
- Input validation
- Pin Favorite Ruri's Smile
- Share Diagnostic a (report issue)

### Color Presets

Ayunda Rusdi currently provides **18 color presets**:

1. Risu True
2. Risu Paper
3. Risu Natural
4. Risu Cinema
5. Risu Ice
6. Risu Deep
7. Risu P3
8. Risu Ember
9. Risu AMOLED
10. Risu HDR
11. Risu Game
12. Risu Vivid
13. Risu Anime
14. Risu Hyper
15. Risu Custom
16. Risu Muted
17. Risu Comic
18. Risu OLED

### Additional Presets

**Risu Muted**
- Reduced saturation
- Less aggressive color output

**Risu Comic**
- Higher saturation
- Stronger primary colors

**Risu OLED**
- Higher saturation
- Stronger color separation

---

## Display Backend

Ayunda Rusdi uses the verified Android SurfaceFlinger saturation interface:

```text
service call SurfaceFlinger 1022 f <value>
```

The implemented backend controls the display saturation multiplier.

The project does not claim unsupported display controls or unverified SurfaceFlinger transactions.

---

## Credits

**Original Developer:** Kanagawa Yamada - for his majestic work.  
**Fork & Maintenance:** KERVIII
