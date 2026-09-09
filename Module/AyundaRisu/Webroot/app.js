// Ayunda Rusdi Color Enhancer - WebUI
//
// BACKEND INTERFACE (do not touch without touching AyundaRisu/common.sh
// too): state is a single file, /data/adb/risu-color-enhancer/state.conf
// (module_state / active_preset / active_value / custom_value), applied
// through the existing validated scripts. This file only decides how to
// PRESENT that - it is never the source of truth.
//
// PRESENTATION (safe to restyle freely): rendering, tabs, toast, confirm
// dialog - all below the "RENDERING" marker.

const MODDIR = "/data/adb/modules/AyundaRusdi/AyundaRisu";
const STATEDIR = "/data/adb/risu-color-enhancer";
const MODULE_VERSION = "6.3";
let callbackId = 0;

function executeCommand(cmd, opts = {}) {
    return new Promise((resolve) => {
        const cbName = `exec_callback_${Date.now()}_${callbackId++}`;
        window[cbName] = (errno, stdout, stderr) => {
            resolve({ errno, stdout: stdout || "", stderr: stderr || "" });
            delete window[cbName];
        };
        try {
            ksu.exec(cmd, JSON.stringify(opts), cbName);
        } catch (e) {
            delete window[cbName];
            resolve({ errno: -1, stdout: "", stderr: "ksu bridge unavailable" });
        }
    });
}

// Defensive presets.conf parsing: missing file, malformed rows, wrong
// field counts, duplicate ids, and invalid values are each skipped with a
// warning rather than crashing the preset list.
function parsePresets(text) {
    const presets = [];
    const seen = new Set();
    const warnings = [];

    text.split("\n").forEach((rawLine, i) => {
        const line = rawLine.trim();
        if (!line || line.startsWith("#")) return;
        const fields = line.split("|");
        if (fields.length !== 4) {
            warnings.push(`row ${i + 1}: expected 4 fields, got ${fields.length}`);
            return;
        }
        const [id, name, description, value] = fields;
        if (!id || !name || !description || !value) {
            warnings.push(`row ${i + 1}: missing field(s) for "${id || "?"}"`);
            return;
        }
        if (seen.has(id)) {
            warnings.push(`row ${i + 1}: duplicate id "${id}" ignored`);
            return;
        }
        if (value !== "custom" && (!/^[0-9]+(\.[0-9]+)?$/.test(value) || +value < 0 || +value > 2.5)) {
            warnings.push(`row ${i + 1}: invalid value for "${id}"`);
            return;
        }
        seen.add(id);
        presets.push({ id, name, description, value });
    });

    return { presets, warnings };
}

async function loadPresets() {
    let res;
    try {
        res = await fetch("/presets.conf");
    } catch (e) {
        return { presets: [], warnings: ["network/fetch error"], ok: false };
    }
    if (!res.ok) return { presets: [], warnings: [`HTTP ${res.status}`], ok: false };
    const text = await res.text();
    const { presets, warnings } = parsePresets(text);
    return { presets, warnings, ok: presets.length > 0 };
}

function parseStateText(text) {
    const state = { module_state: "", active_preset: "", active_value: "", custom_value: "" };
    text.split("\n").forEach((line) => {
        const idx = line.indexOf("=");
        if (idx === -1) return;
        const key = line.slice(0, idx).trim();
        const val = line.slice(idx + 1).trim();
        if (key in state) state[key] = val;
    });
    return state;
}

async function readState() {
    const res = await executeCommand(`cat ${STATEDIR}/state.conf 2>&1`);
    if (res.errno !== 0) {
        return { ok: false, error: res.stderr.trim() || `Unable to read module state (errno ${res.errno}).` };
    }
    const parsed = parseStateText(res.stdout);
    if (!parsed.module_state) {
        return { ok: false, error: "Module state file is empty or unreadable." };
    }
    return { ok: true, state: parsed };
}

// ═══════════════════════════════ RENDERING ═══════════════════════════════

const App = {
    presets: [],
    state: null,
    stateReadOk: false,
    stateReadError: "",
    activeTab: "home",
    error: null, // { message, retry, onRetry } | null - follows the active tab
    appReady: false, // true once the initial presets.conf fetch + state read both resolve
};

