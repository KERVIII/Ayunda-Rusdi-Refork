// Ayunda Rusdi Color Enhancer 7.0 - WebUI
//
// The UI is a VIEW of backend state. Single source of truth: the output of
// AyundaRisu/status.sh (state, diagnostics, tweak read-back, preset table),
// fetched in ONE shell call after every action. Nothing is trusted from the
// client side. Commands only ever contain constants plus values that were
// validated here AND are re-validated by the shell scripts.

const MODDIR = "/data/adb/modules/AyundaRusdi/AyundaRisu";
const TW_DEFAULT = 0.85;
let callbackId = 0;

function executeCommand(cmd) {
    return new Promise((resolve) => {
        const cbName = `exec_callback_${Date.now()}_${callbackId++}`;
        window[cbName] = (errno, stdout, stderr) => {
            resolve({ errno, stdout: stdout || "", stderr: stderr || "" });
            delete window[cbName];
        };
        try {
            ksu.exec(cmd, "{}", cbName);
        } catch (e) {
            delete window[cbName];
            resolve({ errno: -1, stdout: "", stderr: "ksu bridge unavailable" });
        }
    });
}

// ── input validation (mirrors the shell side; the shell is authoritative) ──
const ID_RE = /^[a-z0-9_]{1,32}$/;
const NUM_RE = /^[0-9]+(\.[0-9]+)?$/;
const PKG_RE = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/;
function validPackage(text) { return typeof text === "string" && text.length <= 200 && PKG_RE.test(text); }
function validScale(text, lo, hi) {
    if (!NUM_RE.test(text) || text.length > 8) return false;
    const n = Number(text);
    return Number.isFinite(n) && n >= lo && n <= hi;
}

// ── status.sh parsing ──
function parseStatus(text) {
    const s = { presets: [], favorites: [], profiles: [] };
    text.split("\n").forEach((line) => {
        const i = line.indexOf("=");
        if (i === -1) return;
        const k = line.slice(0, i), v = line.slice(i + 1).trim();
        if (k === "favorite") {
            if (ID_RE.test(v)) s.favorites.push(v);
        } else if (k === "profile") {
            const f = v.split("|");
            if ((f.length === 5 || f.length === 6) && validPackage(f[0]) && (f[1] === "preset" || f[1] === "sat")) s.profiles.push({ pkg: f[0], kind: f[1], value: f[2], resolved: f[3], status: f[4], installed: f[5] === "0" ? "0" : (f[5] === "1" ? "1" : "?") });
        } else if (k === "preset") {
            const f = v.split("|");
            if (f.length === 4 && ID_RE.test(f[0])) s.presets.push({ id: f[0], name: f[1], description: f[2], value: f[3] });
        } else {
            s[k] = v;
        }
    });
    return s;
}

const App = {
    presets: [],
    status: null,      // last good parse of status.sh
    readOk: false,
    readError: "",
    activeTab: "home",
    error: null,
    gridBuiltFor: "", // preset-id signature of the built grid
    pinnedBuiltFor: "",
    profilesBuiltFor: "",
    editingPkg: "",
};

function $(id) { return document.getElementById(id); }
function fmt(val) { const n = parseFloat(val); return Number.isFinite(n) ? n.toFixed(2) : "-"; }
function findPreset(id) { return App.presets.find((p) => p.id === id); }
function favorites() { return App.readOk ? App.status.favorites : []; }
function profiles() { return App.readOk ? App.status.profiles : []; }
function isEnabled() { return App.readOk && App.status.module_state === "enabled"; }

// ── error card (persistent; DOM-built, no innerHTML) ──
function buildErrorCard() {
    const card = document.createElement("div");
    card.className = "error-card";
    const msg = document.createElement("div");
    msg.className = "msg";
    msg.textContent = App.error.message;
    card.appendChild(msg);
    const row = document.createElement("div");
    row.className = "row";
    if (App.error.onRetry) {
        const retry = document.createElement("button");
        retry.type = "button";
        retry.textContent = "Retry";
        retry.addEventListener("click", async () => {
            const fn = App.error.onRetry;
            App.error = null;
            renderErrorSlots();
            if (fn) await fn();
        });
        row.appendChild(retry);
    }
    const dismiss = document.createElement("button");
    dismiss.type = "button";
    dismiss.textContent = "Dismiss";
    dismiss.addEventListener("click", () => { App.error = null; renderErrorSlots(); });
    row.appendChild(dismiss);
    card.appendChild(row);
    return card;
}
const ERROR_SLOTS = { home: "homeErrorSlot", presets: "presetsErrorSlot", controls: "controlsErrorSlot", about: "aboutErrorSlot" };
function renderErrorSlots() {
    Object.values(ERROR_SLOTS).forEach((id) => { const el = $(id); if (el) el.textContent = ""; });
    if (!App.error) return;
    const slot = $(ERROR_SLOTS[App.activeTab]);
    if (slot) slot.appendChild(buildErrorCard());
}
function setError(message, onRetry) { App.error = { message, onRetry: onRetry || null }; }

