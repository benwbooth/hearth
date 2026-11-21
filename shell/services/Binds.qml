pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Keyboard shortcuts editor (Settings > Keyboard Shortcuts), arbor only.
//
// The defaults are the `binds { }` of arbor's config (~/.config/arbor/config.kdl,
// read-only from /etc/nixos). Changes are saved in settings.json `binds`
// ({ "Mod+Q": { off: true } | { action, props } }) and written to
// ~/.config/hearth/arbor-binds.kdl, which the config includes after its own
// binds: arbor replaces a bind with the same keys, so a changed shortcut is
// "turn the old keys off (bound to nothing) + bind the new keys".
//
// App shortcuts: apps that register global shortcuts through the portal
// (arbor's GlobalShortcuts IPC); `globalSupported` is false when the running
// arbor doesn't have that IPC, and the page hides the section.
Singleton {
    id: root

    readonly property var overrides: { void Settings.data; return Settings.data.binds || {}; }
    property var defaults: []          // [{ key, props, action }]
    readonly property string arborConfig: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/arbor/config.kdl"

    // --- keys ---
    readonly property var modOrder: ["Mod", "Super", "Ctrl", "Alt", "Shift", "ISO_Level3_Shift"]
    function modName(m) {
        const l = m.toLowerCase();
        if (l === "mod") return "Mod";
        if (l === "super" || l === "win" || l === "meta" || l === "mod4") return "Super";
        if (l === "ctrl" || l === "control") return "Ctrl";
        if (l === "alt" || l === "mod1") return "Alt";
        if (l === "shift") return "Shift";
        if (l === "iso_level3_shift" || l === "mod5") return "ISO_Level3_Shift";
        return m;
    }
    function splitKey(k) {
        const parts = k.split("+");
        const key = parts.pop();
        return { mods: parts.map(modName), key: key };
    }
    // Comparable form: Mod counts as Super (arbor's default mod key).
    function norm(k) {
        const s = splitKey(k);
        const mods = Array.from(new Set(s.mods.map(m => m === "Mod" ? "Super" : m))).sort();
        return mods.concat([s.key.toLowerCase()]).join("+");
    }
    // "Mod+Shift+Slash" -> "Super+Shift+/"
    readonly property var keyGlyphs: ({ Slash: "/", Backslash: "\\", Comma: ",", Period: ".", Minus: "-", Equal: "=",
        BracketLeft: "[", BracketRight: "]", Semicolon: ";", Apostrophe: "'", Grave: "`", Page_Up: "Page Up",
        Page_Down: "Page Down", Return: "Return", space: "Space", Space: "Space", Escape: "Esc", Delete: "Delete",
        BackSpace: "Backspace", Print: "Print Screen", WheelScrollDown: "scroll down", WheelScrollUp: "scroll up",
        WheelScrollLeft: "scroll left", WheelScrollRight: "scroll right",
        XF86AudioRaiseVolume: "Volume Up", XF86AudioLowerVolume: "Volume Down", XF86AudioMute: "Mute",
        XF86AudioMicMute: "Mic Mute", XF86AudioPlay: "Play", XF86AudioPause: "Pause (media)", XF86AudioNext: "Next Track",
        XF86AudioPrev: "Previous Track", XF86AudioStop: "Stop", XF86MonBrightnessUp: "Brightness Up",
        XF86MonBrightnessDown: "Brightness Down", XF86PowerOff: "Power button" })
    function pretty(k) {
        const s = splitKey(k);
        return s.mods.map(m => m === "Mod" ? "Super" : m === "ISO_Level3_Shift" ? "AltGr" : m)
            .concat([keyGlyphs[s.key] || s.key]).join("+");
    }

    // Qt key event -> arbor key name ("" while only modifiers are held).
    readonly property var qtKeys: {
        const m = {};
        m[Qt.Key_Return] = "Return"; m[Qt.Key_Enter] = "Return"; m[Qt.Key_Escape] = "Escape";
        m[Qt.Key_Tab] = "Tab"; m[Qt.Key_Backtab] = "Tab"; m[Qt.Key_Space] = "Space"; m[Qt.Key_Backspace] = "BackSpace";
        m[Qt.Key_Delete] = "Delete"; m[Qt.Key_Insert] = "Insert"; m[Qt.Key_Home] = "Home"; m[Qt.Key_End] = "End";
        m[Qt.Key_PageUp] = "Page_Up"; m[Qt.Key_PageDown] = "Page_Down"; m[Qt.Key_Left] = "Left"; m[Qt.Key_Right] = "Right";
        m[Qt.Key_Up] = "Up"; m[Qt.Key_Down] = "Down"; m[Qt.Key_Print] = "Print"; m[Qt.Key_Pause] = "Pause";
        m[Qt.Key_Minus] = "Minus"; m[Qt.Key_Underscore] = "Minus"; m[Qt.Key_Equal] = "Equal"; m[Qt.Key_Plus] = "Equal";
        m[Qt.Key_BracketLeft] = "BracketLeft"; m[Qt.Key_BraceLeft] = "BracketLeft";
        m[Qt.Key_BracketRight] = "BracketRight"; m[Qt.Key_BraceRight] = "BracketRight";
        m[Qt.Key_Semicolon] = "Semicolon"; m[Qt.Key_Colon] = "Semicolon";
        m[Qt.Key_Apostrophe] = "Apostrophe"; m[Qt.Key_QuoteDbl] = "Apostrophe";
        m[Qt.Key_QuoteLeft] = "Grave"; m[Qt.Key_AsciiTilde] = "Grave";
        m[Qt.Key_Backslash] = "Backslash"; m[Qt.Key_Bar] = "Backslash";
        m[Qt.Key_Comma] = "Comma"; m[Qt.Key_Less] = "Comma"; m[Qt.Key_Period] = "Period"; m[Qt.Key_Greater] = "Period";
        m[Qt.Key_Slash] = "Slash"; m[Qt.Key_Question] = "Slash";
        m[Qt.Key_Exclam] = "1"; m[Qt.Key_At] = "2"; m[Qt.Key_NumberSign] = "3"; m[Qt.Key_Dollar] = "4";
        m[Qt.Key_Percent] = "5"; m[Qt.Key_AsciiCircum] = "6"; m[Qt.Key_Ampersand] = "7"; m[Qt.Key_Asterisk] = "8";
        m[Qt.Key_ParenLeft] = "9"; m[Qt.Key_ParenRight] = "0";
        m[Qt.Key_VolumeUp] = "XF86AudioRaiseVolume"; m[Qt.Key_VolumeDown] = "XF86AudioLowerVolume";
        m[Qt.Key_VolumeMute] = "XF86AudioMute"; m[Qt.Key_MediaPlay] = "XF86AudioPlay"; m[Qt.Key_MediaTogglePlayPause] = "XF86AudioPlay";
        m[Qt.Key_MediaNext] = "XF86AudioNext"; m[Qt.Key_MediaPrevious] = "XF86AudioPrev"; m[Qt.Key_MediaStop] = "XF86AudioStop";
        m[Qt.Key_MonBrightnessUp] = "XF86MonBrightnessUp"; m[Qt.Key_MonBrightnessDown] = "XF86MonBrightnessDown";
        m[Qt.Key_PowerOff] = "XF86PowerOff"; m[Qt.Key_Calculator] = "XF86Calculator";
        return m;
    }
    function comboFromEvent(ev) {
        const k = ev.key;
        if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R,
             Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_Hyper_L, Qt.Key_Hyper_R].indexOf(k) >= 0) return "";
        let name = root.qtKeys[k] || "";
        if (!name && k >= Qt.Key_A && k <= Qt.Key_Z) name = String.fromCharCode(k);
        if (!name && k >= Qt.Key_0 && k <= Qt.Key_9) name = String.fromCharCode(k);
        if (!name && k >= Qt.Key_F1 && k <= Qt.Key_F35) name = "F" + (k - Qt.Key_F1 + 1);
        if (!name && ev.text && ev.text.length === 1 && ev.text.trim() !== "") name = ev.text.toUpperCase();
        if (!name) return "";
        const mods = [];
        if (ev.modifiers & Qt.MetaModifier) mods.push("Mod");
        if (ev.modifiers & Qt.ControlModifier) mods.push("Ctrl");
        if (ev.modifiers & Qt.AltModifier) mods.push("Alt");
        if (ev.modifiers & Qt.ShiftModifier) mods.push("Shift");
        return mods.concat([name]).join("+");
    }

    // --- actions, in plain language ---
    // For the "add a shortcut" picker and for naming binds without a title.
    readonly property var actionChoices: [
        { value: "close-window", label: "Close the window", group: "Windows" },
        { value: "fullscreen-window", label: "Full screen", group: "Windows" },
        { value: "maximize-window-to-edges", label: "Maximize the window", group: "Windows" },
        { value: "minimize-window", label: "Minimize the window", group: "Windows" },
        { value: "restore-window", label: "Bring back the last minimized window", group: "Windows" },
        { value: "toggle-window-floating", label: "Dock or undock the window", group: "Windows" },
        { value: "center-window", label: "Center the window", group: "Windows" },
        { value: "focus-tab-next", label: "Next tab", group: "Windows" },
        { value: "focus-tab-prev", label: "Previous tab", group: "Windows" },
        { value: "focus-column-left", label: "Focus the window on the left", group: "Windows" },
        { value: "focus-column-right", label: "Focus the window on the right", group: "Windows" },
        { value: "focus-window-up", label: "Focus the window above", group: "Windows" },
        { value: "focus-window-down", label: "Focus the window below", group: "Windows" },
        { value: "move-column-left", label: "Move the window left", group: "Windows" },
        { value: "move-column-right", label: "Move the window right", group: "Windows" },
        { value: "move-window-up", label: "Move the window up", group: "Windows" },
        { value: "move-window-down", label: "Move the window down", group: "Windows" },
        { value: "move-window-to-zone 1", label: "Snap the window into zone 1", group: "Windows" },
        { value: "move-window-to-zone 2", label: "Snap the window into zone 2", group: "Windows" },
        { value: "move-window-to-zone 3", label: "Snap the window into zone 3", group: "Windows" },
        { value: "move-window-to-zone 4", label: "Snap the window into zone 4", group: "Windows" },
        { value: "move-window-to-zone 5", label: "Snap the window into zone 5", group: "Windows" },
        { value: "move-window-to-zone 6", label: "Snap the window into zone 6", group: "Windows" },
        { value: "move-window-to-zone 7", label: "Snap the window into zone 7", group: "Windows" },
        { value: "move-window-to-zone 8", label: "Snap the window into zone 8", group: "Windows" },
        { value: "move-window-to-zone 9", label: "Snap the window into zone 9", group: "Windows" },
        { value: "spawn \"hearth-ipc\" \"call\" \"zones\" \"nextLayout\"", label: "Next zone layout", group: "Windows" },
        { value: "spawn \"hearth-ipc\" \"call\" \"zones\" \"prevLayout\"", label: "Previous zone layout", group: "Windows" },
        { value: "spawn \"hearth-ipc\" \"call\" \"zones\" \"toggleOverlay\"", label: "Show the window zones", group: "Windows" },
        { value: "toggle-overview", label: "Overview (Mission Control)", group: "Workspaces & Overview" },
        { value: "focus-workspace-up", label: "Previous workspace", group: "Workspaces & Overview" },
        { value: "focus-workspace-down", label: "Next workspace", group: "Workspaces & Overview" },
        { value: "move-window-to-workspace-up", label: "Move the window to the previous workspace", group: "Workspaces & Overview" },
        { value: "move-window-to-workspace-down", label: "Move the window to the next workspace", group: "Workspaces & Overview" },
        { value: "camera-zoom-out", label: "Zoom out (camera)", group: "Workspaces & Overview" },
        { value: "camera-zoom-in", label: "Zoom in (camera)", group: "Workspaces & Overview" },
        { value: "camera-show-all", label: "Show all docked windows", group: "Workspaces & Overview" },
        { value: "camera-frame-window", label: "Frame this window", group: "Workspaces & Overview" },
        { value: "spawn \"hearth-ipc\" \"call\" \"screenshot\" \"printKey\"", label: "Screenshot tool (what Print does in Settings)", group: "Screenshots" },
        { value: "spawn \"hearth-ipc\" \"call\" \"screenshot\" \"open\"", label: "Screenshot tool: region, window or screen", group: "Screenshots" },
        { value: "spawn \"hearth-ipc\" \"call\" \"screenshot\" \"region\"", label: "Screenshot of a region", group: "Screenshots" },
        { value: "spawn \"hearth-ipc\" \"call\" \"screenshot\" \"screen\"", label: "Screenshot of the whole screen", group: "Screenshots" },
        { value: "spawn \"hearth-ipc\" \"call\" \"screenshot\" \"all\"", label: "Screenshot of all screens", group: "Screenshots" },
        { value: "spawn \"hearth-ipc\" \"call\" \"screenshot\" \"activeWindow\"", label: "Screenshot of the active window", group: "Screenshots" },
        { value: "spawn \"hearth-ipc\" \"call\" \"screenshot\" \"record\"", label: "Record the screen (again: stop)", group: "Screenshots" },
        { value: "zoom-in", label: "Zoom the screen in (magnifier)", group: "Accessibility" },
        { value: "zoom-out", label: "Zoom the screen out", group: "Accessibility" },
        { value: "zoom-reset", label: "Turn screen zoom off", group: "Accessibility" },
        { value: "toggle-reduce-motion", label: "Reduce motion (animations off) on/off", group: "Accessibility" },
        { value: "screenshot", label: "arbor's quick region screenshot (to the clipboard)", group: "Screenshots" },
        { value: "screenshot-screen", label: "arbor's quick screen screenshot", group: "Screenshots" },
        { value: "screenshot-window", label: "arbor's quick window screenshot", group: "Screenshots" },
        { value: "spawn \"hearth-ipc\" \"call\" \"session\" \"lock\"", label: "Lock the screen", group: "System" },
        { value: "spawn \"hearth-ipc\" \"call\" \"session\" \"open\"", label: "Log out, restart or shut down", group: "System" },
        { value: "spawn \"hearth-ipc\" \"call\" \"settings\" \"open\"", label: "Open hearth Settings", group: "System" },
        { value: "spawn \"hearth-ipc\" \"call\" \"help\" \"shortcuts\"", label: "Show keyboard shortcuts", group: "System" },
        { value: "spawn \"hearth-ipc\" \"call\" \"spotlight\" \"toggle\"", label: "Spotlight search", group: "Apps & Launcher" },
        { value: "spawn \"hearth-ipc\" \"call\" \"voice\" \"toggle\"", label: "Voice assistant (start/stop listening)", group: "Apps & Launcher" },
        { value: "spawn \"vicinae\" \"toggle\"", label: "Search apps (launcher)", group: "Apps & Launcher" },
        { value: "spawn \"swaync-client\" \"-t\" \"-sw\"", label: "Notification Center", group: "System" },
        { value: "power-off-monitors", label: "Turn the displays off", group: "System" },
        { value: "show-hotkey-overlay", label: "arbor's shortcut list", group: "System" }
    ]
    function groupFor(action) {
        const a = action.toLowerCase();
        if (/screenshot/.test(a)) return "Screenshots";
        if (/workspace|overview|monitor|camera/.test(a)) return "Workspaces & Overview";
        if (/wpctl|playerctl|brightness|volume/.test(a)) return "Sound, Media & Brightness";
        if (/^zoom-|reduce-motion/.test(a)) return "Accessibility";
        if (/session|quit|power|lock|hotkey|inhibit|help|settings/.test(a)) return "System";
        if (/spawn|launch/.test(a)) return "Apps & Launcher";
        return "Windows";
    }
    function describeAction(action) {
        const c = root.actionChoices.find(x => x.value === action);
        if (c) return c.label;
        const m = action.match(/^spawn(?:-sh)?\s+(.*)$/);
        if (m) {
            const args = (m[1].match(/"((?:[^"\\]|\\.)*)"/g) || []).map(s => s.slice(1, -1));
            if (args[0] === "hearth-ipc" && args[1] === "call") return "hearth: " + args.slice(2).join(" ");
            if (/^spawn-sh/.test(action)) return "Run: " + (args[0] || m[1]);
            return "Open " + (args[0] || m[1]).split("/").pop() + (args.length > 1 ? " " + args.slice(1).join(" ") : "");
        }
        const s = action.replace(/;$/, "").replace(/-/g, " ");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
    function titleOf(props, action) {
        const t = (props || "").match(/hotkey-overlay-title="((?:[^"\\]|\\.)*)"/);
        return t ? t[1] : describeAction(action);
    }

    // --- parsing arbor's config ---
    function parse(text) {
        const out = [];
        const re = /^\s*binds\s*\{/gm;
        let m;
        while ((m = re.exec(text))) {
            let i = re.lastIndex, depth = 1, body = "";
            for (; i < text.length && depth > 0; i++) {
                const c = text[i];
                if (c === "\n") { body += c; continue; }
                if (c === "/" && text[i + 1] === "/") { while (i < text.length && text[i] !== "\n") i++; body += "\n"; continue; }
                if (c === '"') {          // strings may contain braces
                    let j = i + 1;
                    while (j < text.length && text[j] !== '"') { if (text[j] === "\\") j++; j++; }
                    body += text.slice(i, j + 1);
                    i = j;
                    continue;
                }
                if (c === "{") depth++;
                if (c === "}") { depth--; if (depth === 0) break; }
                body += c;
            }
            // Each bind: KEY props { action; }
            const bre = /([A-Za-z0-9_+]+)([^{}\n]*)\{([^{}]*)\}/g;
            let b;
            while ((b = bre.exec(body))) {
                out.push({ key: b[1], props: b[2].trim(), action: b[3].trim().replace(/;\s*$/, "").trim() });
            }
        }
        return out;
    }
    FileView {
        path: Compositor.isArbor ? root.arborConfig : ""
        blockLoading: false
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.defaults = root.parse(text())
    }

    // --- the effective list ---
    function overrideFor(key) {
        const n = norm(key);
        for (const k in root.overrides) if (norm(k) === n) return { key: k, value: root.overrides[k] };
        return null;
    }
    readonly property var effective: {
        const out = [];
        const used = new Set();
        for (const d of root.defaults) {
            const o = overrideFor(d.key);
            if (o) used.add(o.key);
            const v = o ? o.value : null;
            const off = !!(v && v.off);
            const action = v && !off ? v.action : d.action;
            const props = v && !off ? (v.props || "") : d.props;
            out.push({ key: d.key, action: action, props: props, title: titleOf(props, action), group: groupFor(action),
                       source: v ? "changed" : "default", off: off, defaultAction: d.action, defaultProps: d.props });
        }
        for (const k in root.overrides) {
            if (used.has(k)) continue;
            const v = root.overrides[k];
            if (v.off) continue;
            out.push({ key: k, action: v.action, props: v.props || "", title: titleOf(v.props, v.action),
                       group: groupFor(v.action), source: "added", off: false });
        }
        return out;
    }
    // For Help: [{ group, title, keys }].
    readonly property var helpList: root.effective.filter(e => !e.off && !/hotkey-overlay-title=null/.test(e.props))
        .map(e => ({ group: e.group, title: e.title, keys: pretty(e.key) }))

    function conflict(key, exceptKey) {
        const n = norm(key);
        const ex = exceptKey ? norm(exceptKey) : "";
        for (const e of root.effective) if (!e.off && norm(e.key) === n && norm(e.key) !== ex) return { kind: "bind", title: e.title, key: e.key };
        for (const g of root.globals) if (g.trigger && norm(g.trigger) === n) return { kind: "app", title: `${g.description || g.id} (${g.app_id || "an app"})`, key: g.trigger };
        return null;
    }

    function setOverrides(o) { Settings.set("binds", o); }
    function withOverride(o, key, value) {
        const existing = Object.keys(o).find(k => norm(k) === norm(key));
        if (existing) delete o[existing];
        if (value !== undefined) o[key] = value;
        return o;
    }
    // Move a shortcut to new keys. `replace`: a bind already on those keys
    // gets turned off first (it's replaced anyway: same keys).
    function changeKeys(e, newKey) {
        let o = Object.assign({}, root.overrides);
        if (e.source === "added") o = withOverride(o, e.key, undefined);
        else o = withOverride(o, e.key, { off: true });
        const d = root.defaults.find(x => norm(x.key) === norm(newKey));
        if (d && d.action === e.action) o = withOverride(o, newKey, undefined);     // back to its default
        else o = withOverride(o, newKey, { action: e.action, props: e.props || "" });
        setOverrides(o);
    }
    function turnOff(e) {
        let o = Object.assign({}, root.overrides);
        o = withOverride(o, e.key, e.source === "added" ? undefined : { off: true });
        setOverrides(o);
    }
    function resetBind(e) { setOverrides(withOverride(Object.assign({}, root.overrides), e.key, undefined)); }
    function resetAll() { Settings.reset("binds"); }
    function addBind(key, action, title) {
        const props = title ? `hotkey-overlay-title=${ArborConfig.str(title)}` : "";
        setOverrides(withOverride(Object.assign({}, root.overrides), key, { action: action, props: props }));
    }

    readonly property string kdl: {
        const lines = ["// Written by hearth (Settings > Keyboard Shortcuts). Changes here are replaced.", "binds {"];
        for (const k of Object.keys(root.overrides).sort()) {
            const v = root.overrides[k];
            if (v.off) lines.push(`    ${k} hotkey-overlay-title=null { spawn "true"; }`);
            else lines.push(`    ${k}${v.props ? " " + v.props : ""} { ${v.action}; }`);
        }
        lines.push("}");
        return lines.join("\n");
    }
    property string error: ""
    onKdlChanged: if (Compositor.isArbor && Settings.loaded && Settings.data.binds !== undefined) writeSoon.restart()
    Timer {
        id: writeSoon
        interval: 300
        onTriggered: ArborConfig.write("arbor-binds.kdl", root.kdl, (ok, err) => root.error = err)
    }

    // --- app shortcuts (GlobalShortcuts portal, arbor IPC) ---
    property bool globalSupported: false
    property var globals: []
    property string globalError: ""
    function refreshGlobals() {
        Compositor.arborRequest("GlobalShortcuts", r => {
            if (r.Ok && r.Ok.GlobalShortcuts !== undefined) {
                root.globalSupported = true;
                root.globals = r.Ok.GlobalShortcuts;
            } else {
                root.globalSupported = false;
                root.globals = [];
            }
        });
    }
    function setGlobal(g, trigger) {
        Compositor.arborRequest({ SetGlobalShortcut: { app_id: g.app_id, id: g.id, trigger: trigger || null } }, r => {
            root.globalError = r.Err !== undefined ? "arbor couldn't change that app shortcut: " + r.Err : "";
            root.refreshGlobals();
        });
    }
    Component.onCompleted: if (Compositor.isArbor) refreshGlobals()
}