function $(id) { return document.getElementById(id); }
function fmt(val) {
    const n = parseFloat(val);
    return isNaN(n) ? "-" : n.toFixed(2);
}
function findPreset(id) { return App.presets.find((p) => p.id === id); }

// --- Error card: persistent (not a toast) - built via DOM creation only.
function buildErrorCard() {
    const card = document.createElement("div");
    card.className = "error-card";
    const msg = document.createElement("div");
    msg.className = "msg";
    msg.textContent = App.error.message;
    card.appendChild(msg);

    if (App.error.retry) {
        const row = document.createElement("div");
        row.className = "row";
        const retryBtn = document.createElement("button");
        retryBtn.type = "button";
        retryBtn.textContent = "Retry";
        retryBtn.addEventListener("click", async () => {
            const fn = App.error.onRetry;
            App.error = null;
            renderAll();
            if (fn) await fn();
        });
        const dismissBtn = document.createElement("button");
        dismissBtn.type = "button";
        dismissBtn.textContent = "Dismiss";
        dismissBtn.addEventListener("click", () => {
            App.error = null;
            renderAll();
        });
        row.appendChild(retryBtn);
        row.appendChild(dismissBtn);
        card.appendChild(row);
    }
    return card;
}

function renderErrorSlots() {
    ["homeErrorSlot", "presetsErrorSlot", "customErrorSlot", "statusErrorSlot", "aboutErrorSlot"].forEach((id) => {
        const slot = $(id);
        if (slot) slot.textContent = "";
    });
    if (!App.error) return;
    // Shown in whichever tab is currently active, so it's visible wherever
    // the user navigates without needing five independent error states.
    const slotId = { home: "homeErrorSlot", presets: "presetsErrorSlot", custom: "customErrorSlot", status: "statusErrorSlot", about: "aboutErrorSlot" }[App.activeTab];
    const slot = $(slotId);
    if (slot) slot.appendChild(buildErrorCard());
}

function setError(message, opts = {}) {
    App.error = { message, retry: !!opts.retry, onRetry: opts.onRetry || null };
}
function clearError() {
    App.error = null;
}

function renderStatusPill() {
    const dot = $("statusDot");
    const text = $("statusPillText");
    dot.className = "dot";
    if (!App.stateReadOk) {
        dot.classList.add("error");
        text.textContent = "Error";
        return;
    }
    if (App.state.module_state === "enabled") {
        dot.classList.add("on");
        text.textContent = "Enabled";
    } else {
        dot.classList.add("off");
        text.textContent = "Disabled";
    }
}

function renderHome() {
    const heroDot = $("heroDot");
    heroDot.className = "dot";

    if (!App.stateReadOk) {
        $("heroPresetName").textContent = "Unable to read state";
        $("heroPresetDesc").textContent = App.stateReadError;
        $("heroStateWord").textContent = "unknown";
        heroDot.classList.add("error");
        $("statSatQuick").textContent = "-";
        $("statStateQuick").textContent = "Error";
        $("homeMeterValue").textContent = "-";
        $("homeMeterFill").style.width = "0%";
        renderPreview();
        return;
    }

    const { module_state, active_preset, active_value } = App.state;
    const meta = findPreset(active_preset);
    const enabled = module_state === "enabled";

    $("heroPresetName").textContent = enabled ? (meta ? meta.name : active_preset || "Unknown preset") : "Native";
    $("heroPresetDesc").textContent = enabled ? (meta ? meta.description : "") : "No enhancement is currently applied.";
    $("heroStateWord").textContent = enabled ? "enabled" : "disabled";
    heroDot.classList.add(enabled ? "on" : "off");

    const shownValue = enabled ? active_value : "1.00";
    $("statSatQuick").textContent = fmt(shownValue);
    $("statStateQuick").textContent = enabled ? "Enabled" : "Disabled";
    $("homeMeterValue").textContent = `${fmt(shownValue)} / 2.50`;
    const frac = Math.max(0, Math.min(1, parseFloat(shownValue) / 2.5));
    $("homeMeterFill").style.width = `${isNaN(frac) ? 0 : frac * 100}%`;

    renderPreview();
}