// ═══════════════════════════════ RENDERING ═══════════════════════════════

function renderStatusPill() {
    const dot = $("statusDot");
    dot.className = "dot";
    if (!App.readOk) { dot.classList.add("error"); $("statusPillText").textContent = "Error"; return; }
    dot.classList.add(isEnabled() ? "on" : "off");
    $("statusPillText").textContent = isEnabled() ? "Enabled" : "Disabled";
}

function shownSaturation() {
    if (!isEnabled()) return 1.0;
    const v = parseFloat(App.status.active_value);
    return Number.isFinite(v) ? v : 1.0;
}

function renderHome() {
    const heroDot = $("heroDot");
    heroDot.className = "dot";
    if (!App.readOk) {
        $("heroPresetName").textContent = "Unable to read state";
        $("heroPresetDesc").textContent = App.readError;
        $("heroStateWord").textContent = "unknown";
        heroDot.classList.add("error");
        $("statSatQuick").textContent = "-";
        $("statStateQuick").textContent = "Error";
        $("homeMeterValue").textContent = "-";
        $("homeMeterFill").style.width = "0%";
        renderPreview();
        return;
    }
    const enabled = isEnabled();
    const meta = findPreset(App.status.active_preset);
    $("heroPresetName").textContent = enabled ? (meta ? meta.name : App.status.active_preset || "Unknown preset") : "Native";
    $("heroPresetDesc").textContent = enabled ? (meta ? meta.description : "") : "No enhancement is currently applied.";
    $("heroStateWord").textContent = enabled ? "enabled" : "disabled";
    heroDot.classList.add(enabled ? "on" : "off");
    const sat = shownSaturation();
    $("statSatQuick").textContent = fmt(sat);
    $("statStateQuick").textContent = enabled ? "Enabled" : "Disabled";
    $("homeMeterValue").textContent = `${fmt(sat)} / 2.50`;
    $("homeMeterFill").style.width = `${Math.max(0, Math.min(1, sat / 2.5)) * 100}%`;
    renderPreview();
}

// ── Before/After preview: CSS saturate() on a bundled image. Frontend-only
// visual aid; never issues a backend command and makes no claim about the
// real panel output. Three bundled scenes; switching preloads + decodes the
// new image, cross-fades, and reports a load failure instead of showing a
// blank frame. ──
const PREVIEW_SCENES = [
    { src: "/scene1.jpg", pos: "50% 32%" },
    { src: "/scene2.jpg", pos: "50% 50%" },
    { src: "/scene3.jpg", pos: "50% 50%" },
];
let previewScene = 0;
let sceneToken = 0;
function setSceneImages(i) {
    ["previewImgBefore", "previewImgAfter"].forEach((id) => {
        const img = $(id);
        img.src = PREVIEW_SCENES[i].src;
        img.style.objectPosition = PREVIEW_SCENES[i].pos;
    });
}
async function showScene(i) {
    if (i < 0 || i >= PREVIEW_SCENES.length) return;
    const token = ++sceneToken;
    const compare = $("previewCompare"), err = $("previewError");
    const probe = new Image();
    probe.src = PREVIEW_SCENES[i].src;
    try {
        await probe.decode();
    } catch (e) {
        if (token !== sceneToken) return;
        err.textContent = `Scene ${i + 1} image could not be loaded.`;
        err.classList.remove("hidden");
        return;
    }
    if (token !== sceneToken) return; // a newer selection won
    err.classList.add("hidden");
    previewScene = i;
    document.querySelectorAll(".preview-scene-btn").forEach((b, j) => {
        b.classList.toggle("active", j === i);
        b.setAttribute("aria-pressed", j === i ? "true" : "false");
    });
    compare.classList.add("fading");
    setTimeout(() => {
        if (token !== sceneToken) return;
        setSceneImages(i);
        requestAnimationFrame(() => compare.classList.remove("fading"));
    }, 140);
}
function renderPreview() {
    if (!$("previewImgBefore").getAttribute("src")) setSceneImages(previewScene);
    const sat = App.readOk ? shownSaturation() : 1.0;
    $("previewAfterWrap").style.setProperty("--preview-sat", sat);
    $("previewSatLabel").textContent = sat.toFixed(2);
}
function setupPreviewInteraction() {
    const compare = $("previewCompare");
    function setPos(clientX) {
        const rect = compare.getBoundingClientRect();
        const pct = Math.max(0, Math.min(100, ((clientX - rect.left) / rect.width) * 100));
        compare.style.setProperty("--preview-pos", `${pct}%`);
    }
    let dragging = false;
    compare.addEventListener("pointerdown", (e) => { dragging = true; compare.setPointerCapture(e.pointerId); setPos(e.clientX); });
    compare.addEventListener("pointermove", (e) => { if (dragging) setPos(e.clientX); });
    const stop = () => { dragging = false; };
    compare.addEventListener("pointerup", stop);
    compare.addEventListener("pointercancel", stop);
    document.querySelectorAll(".preview-scene-btn").forEach((btn, i) => btn.addEventListener("click", () => showScene(i)));
    document.querySelectorAll(".preview-scene-btn").forEach((b, j) => b.setAttribute("aria-pressed", j === 0 ? "true" : "false"));
}

// ── presets: grid is built ONCE per preset table; later renders only toggle
// classes/text on existing nodes (no DOM rebuild per action). ──
function buildPresetCard(preset) {
    const cell = document.createElement("div");
    cell.className = "pcard-cell";

    const card = document.createElement("button");
    card.type = "button";
    card.className = "pcard";
    card.dataset.id = preset.id;
    card.setAttribute("aria-pressed", "false");

    const head = document.createElement("div");
    head.className = "pcard-head";
    const valSpan = document.createElement("span");
    valSpan.textContent = preset.value === "custom" ? "SET" : fmt(preset.value);
    const tag = document.createElement("span");
    tag.className = "ck";
    head.appendChild(valSpan);
    head.appendChild(tag);

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

    const fav = document.createElement("button");
    fav.type = "button";
    fav.className = "fav-btn";
    fav.dataset.id = preset.id;
    fav.addEventListener("click", () => toggleFavorite(preset));

    cell.appendChild(card);
    cell.appendChild(fav);
    return cell;
}

function buildChip(preset) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "chip";
    chip.dataset.id = preset.id;
    chip.textContent = preset.name.replace(/^Risu /, "");
    chip.setAttribute("aria-label", `Apply ${preset.name}`);
    chip.addEventListener("click", () => onPresetSelected(preset));
    return chip;
}

function renderPinned(activeId) {
    const pinned = favorites().map(findPreset).filter(Boolean);
    const sig = pinned.map((p) => p.id).join(",");
    if (sig !== App.pinnedBuiltFor) {
        [["homePinned", "homePinnedBox"], ["presetsPinned", "presetsPinnedBox"]].forEach(([rowId, boxId]) => {
            const row = $(rowId);
            row.textContent = "";
            pinned.forEach((p) => row.appendChild(buildChip(p)));
            $(boxId).classList.toggle("hidden", pinned.length === 0);
        });
        App.pinnedBuiltFor = sig;
    }
    document.querySelectorAll(".chip").forEach((c) => {
        const on = c.dataset.id === activeId;
        c.classList.toggle("active", on);
        c.setAttribute("aria-pressed", on ? "true" : "false");
    });
}

function renderPresets() {
    const grid = $("presetGrid");
    const sig = App.presets.map((p) => p.id).join(",");
    if (sig !== App.gridBuiltFor) {
        grid.textContent = "";
        App.presets.forEach((p) => grid.appendChild(buildPresetCard(p)));
        App.gridBuiltFor = sig;
        fillProfilePresetSelect();
    }
    const activeId = isEnabled() ? App.status.active_preset : "";
    grid.querySelectorAll("button.pcard").forEach((card) => {
        const active = card.dataset.id === activeId;
        card.classList.toggle("active", active);
        card.setAttribute("aria-pressed", active ? "true" : "false");
        card.querySelector(".ck").textContent = active ? "ACTIVE" : "";
    });
    const favs = favorites();
    grid.querySelectorAll(".fav-btn").forEach((btn) => {
        const pinned = favs.includes(btn.dataset.id);
        const p = findPreset(btn.dataset.id);
        btn.classList.toggle("on", pinned);
        btn.setAttribute("aria-pressed", pinned ? "true" : "false");
        btn.setAttribute("aria-label", `${pinned ? "Unpin" : "Pin"} ${p ? p.name : btn.dataset.id}`);
        btn.textContent = pinned ? "\u2605" : "\u2606";
    });
    renderPinned(activeId);
    $("presetsCount").textContent = `${App.presets.length} Profiles`;
}

// ── controls ──
function renderCustom() {
    const custom = isEnabled() && App.status.active_preset === "risu_custom";
    $("customCard").classList.toggle("hidden", !custom);
    $("customHint").classList.toggle("hidden", custom);
    if (!App.readOk) return;
    const slider = $("customSlider");
    if (custom) {
        const v = parseFloat(App.status.active_value);
        slider.value = Number.isFinite(v) ? v : 1.0;
        $("customValueDisplay").textContent = parseFloat(slider.value).toFixed(2);
    }
}