// ═══════════════════════ BEFORE/AFTER PREVIEW ═══════════════════════════
// Frontend-only visual demo. Reuses the SAME App.state this file already
// reads for the Home/Status pages - it does not call apply_preset.sh,
// ModuleOff.sh, or reset.sh, and never issues a SurfaceFlinger command.
// The "after" side is a CSS saturate() filter on the same source image
// used for "before"; nothing here is a claim about actual panel output.

const PREVIEW_IMAGES = ["/bg1.4b3c90a5.jpg", "/bg2.98502a4b.jpg"];
let previewScene = 0;

function currentPreviewSaturation() {
    if (!App.stateReadOk) return 1.0;
    const enabled = App.state.module_state === "enabled";
    const v = parseFloat(enabled ? App.state.active_value : "1.00");
    return isNaN(v) ? 1.0 : v;
}

function renderPreview() {
    const before = $("previewImgBefore");
    const after = $("previewImgAfter");
    if (!before || !after) return; // Home not yet in DOM at first call - defensive only

    const src = PREVIEW_IMAGES[previewScene];
    if (!before.src.endsWith(src)) before.src = src;
    if (!after.src.endsWith(src)) after.src = src;

    const sat = currentPreviewSaturation();
    $("previewAfterWrap").style.setProperty("--preview-sat", sat);
    $("previewSatLabel").textContent = sat.toFixed(2);
}

function setupPreviewInteraction() {
    const compare = $("previewCompare");
    if (!compare) return;

    function setPositionFromClientX(clientX) {
        const rect = compare.getBoundingClientRect();
        const pct = Math.max(0, Math.min(100, ((clientX - rect.left) / rect.width) * 100));
        compare.style.setProperty("--preview-pos", `${pct}%`);
    }

    let dragging = false;
    compare.addEventListener("pointerdown", (e) => {
        dragging = true;
        compare.setPointerCapture(e.pointerId);
        setPositionFromClientX(e.clientX);
    });
    compare.addEventListener("pointermove", (e) => {
        if (!dragging) return;
        setPositionFromClientX(e.clientX);
    });
    const stop = () => { dragging = false; };
    compare.addEventListener("pointerup", stop);
    compare.addEventListener("pointercancel", stop);

    document.querySelectorAll(".preview-scene-btn").forEach((btn, i) => {
        btn.addEventListener("click", () => {
            previewScene = i;
            document.querySelectorAll(".preview-scene-btn").forEach((b, j) => b.classList.toggle("active", j === i));
            renderPreview();
        });
    });
}

function buildPresetCard(preset, isActive) {
    const card = document.createElement("button");
    card.type = "button";
    card.className = "pcard" + (isActive ? " active" : "");
    card.dataset.id = preset.id;

    const head = document.createElement("div");
    head.className = "pcard-head";
    const valSpan = document.createElement("span");
    valSpan.textContent = preset.value === "custom" ? "SET" : fmt(preset.value);
    const ck = document.createElement("span");
    ck.className = "ck";
    ck.textContent = "\u2713";
    head.appendChild(valSpan);
    head.appendChild(ck);

    const body = document.createElement("div");
    body.className = "pcard-body";
    const nameEl = document.createElement("div");
    nameEl.className = "pcard-name";
    nameEl.textContent = preset.name;
    const descEl = document.createElement("div");
    descEl.className = "pcard-desc";
    descEl.textContent = preset.description;
    body.appendChild(nameEl);
    body.appendChild(descEl);

    card.appendChild(head);
    card.appendChild(body);
    card.addEventListener("click", () => onPresetSelected(preset));
    return card;
}

function renderPresets() {
    const grid = $("presetGrid");
    grid.textContent = "";
    const activeId = App.stateReadOk && App.state.module_state === "enabled" ? App.state.active_preset : "";
    for (const p of App.presets) grid.appendChild(buildPresetCard(p, p.id === activeId));
    $("presetsCount").textContent = `${App.presets.length} Profiles`;
}