function renderTweaks() {
    const supported = App.readOk && App.status.tweaks_supported === "1";
    $("tweaksUnsupported").classList.toggle("hidden", !App.readOk || supported);
    $("tweaksCard").classList.toggle("hidden", !supported);
    if (!supported) return;
    $("twWindow").textContent = App.status.window === "null" ? "default" : fmt(App.status.window);
    $("twTransition").textContent = App.status.transition === "null" ? "default" : fmt(App.status.transition);
    $("twAnimator").textContent = App.status.animator === "null" ? "default" : fmt(App.status.animator);
    const applied = App.status.tweaks_applied === "1";
    $("twApplied").textContent = applied ? `Applied (${fmt(App.status.tweaks_value)})` : "Not applied";
    if (applied) {
        $("tweakSlider").value = App.status.tweaks_value;
        $("tweakValueDisplay").textContent = fmt(App.status.tweaks_value);
    }
}

function renderDiagnostics() {
    const set = (id, v) => { $(id).textContent = v; };
    if (!App.readOk) {
        ["statVersion", "statState", "statPreset", "statSaturation", "statBackend", "statRoot", "statAndroid", "statModel", "statVerify"].forEach((id) => set(id, "-"));
        set("statRead", "FAILED");
        set("aboutVersion", "-");
        return;
    }
    const s = App.status, enabled = isEnabled(), meta = findPreset(s.active_preset);
    set("statVersion", s.version ? `V${s.version}` : "-");
    set("aboutVersion", s.version ? `V${s.version}` : "-");
    set("statState", enabled ? "Enabled" : "Disabled");
    set("statPreset", s.active_preset ? (meta ? meta.name : s.active_preset) + (enabled ? "" : " (off)") : "-");
    set("statSaturation", enabled ? fmt(s.active_value) : "1.00 (native)");
    set("statBackend", s.backend === "1" ? "SurfaceFlinger OK" : "SurfaceFlinger unavailable");
    set("statRead", s.state_valid === "1" ? "OK" : "INVALID");
    set("statRoot", s.root || "-");
    set("statAndroid", s.android ? `${s.android}${s.sdk ? ` (API ${s.sdk})` : ""}` : "-");
    set("statModel", s.model || "-");
    set("statVerify", s.verify === "PASS" ? "PASS" : "FAIL");
}