function renderCustom() {
    if (!App.stateReadOk) return;
    const slider = $("customSlider");
    const display = $("customValueDisplay");
    // Single source of truth: the slider mirrors the CURRENTLY ACTIVE
    // saturation (same number shown on Home/Status), not an independently
    // tracked "last custom value" - selecting any preset and then opening
    // Custom must show that preset's real number, never something stale
    // or unrelated. Falls back to the last custom value (then 1.00) only
    // when the module is disabled and there's no active value to mirror.
    const enabled = App.state.module_state === "enabled";
    const raw = enabled ? App.state.active_value : App.state.custom_value;
    const cv = parseFloat(raw);
    const v = isNaN(cv) ? 1.0 : cv;
    slider.value = v;
    // Belt-and-suspenders: a range input's step attribute can silently
    // coerce an assigned .value to the nearest step (this was the actual
    // cause of a real reported bug - Risu Ice's 1.18 got silently snapped
    // to 1.20 by a step="0.05" slider, and stayed wrong if the slider was
    // touched afterward). step is now 0.01 (matches every real value in
    // presets.conf exactly, verified), but the label is read back from
    // the slider's own resulting value rather than the pre-assignment
    // variable, so the two can never visually disagree even in an
    // unexpected edge case.
    display.textContent = parseFloat(slider.value).toFixed(2);
}

function renderStatus() {
    $("statVersion").textContent = MODULE_VERSION;
    if (!App.stateReadOk) {
        $("statState").textContent = "-";
        $("statPreset").textContent = "-";
        $("statSaturation").textContent = "-";
        $("statRead").textContent = "FAILED";
        return;
    }
    const enabled = App.state.module_state === "enabled";
    const meta = findPreset(App.state.active_preset);
    $("statState").textContent = enabled ? "Enabled" : "Disabled";
    $("statPreset").textContent = enabled ? (meta ? meta.name : App.state.active_preset || "-") : (App.state.active_preset ? `${App.state.active_preset} (off)` : "-");
    $("statSaturation").textContent = enabled ? fmt(App.state.active_value) : "1.00 (native)";
    $("statRead").textContent = "OK";
}

function renderAll() {
    renderStatusPill();
    renderHome();
    renderPresets();
    renderCustom();
    renderStatus();
    renderErrorSlots();
}

// --- Ghost loader: created once in HTML, visibility toggled only. Shown
// only while genuinely waiting on real app initialization (the initial
// presets.conf fetch + state read) - never a fixed decorative delay, and
// never on Home. -------------------------------------------------------
function showGhostIfWaiting(tab) {
    const ghost = $("ghost-loader");
    if (tab === "home" || App.appReady) {
        ghost.classList.remove("visible");
        return;
    }
    ghost.classList.add("visible");
}

function hideGhost() {
    $("ghost-loader").classList.remove("visible");
}

// --- Tab navigation -------------------------------------------------
const TAB_ORDER = ["home", "presets", "custom", "status", "about"];

function switchTab(tab) {
    App.activeTab = tab;
    document.querySelectorAll(".tab-content").forEach((el) => el.classList.toggle("active", el.id === `tab-${tab}`));
    document.querySelectorAll(".knav-item").forEach((el) => el.classList.toggle("active", el.dataset.tab === tab));
    const idx = TAB_ORDER.indexOf(tab);
    if (idx !== -1) $("knavKnob").style.setProperty("--knav-idx", idx);

    // The knob shows its own copy of the active tab's icon (cloned from
    // the real button's SVG, so there's exactly one source of truth for
    // what each icon looks like) rather than trying to visually align the
    // original in-flow icon with a separately-positioned element.
    const activeBtn = document.querySelector(`.knav-item[data-tab="${tab}"]`);
    const knobIcon = $("knavKnobIcon");
    if (activeBtn && knobIcon) {
        const svg = activeBtn.querySelector("svg");
        knobIcon.textContent = "";
        if (svg) knobIcon.appendChild(svg.cloneNode(true));
    }

    showGhostIfWaiting(tab);
    renderErrorSlots();
}