// ── per-app profiles ──
function fillProfilePresetSelect() {
    const sel = $("profilePreset");
    const keep = sel.value;
    sel.textContent = "";
    App.presets.filter((p) => p.id !== "risu_custom").forEach((p) => {
        const o = document.createElement("option");
        o.value = p.id;
        o.textContent = `${p.name} (${fmt(p.value)})`;
        sel.appendChild(o);
    });
    if (keep) sel.value = keep;
}
function profileInEffect(p) {
    if (!isEnabled() || p.status !== "ok") return false;
    if (p.kind === "preset") return App.status.active_preset === p.value;
    return App.status.active_preset === "risu_custom" && fmt(App.status.active_value) === fmt(p.resolved);
}
function describeProfile(p) {
    if (p.kind === "sat") return `Saturation ${fmt(p.value)}`;
    const meta = findPreset(p.value);
    return meta ? `${meta.name} (${fmt(p.resolved)})` : `${p.value} (missing)`;
}
function renderProfiles() {
    const list = profiles();
    const sig = list.map((p) => [p.pkg, p.kind, p.value, p.status, p.installed].join(":")).join(",") + "|" + (isEnabled() ? App.status.active_preset + App.status.active_value : "off");
    $("profileEmpty").classList.toggle("hidden", list.length > 0 || !App.readOk);
    if (sig === App.profilesBuiltFor) return;
    App.profilesBuiltFor = sig;
    const box = $("profileList");
    box.textContent = "";
    list.forEach((p) => {
        const row = document.createElement("div");
        row.className = "profile-row";
        row.dataset.pkg = p.pkg;
        const info = document.createElement("div");
        info.className = "profile-info";
        const name = document.createElement("div");
        name.className = "profile-pkg";
        name.textContent = p.pkg;
        const map = document.createElement("div");
        map.className = "profile-map";
        map.textContent = describeProfile(p);
        info.appendChild(name);
        info.appendChild(map);
        if (p.status !== "ok" || profileInEffect(p) || p.installed === "0") {
            const tag = document.createElement("span");
            tag.className = "profile-tag" + (p.status !== "ok" || p.installed === "0" ? " broken" : "");
            tag.textContent = p.status !== "ok" ? "BROKEN" : (p.installed === "0" ? "NOT INSTALLED" : "IN EFFECT");
            info.appendChild(tag);
        }
        const acts = document.createElement("div");
        acts.className = "profile-actions";
        [["Apply", () => applyProfile(p), p.status !== "ok"], ["Edit", () => editProfile(p), false], ["Delete", () => deleteProfile(p), false]].forEach(([label, fn, dis]) => {
            const b = document.createElement("button");
            b.type = "button";
            b.className = "cm-btn-secondary profile-btn";
            b.dataset.action = label.toLowerCase();
            b.textContent = label;
            b.disabled = dis;
            b.addEventListener("click", fn);
            acts.appendChild(b);
        });
        row.appendChild(info);
        row.appendChild(acts);
        box.appendChild(row);
    });
}
function syncProfileKind() {
    const sat = $("profileKind").value === "sat";
    $("profilePresetWrap").classList.toggle("hidden", sat);
    $("profileSatWrap").classList.toggle("hidden", !sat);
}
function resetProfileForm() {
    App.editingPkg = "";
    $("profilePkg").value = "";
    $("profilePkg").readOnly = false;
    $("profileKind").value = "preset";
    $("profileSat").value = "1.00";
    $("profileFormTitle").textContent = "New profile";
    $("profileCancel").classList.add("hidden");
    syncProfileKind();
}
function editProfile(p) {
    App.editingPkg = p.pkg;
    $("profilePkg").value = p.pkg;
    $("profilePkg").readOnly = true;
    $("profileKind").value = p.kind;
    if (p.kind === "preset") $("profilePreset").value = p.value; else $("profileSat").value = fmt(p.value);
    $("profileFormTitle").textContent = "Edit profile";
    $("profileCancel").classList.remove("hidden");
    syncProfileKind();
    $("profileForm").scrollIntoView({ block: "center" });
}
async function saveProfile() {
    const pkg = $("profilePkg").value.trim();
    if (!validPackage(pkg)) { setError("Invalid package name. Use letters, digits, underscores and dots, e.g. com.example.app"); renderErrorSlots(); return; }
    const kind = $("profileKind").value;
    let value;
    if (kind === "preset") {
        value = $("profilePreset").value;
        if (!ID_RE.test(value) || !findPreset(value)) { setError("Choose a preset."); renderErrorSlots(); return; }
    } else {
        value = $("profileSat").value.trim();
        if (!validScale(value, 0, 2.5)) { setError(`Invalid saturation value: ${value || "(empty)"}. Allowed 0.00-2.50.`); renderErrorSlots(); return; }
        value = parseFloat(value).toFixed(2);
    }
    const ok = await runAction(`sh ${MODDIR}/profile.sh set ${pkg} ${kind} ${value}`, `Profile saved for ${pkg}`);
    if (ok) resetProfileForm();
}
async function applyProfile(p) {
    if (!validPackage(p.pkg)) return;
    await runAction(`sh ${MODDIR}/profile.sh apply ${p.pkg}`, `Applied profile for ${p.pkg}`);
}
function deleteProfile(p) {
    if (!validPackage(p.pkg)) return;
    confirmDialog("Delete profile", `Remove the profile for ${p.pkg}? Your current color setting is not changed.`, async () => {
        const ok = await runAction(`sh ${MODDIR}/profile.sh delete ${p.pkg}`, "Profile deleted");
        if (ok && App.editingPkg === p.pkg) resetProfileForm();
    });
}

// ── favorites ──
async function toggleFavorite(preset) {
    if (!ID_RE.test(preset.id)) return;
    const pinned = favorites().includes(preset.id);
    await runAction(`sh ${MODDIR}/favorites.sh ${pinned ? "unpin" : "pin"} ${preset.id}`, `${pinned ? "Unpinned" : "Pinned"} ${preset.name}`);
}

// ── Diagnostic Log: the text is generated by AyundaRisu/diagnostic.sh from the
// live module state (one generator for the screen, Copy and Save Logs). There
// is no Web Share path. Nothing here is hardcoded. ──
function setLogStatus(msg, kind) {
    const el = $("logStatus");
    el.textContent = msg;
    el.className = "share-status" + (kind ? ` ${kind}` : "");
}
async function generateDiagnostic() {
    const res = await executeCommand(`sh ${MODDIR}/diagnostic.sh print 2>&1`);
    if (res.errno !== 0 || !res.stdout.trim()) {
        return { ok: false, error: (res.stderr.trim() || res.stdout.trim() || `diagnostic script failed (errno ${res.errno})`) };
    }
    return { ok: true, text: res.stdout.replace(/\n+$/, "") };
}
let diagGeneration = 0;
async function refreshDiagnosticText() {
    const gen = ++diagGeneration;
    const r = await generateDiagnostic();
    if (gen !== diagGeneration || document.activeElement === $("diagText")) return;
    $("diagText").value = r.ok ? r.text : `Could not generate the diagnostic log:\n${r.error}`;
}
async function copyText(text) {
    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
        try { await navigator.clipboard.writeText(text); return true; } catch (e) { /* fall through */ }
    }
    try {
        const ta = $("diagText");
        ta.removeAttribute("readonly");
        ta.focus();
        ta.select();
        ta.setSelectionRange(0, text.length);
        const ok = document.execCommand && document.execCommand("copy");
        ta.setAttribute("readonly", "");
        ta.blur();
        return !!ok;
    } catch (e) {
        $("diagText").setAttribute("readonly", "");
        return false;
    }
}
async function onCopyDiagnostic() {
    const r = await generateDiagnostic();
    if (!r.ok) { setLogStatus(`Failed to generate the log: ${r.error}`, "err"); return; }
    $("diagText").value = r.text;
    const ok = await copyText(r.text);
    if (ok) { setLogStatus("Copied to clipboard.", "ok"); toast("Diagnostic copied"); }
    else setLogStatus("Copy failed. Select the text above and copy it manually.", "err");
}
// Success is reported ONLY if the script exited 0 AND printed "OK saved <path>".
async function onSaveLogs() {
    setBusy(true);
    setLogStatus("Saving...", "");
    const res = await executeCommand(`sh ${MODDIR}/diagnostic.sh save`);
    setBusy(false);
    const out = res.stdout.trim();
    if (res.errno === 0 && /^OK saved Download\/AyundaRusdi Logs\/[A-Za-z0-9_.-]+\.txt$/.test(out)) {
        setLogStatus(`Saved:\n${out.slice(9)}`, "ok");
        toast("Log saved");
        return;
    }
    const why = res.stderr.trim().replace(/^error:\s*/, "") || out || `command failed (errno ${res.errno})`;
    setLogStatus(`Failed to save logs:\n${why}`, "err");
}

// ── per-app auto switching status (everything below comes from watcher.sh status) ──
function autoSwitchLabel() {
    if (!App.readOk) return "unknown";
    const s = App.status;
    if (s.watcher_supported !== "1") return "unsupported";
    if (s.autoswitch !== "1") return "off";
    if (s.watcher === "running") return "running";
    if (s.watcher_reason === "module_disabled") return "stopped (module disabled)";
    if (s.watcher_reason === "no_profiles" || !s.profiles.length) return "idle, no profiles";
    return "not running";
}
function profileLabel(pkg) {
    const p = App.status.profiles.find((x) => x.pkg === pkg);
    if (!p) return "unknown profile";
    return p.kind === "sat" ? `Saturation ${fmt(p.value)}` : ((findPreset(p.value) || {}).name || p.value);
}
function renderAuto() {
    const ok = App.readOk, s = App.status || { profiles: [] };
    const on = ok && s.autoswitch === "1";
    $("autoState").textContent = !ok ? "-" : (on ? "On" : "Off");
    $("watcherState").textContent = !ok ? "-" : (s.watcher_supported !== "1" ? "Unsupported (setsid/logcat missing)" : autoSwitchLabel().replace(/^./, (c) => c.toUpperCase()));
    $("lastFg").textContent = (ok && s.last_foreground) || "none yet";
    const ov = ok && s.override ? s.override.split("|") : null;
    const hasOv = !!(ov && ov.length === 2 && validPackage(ov[0]));
    $("overrideNow").textContent = hasOv ? profileLabel(ov[0]) : "none";
    $("overrideVal").textContent = !ok ? "-" : (hasOv ? fmt(ov[1]) : `${isEnabled() ? fmt(s.active_value) : "1.00"} (global)`);
    let be = "none yet";
    if (ok && s.last_apply_result === "ok") be = `PASS${s.last_apply_time ? ` (${s.last_apply_time})` : ""}`;
    else if (ok && s.last_apply_result === "skipped") be = "No change needed";
    else if (ok && s.last_apply_result === "failed") be = `FAIL: ${s.last_apply_reason || "unknown reason"}`;
    $("applyResult").textContent = !ok ? "-" : be;
    $("autoToggle").textContent = on ? "Turn auto switching off" : "Turn auto switching on";
}
async function toggleAuto() {
    const on = App.readOk && App.status.autoswitch === "1";
    await runAction(`sh ${MODDIR}/watcher.sh auto ${on ? "off" : "on"}`, on ? "Auto switching turned off" : "Auto switching turned on");
}

function renderAll() {
    renderStatusPill();
    renderHome();
    renderPresets();
    renderCustom();
    renderTweaks();
    renderDiagnostics();
    renderProfiles();
    renderAuto();
    if (App.activeTab === "controls") refreshDiagnosticText();
    renderErrorSlots();
}