// --- Swipe gesture on the navbar itself (per spec: detect on the navbar,
// not the page). Pointer Events cover touch + mouse + pen uniformly.
// setPointerCapture is the critical piece for real touchscreens: without
// it, a drag that moves the finger outside the (small, ~60px-tall) bar's
// bounds - trivially easy during any deliberate horizontal swipe - can
// fail to deliver pointerup back to this element at all, silently
// breaking the gesture even though it looks fine under mouse-simulated
// testing (which doesn't exhibit this failure mode). No wraparound at the
// first/last tab. Direction is locked progressively during the drag (not
// only at release) so a confirmed-horizontal gesture can also suppress
// the browser's own touch handling for the rest of that drag. ----------
function setupNavSwipe() {
    const nav = $("bottom-nav");
    const SWIPE_THRESHOLD = 40; // px - deliberate horizontal drags only
    const DIRECTION_LOCK_DISTANCE = 10; // px - enough movement to classify intent
    let startX = 0, startY = 0, startPointerId = null, dx = 0, tracking = false, horizontalLock = null, captured = false;

    function reset() {
        tracking = false;
        horizontalLock = null;
        captured = false;
        dx = 0;
    }

    nav.addEventListener("pointerdown", (e) => {
        tracking = true;
        horizontalLock = null;
        captured = false;
        startX = e.clientX;
        startY = e.clientY;
        startPointerId = e.pointerId;
        dx = 0;
        // Deliberately NOT calling setPointerCapture here: capturing on
        // every pointerdown retargets the eventual pointerup (and the
        // browser's click synthesis with it) onto `nav` instead of the
        // actual tapped button, which silently breaks ordinary taps. We
        // only capture once a real horizontal drag is confirmed, below.
    });

    nav.addEventListener("pointermove", (e) => {
        if (!tracking) return;
        dx = e.clientX - startX;
        const dy = e.clientY - startY;

        if (horizontalLock === null && (Math.abs(dx) > DIRECTION_LOCK_DISTANCE || Math.abs(dy) > DIRECTION_LOCK_DISTANCE)) {
            horizontalLock = Math.abs(dx) > Math.abs(dy);
        }
        if (horizontalLock && !captured) {
            // Now that this is confirmed to be a horizontal drag (not a
            // tap, not a vertical scroll attempt), capture the pointer so
            // the eventual pointerup is reliably delivered back to `nav`
            // even if the finger has moved outside its small bounds -
            // and suppress any further native handling of the gesture.
            try { nav.setPointerCapture(startPointerId); } catch (err) { /* best-effort on older WebViews */ }
            captured = true;
        }
        if (horizontalLock) {
            e.preventDefault();
        }
    });

    function finish(e) {
        if (!tracking) return;
        const wasHorizontal = horizontalLock === true;
        const finalDx = e ? e.clientX - startX : dx;
        reset();
        if (!wasHorizontal) return;
        if (Math.abs(finalDx) < SWIPE_THRESHOLD) return; // too small - a tap, not a swipe

        const idx = TAB_ORDER.indexOf(App.activeTab);
        if (idx === -1) return;
        if (finalDx < 0 && idx < TAB_ORDER.length - 1) {
            switchTab(TAB_ORDER[idx + 1]); // swipe left -> next tab
        } else if (finalDx > 0 && idx > 0) {
            switchTab(TAB_ORDER[idx - 1]); // swipe right -> previous tab
        }
        // at the first/last tab, out-of-range swipes are simply no-ops -
        // no wraparound, per spec (no reference evidence of wrapping).
    }

    nav.addEventListener("pointerup", finish);
    nav.addEventListener("pointercancel", reset);
}

// --- Toast (success feedback only) -----------------------------------
let toastTimer;
function toast(msg) {
    const el = $("toast");
    el.textContent = msg;
    el.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove("show"), 2200);
}

// --- Confirm dialog (Reset only - the one destructive action) --------
let confirmFn = null;
function confirmDialog(title, desc, fn) {
    $("confirm-title").textContent = title;
    $("confirm-desc").textContent = desc;
    confirmFn = fn;
    $("confirm-overlay").classList.add("show");
}
function confirmYes() {
    $("confirm-overlay").classList.remove("show");
    const fn = confirmFn;
    confirmFn = null;
    if (fn) fn();
}
function confirmNo() {
    $("confirm-overlay").classList.remove("show");
    confirmFn = null;
}