// ── tabs ──
const TAB_ORDER = ["home", "presets", "controls", "about"];
function switchTab(tab) {
    if (!TAB_ORDER.includes(tab)) return;
    const changed = App.activeTab !== tab;
    App.activeTab = tab;
    document.querySelectorAll(".tab-content").forEach((el) => el.classList.toggle("active", el.id === `tab-${tab}`));
    if (changed) { const act = $(`tab-${tab}`); act.scrollTop = 0; window.scrollTo(0, 0); }
    if (changed && tab === "controls" && App.readOk) refreshDiagnosticText();
    document.querySelectorAll(".knav-item").forEach((el) => {
        el.classList.toggle("active", el.dataset.tab === tab);
        el.setAttribute("aria-current", el.dataset.tab === tab ? "page" : "false");
    });
    $("knavKnob").style.setProperty("--knav-idx", TAB_ORDER.indexOf(tab));
    // the knob shows a clone of the active tab's own icon (single source)
    const svg = document.querySelector(`.knav-item[data-tab="${tab}"] svg`);
    const knobIcon = $("knavKnobIcon");
    knobIcon.textContent = "";
    if (svg) knobIcon.appendChild(svg.cloneNode(true));
    renderErrorSlots();
}

// Swipe on the navbar. setPointerCapture only after a horizontal drag is
// confirmed (capturing on pointerdown would retarget taps away from buttons).
function setupNavSwipe() {
    const nav = $("bottom-nav");
    const THRESH = 40, LOCK = 10;
    let startX = 0, startY = 0, pid = null, dx = 0, tracking = false, horiz = null, captured = false;
    const reset = () => { tracking = false; horiz = null; captured = false; dx = 0; };
    nav.addEventListener("pointerdown", (e) => { tracking = true; horiz = null; captured = false; startX = e.clientX; startY = e.clientY; pid = e.pointerId; dx = 0; });
    nav.addEventListener("pointermove", (e) => {
        if (!tracking) return;
        dx = e.clientX - startX;
        const dy = e.clientY - startY;
        if (horiz === null && (Math.abs(dx) > LOCK || Math.abs(dy) > LOCK)) horiz = Math.abs(dx) > Math.abs(dy);
        if (horiz && !captured) { try { nav.setPointerCapture(pid); } catch (err) { /* older WebViews */ } captured = true; }
        if (horiz) e.preventDefault();
    });
    nav.addEventListener("pointerup", (e) => {
        if (!tracking) return;
        const was = horiz === true, finalDx = e.clientX - startX;
        reset();
        if (!was || Math.abs(finalDx) < THRESH) return;
        const idx = TAB_ORDER.indexOf(App.activeTab);
        if (finalDx < 0 && idx < TAB_ORDER.length - 1) switchTab(TAB_ORDER[idx + 1]);
        else if (finalDx > 0 && idx > 0) switchTab(TAB_ORDER[idx - 1]);
    });
    nav.addEventListener("pointercancel", reset);
}

// ── toast / confirm ──
let toastTimer;
function toast(msg) {
    const el = $("toast");
    el.textContent = msg;
    el.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove("show"), 2200);
}
let confirmFn = null;
function confirmDialog(title, desc, fn) {
    $("confirm-title").textContent = title;
    $("confirm-desc").textContent = desc;
    confirmFn = fn;
    $("confirm-overlay").classList.add("show");
}
function confirmYes() { $("confirm-overlay").classList.remove("show"); const fn = confirmFn; confirmFn = null; if (fn) fn(); }
function confirmNo() { $("confirm-overlay").classList.remove("show"); confirmFn = null; }

// ── backend sync ──
function setBusy(busy) {
    document.querySelectorAll("button, input[type=range], input[type=number], select").forEach((b) => (b.disabled = busy));
    if (!busy) renderProfilesButtons();
}

// after a busy period, re-disable Apply on broken profiles
function renderProfilesButtons() {
    document.querySelectorAll(".profile-row").forEach((row) => {
        const p = profiles().find((x) => x.pkg === row.dataset.pkg);
        const b = row.querySelector('button[data-action="apply"]');
        if (b && p) b.disabled = p.status !== "ok";
    });
}
let readGeneration = 0; // only the newest read may update the UI
async function refreshFromBackend() {
    const gen = ++readGeneration;
    const res = await executeCommand(`sh ${MODDIR}/status.sh 2>&1`);
    if (gen !== readGeneration) return;
    let parsed = null;
    if (res.errno === 0) parsed = parseStatus(res.stdout);
    if (!parsed || parsed.state_read !== "1") {
        App.readOk = false;
        App.readError = res.errno !== 0
            ? (res.stderr.trim() || res.stdout.trim() || `Unable to read module state (errno ${res.errno}).`)
            : "Module state file is missing or unreadable.";
        if (parsed && parsed.presets.length) App.presets = parsed.presets;
        setError(App.readError, refreshFromBackend);
    } else {
        App.status = parsed;
        App.readOk = true;
        App.readError = "";
        if (parsed.presets.length) App.presets = parsed.presets;
        if (App.error && App.error.onRetry === refreshFromBackend) App.error = null;
    }
    renderAll();
}

// Success is reported ONLY when the script exited 0 AND printed "OK ...".
async function runAction(cmd, successMessage) {
    App.error = null;
    setBusy(true);
    const res = await executeCommand(cmd);
    await refreshFromBackend();
    setBusy(false);
    const success = res.errno === 0 && /^OK\b/.test(res.stdout.trim());
    if (!success) {
        const why = res.stderr.trim() || res.stdout.trim() || `Command failed (errno ${res.errno}).`;
        setError(why);
        renderErrorSlots();
        return false;
    }
    toast(successMessage);
    return true;
}

async function onPresetSelected(preset) {
    if (!ID_RE.test(preset.id)) { setError("Invalid preset id."); renderErrorSlots(); return; }
    const ok = await runAction(`sh ${MODDIR}/apply_preset.sh ${preset.id}`, `Applied ${preset.name}`);
    if (ok && preset.id === "risu_custom") switchTab("controls");
}
async function applyCustom(text) {
    if (!validScale(text, 0, 2.5)) { setError(`Invalid saturation value: ${text}`); renderErrorSlots(); return; }
    await runAction(`sh ${MODDIR}/apply_preset.sh risu_custom ${text}`, `Custom saturation set to ${fmt(text)}`);
}
async function moduleOff() { await runAction(`sh ${MODDIR}/ModuleOff.sh`, "Module disabled"); }
function doReset() {
    confirmDialog("Reset", "Applies native saturation (1.00), clears the selected preset and restores animation scales if you changed them here. Pinned presets and profiles are kept.", async () => {
        await runAction(`sh ${MODDIR}/reset.sh`, "Reset complete");
    });
}
async function applyTweaks(text) {
    if (!validScale(text, 0.25, 2)) { setError(`Invalid animation scale: ${text}`); renderErrorSlots(); return; }
    await runAction(`sh ${MODDIR}/ui_tweaks.sh apply ${text}`, `Animation scale ${fmt(text)} applied`);
}
async function resetTweaks() { await runAction(`sh ${MODDIR}/ui_tweaks.sh reset`, "Animation scales restored"); }

// ── init ──
document.addEventListener("DOMContentLoaded", async () => {
    document.querySelectorAll(".knav-item").forEach((btn) => btn.addEventListener("click", () => switchTab(btn.dataset.tab)));
    $("statusPill").addEventListener("click", () => switchTab("controls"));
    switchTab("home");
    setupNavSwipe();
    setupPreviewInteraction();

    $("qaOff").addEventListener("click", moduleOff);
    $("qaReset").addEventListener("click", doReset);
    $("qaNative").addEventListener("click", () => runAction(`sh ${MODDIR}/apply_preset.sh risu_true`, "Set to native"));

    const slider = $("customSlider"), display = $("customValueDisplay");
    slider.addEventListener("input", () => { display.textContent = parseFloat(slider.value).toFixed(2); });
    slider.addEventListener("change", () => applyCustom(parseFloat(slider.value).toFixed(2)));
    $("customNativeButton").addEventListener("click", () => { slider.value = 1.0; display.textContent = "1.00"; applyCustom("1.00"); });

    const tw = $("tweakSlider"), twDisplay = $("tweakValueDisplay");
    tw.value = TW_DEFAULT;
    tw.addEventListener("input", () => { twDisplay.textContent = parseFloat(tw.value).toFixed(2); });
    $("tweakApplyButton").addEventListener("click", () => applyTweaks(parseFloat(tw.value).toFixed(2)));
    $("tweakResetButton").addEventListener("click", resetTweaks);

    $("profileKind").addEventListener("change", syncProfileKind);
    $("profileSave").addEventListener("click", saveProfile);
    $("profileCancel").addEventListener("click", resetProfileForm);
    $("autoToggle").addEventListener("click", toggleAuto);
    syncProfileKind();
    $("diagCopyButton").addEventListener("click", onCopyDiagnostic);
    $("diagSaveButton").addEventListener("click", onSaveLogs);

    $("confirmYesButton").addEventListener("click", confirmYes);
    $("confirmNoButton").addEventListener("click", confirmNo);

    // Re-sync when the WebUI regains focus (state may have changed via boot
    // script, another action surface, or the root manager).
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refreshFromBackend(); });
    window.addEventListener("focus", () => refreshFromBackend());

    await refreshFromBackend();
});