// --- Actions: always re-read state from the backend after success,
// never optimistically trust what we sent. ------------------------------
function setBusy(busy) {
    document.querySelectorAll("button").forEach((b) => (b.disabled = busy));
}

// Request-generation guard: setBusy(true) already prevents a second
// button click from starting a new action while one is pending, but this
// adds a second, independent layer - if two refreshFromBackend() calls
// somehow end up in flight at once, only the result of the LATEST one is
// allowed to update the UI. A stale response finishing after a newer one
// can never overwrite it with an outdated value.
let stateReadGeneration = 0;

async function refreshFromBackend() {
    const myGeneration = ++stateReadGeneration;
    const result = await readState();
    if (myGeneration !== stateReadGeneration) return; // a newer read has already superseded this one

    if (result.ok) {
        App.state = result.state;
        App.stateReadOk = true;
        App.stateReadError = "";
        if (App.error && App.error.onRetry === refreshFromBackend) clearError();
    } else {
        App.stateReadOk = false;
        App.stateReadError = result.error;
        setError(App.stateReadError, { retry: true, onRetry: refreshFromBackend });
    }
    renderAll();
}

async function runAction(cmd, successMessage) {
    clearError();
    setBusy(true);
    const res = await executeCommand(cmd);
    await refreshFromBackend();
    setBusy(false);

    if (res.errno !== 0) {
        if (App.stateReadOk) {
            setError(res.stderr.trim() || `Command failed (errno ${res.errno}).`);
            renderAll();
        }
        return false;
    }
    if (successMessage) toast(successMessage);
    return true;
}

async function onPresetSelected(preset) {
    await runAction(`sh ${MODDIR}/apply_preset.sh ${preset.id}`, `Applied ${preset.name}`);
}
async function applyCustom(value) {
    await runAction(`sh ${MODDIR}/apply_preset.sh risu_custom ${value}`, `Custom saturation set to ${fmt(value)}`);
}
async function moduleOff() {
    await runAction(`sh ${MODDIR}/ModuleOff.sh`, "Module disabled");
}
async function doReset() {
    confirmDialog("Reset", "This clears the saved preset and restores native colors. This can't be undone.", async () => {
        await runAction(`sh ${MODDIR}/reset.sh`, "Reset complete");
    });
}

// --- Init ---------------------------------------------------------
document.addEventListener("DOMContentLoaded", async () => {
    document.querySelectorAll(".knav-item").forEach((btn) => btn.addEventListener("click", () => switchTab(btn.dataset.tab)));
    $("statusPill").addEventListener("click", () => switchTab("status"));
    switchTab("home");
    setupNavSwipe();
    setupPreviewInteraction();

    $("qaOff").addEventListener("click", moduleOff);
    $("qaReset").addEventListener("click", doReset);
    $("qaNative").addEventListener("click", () => runAction(`sh ${MODDIR}/apply_preset.sh risu_true`, "Set to native"));

    const slider = $("customSlider");
    const display = $("customValueDisplay");
    slider.addEventListener("input", () => { display.textContent = parseFloat(slider.value).toFixed(2); });
    $("customApplyButton").addEventListener("click", () => applyCustom(parseFloat(slider.value).toFixed(2)));
    $("customNativeButton").addEventListener("click", () => {
        slider.value = 1.0;
        display.textContent = "1.00";
        applyCustom("1.00");
    });

    $("confirmYesButton").addEventListener("click", confirmYes);
    $("confirmNoButton").addEventListener("click", confirmNo);

    const presetResult = await loadPresets();
    App.presets = presetResult.presets;
    if (!presetResult.ok) {
        setError("Could not load presets.conf - preset list unavailable.", { retry: true, onRetry: () => location.reload() });
    }

    await refreshFromBackend();

    App.appReady = true;
    hideGhost(); // if the user navigated away from Home before this resolved
});
