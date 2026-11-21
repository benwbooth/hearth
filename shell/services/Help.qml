pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Everything the Help menu can find: keyboard shortcuts, trackpad
// gestures, settings and actions, each with a plain-language title.
//
// Shortcuts: on arbor they are read from the user's arbor config
// (~/.config/arbor/config.kdl `binds { ... }`: a bind's hotkey-overlay-title
// or, failing that, its action); on Hyprland they are hearth's own binds
// (hypr/hyprland.lua), listed here.
//
//   hearth-ipc call help shortcuts | gestures | windows | welcome | search TEXT
Singleton {
    id: root

    // { title, keys, group }   groups: Windows, Workspaces & Overview,
    // Apps & Launcher, Screenshots, System
    readonly property var hyprShortcuts: [
        { group: "Apps & Launcher", title: "Search apps, files and more", keys: "Super (tap), Alt+Space" },
        { group: "Apps & Launcher", title: "Open the Nth app in the Dock", keys: "Super+1 … Super+9" },
        { group: "Apps & Launcher", title: "Clipboard history: copy something you copied earlier", keys: "Super+V" },
        { group: "Apps & Launcher", title: "Vicinae's clipboard history (search with previews)", keys: "Super+Shift+V" },
        { group: "Apps & Launcher", title: "Dock app options: hide, move to workspace, keep in Dock, open at login, force quit", keys: "Right-click an app in the Dock" },
        { group: "Apps & Launcher", title: "Reorder or remove Dock apps", keys: "Drag an icon along the Dock, or out of it" },
        { group: "Windows", title: "Close window", keys: "Alt+F4" },
        { group: "Windows", title: "Force quit window", keys: "Super+Ctrl+Esc" },
        { group: "Windows", title: "Maximize window", keys: "Super+Page Up" },
        { group: "Windows", title: "Full screen", keys: "Super+F" },
        { group: "Windows", title: "Minimize window", keys: "Super+Page Down" },
        { group: "Windows", title: "Show minimized windows", keys: "Super+Shift+Page Down" },
        { group: "Windows", title: "Float or tile window", keys: "Super+T" },
        { group: "Windows", title: "Move window left / right / up / down", keys: "Super+Arrows" },
        { group: "Windows", title: "Focus window left / right / up / down", keys: "Super+Alt+Arrows" },
        { group: "Windows", title: "Switch windows", keys: "Alt+Tab, Super+Tab" },
        { group: "Windows", title: "Switch windows of this app", keys: "Alt+`" },
        { group: "Windows", title: "Move window with the mouse", keys: "Super+drag" },
        { group: "Windows", title: "Resize window with the mouse", keys: "Super+right-drag" },
        { group: "Windows", title: "Snap window into a zone", keys: "Super+Ctrl+1 … 9, or hold Shift while dragging" },
        { group: "Workspaces & Overview", title: "Overview of all windows", keys: "Super+W, Super+G" },
        { group: "Workspaces & Overview", title: "Show desktop", keys: "Super+D" },
        { group: "Workspaces & Overview", title: "Go to workspace 1 … 4", keys: "Ctrl+F1 … F4" },
        { group: "Workspaces & Overview", title: "Previous / next workspace", keys: "Super+Ctrl+Left / Right" },
        { group: "Workspaces & Overview", title: "Move window to previous / next workspace", keys: "Super+Ctrl+Shift+Left / Right" },
        { group: "Workspaces & Overview", title: "Zoom in / out / reset", keys: "Super+= / Super+- / Super+0" },
        { group: "Screenshots", title: "Screenshot tool: pick a region, window or screen, then copy, save or mark it up", keys: "Print" },
        { group: "Screenshots", title: "Screenshot a region", keys: "Super+Shift+S" },
        { group: "Screenshots", title: "Copy a region to the clipboard", keys: "Ctrl+Print" },
        { group: "System", title: "Lock screen", keys: "Super+L" },
        { group: "System", title: "Log out, restart or shut down", keys: "Ctrl+Alt+Delete" },
        { group: "System", title: "Keyboard shortcuts (this list)", keys: "Super+/" },
        { group: "Menus", title: "Move through an open menu; Left/Right go to the next menu or into a submenu", keys: "Arrow keys" },
        { group: "Menus", title: "Choose the selected menu item", keys: "Return, Space" },
        { group: "Menus", title: "Close the menu (or the submenu)", keys: "Esc" },
        { group: "Menus", title: "Jump to the menu item starting with a letter", keys: "Type the letter" },
        { group: "Menus", title: "Choose from a menu in one go", keys: "Press a menu title, drag to the item, release" }
    ]

    readonly property var gestures: [
        { title: "Open the overview (all windows)", keys: "Swipe up with 3 or 4 fingers" },
        { title: "Close the overview", keys: "Swipe down with 3 or 4 fingers" },
        { title: "Switch workspace", keys: "Swipe left or right with 3 or 4 fingers" },
        { title: "Scroll", keys: "Two fingers up or down" },
        { title: "Right-click", keys: "Tap with two fingers" }
    ]

    // arbor binds parsed from the config.
    property var arborShortcuts: []
    // Built into arbor (its window switcher), so not in the config's binds.
    readonly property var arborBuiltins: [
        { group: "Windows", title: "Switch windows (hold Alt, press Tab again to go further)", keys: "Alt+Tab, Super+Tab" },
        { group: "Windows", title: "Switch back the other way", keys: "Alt+Shift+Tab" },
        { group: "Windows", title: "Switch between windows of the same app", keys: "Alt+`" }
    ]
    // arbor: the effective binds (config + Settings > Keyboard Shortcuts).
    readonly property var arborList: Binds.helpList.length ? Binds.helpList : arborShortcuts
    readonly property var shortcuts: Compositor.isArbor && arborList.length ? arborBuiltins.concat(arborList) : hyprShortcuts

    // Settings and actions the search can open or run.
    readonly property var actions: [
        { title: "Lock screen", keys: "Super+L", run: () => Session.run("lock") },
        { title: "Sleep", run: () => Session.run("suspend") },
        { title: "Restart…", run: () => Session.run("reboot") },
        { title: "Shut down…", run: () => Session.run("poweroff") },
        { title: "Log out…", run: () => Session.run("logout") },
        { title: "Take a screenshot: region, window, screen or all screens (Spectacle)", keys: "Print", run: () => Screenshots.overlayRequested("") },
        { title: "Screenshot of the whole screen", keys: "Shift+Print", run: () => Screenshots.captureScreen() },
        { title: "Screenshot of the active window", keys: "Super+Print, Alt+Print", run: () => Screenshots.captureActiveWindow() },
        { title: "Screenshot of a region", keys: "Super+Shift+Print, Super+Shift+S", run: () => Screenshots.overlayRequested("region") },
        { title: "Record the screen, a window or a region (video); stop from the menu bar", keys: "Super+Shift+R", run: () => Screenshots.overlayRequested("record") },
        { title: "Screenshot tool: drag a region, handles resize, arrows nudge (Shift resizes), Enter takes it, Esc cancels; R W S A switch mode", keys: "Print" },
        { title: "Screenshot window: mark up with arrows, boxes, text, numbers, blur; Ctrl+C copies, Ctrl+S saves, drag the picture into an app", keys: "Ctrl+C, Ctrl+S, Ctrl+Z" },
        { title: "Settings: screenshots: what Print does, folder, file name, format, copy/save right away, pointer, window shadow, recordings", pane: "screenshots" },
        { title: "Search apps", keys: "Alt+Space", run: () => Quickshell.execDetached(["vicinae", "toggle"]) },
        { title: "Show all windows (overview)", keys: "Super+W", run: () => ShellState.overviewRequested() },
        { title: "Control Center: Wi-Fi, Bluetooth, Focus, Dark Mode, brightness, sound, now playing", run: () => ShellState.openIndicator("controlcenter") },
        { title: "Use menus with the keyboard: arrows, Return, Esc, type a letter", keys: "↑ ↓ ← → ↩ ⎋", guide: "shortcuts" },
        { title: "Choose from a menu in one go: press a title, drag, release", guide: "shortcuts" },
        { title: "Settings: pointer (macOS-style or Breeze)", pane: "appearance" },
        { title: "Settings: monochrome menu bar icons, menu bar style", pane: "menubar" },
        { title: "Settings: Dock show delay, hide delay, slide animation", pane: "dock" },
        { title: "Settings: appearance, light/dark mode, accent colour", pane: "appearance" },
        { title: "Settings: transparency and blur", pane: "appearance" },
        { title: "Settings: menu bar, clock, logo", pane: "menubar" },
        { title: "Settings: Dock size, magnification, position, hiding", pane: "dock" },
        { title: "Settings: switch between Mac layout and classic panel", pane: "layout" },
        { title: "Settings: wallpaper: pictures of the day (Bing, NASA, Wikimedia, Spotlight, Earth View…), dynamic, video, shaders, Wallpaper Engine, slideshows", pane: "wallpaper" },
        { title: "Settings: wallpaper fit, smart crop, per display, lock screen and login screen picture", pane: "wallpaper" },
        { title: "Settings: animated wallpaper: still image only, frame rate, pause when covered, full screen, on battery", pane: "wallpaper" },
        { title: "Settings: wallpaper from the web: Wallhaven, Reddit, Unsplash, Pexels, Flickr (API keys)", pane: "wallpaper" },
        { title: "Next wallpaper (picture of the day or slideshow)", run: () => Wallpaper.next("") },
        { title: "Previous wallpaper (earlier picture of the day)", run: () => Wallpaper.previous("") },
        { title: "About this wallpaper: title, credit, save a copy", run: () => Wallpaper.infoRequested() },
        { title: "Settings: night light", pane: "night" },
        { title: "Settings: notifications, Do Not Disturb", pane: "notifications" },
        { title: "Clipboard history: copy something you copied earlier (paste, Klipper)", keys: "Super+V", run: () => Clipboard.toggleRequested() },
        { title: "Clipboard: in the history, ↑ ↓ choose, Return copies, Delete removes, Ctrl+P pins, Ctrl+E edits, Ctrl+O opens a link", keys: "Super+V", run: () => Clipboard.toggleRequested() },
        { title: "Settings: clipboard history size, pictures, passwords, apps to ignore, clear on logout", pane: "clipboard" },
        { title: "Settings: displays: resolution, refresh rate, scale, arrangement, rotation, HDR, adaptive sync", pane: "displays" },
        { title: "Settings: keyboard layouts, key repeat, Num Lock", pane: "keyboard" },
        { title: "Settings: change keyboard shortcuts, add your own, app shortcuts", pane: "shortcuts" },
        { title: "Settings: window rules: open an app docked or floating, on a workspace, size, title bar, opacity", pane: "windowrules" },
        { title: "Settings: hot corners (Mission Control, Show Desktop, Lock Screen… from a screen corner)", pane: "hotcorners" },
        { title: "Settings: sleep, screen off and lock times, password after sleep, power button", pane: "power" },
        { title: "Settings: users & accounts: your picture (login and lock screen avatar, photo, webcam, monogram) and full name", pane: "users" },
        { title: "Settings: lock screen: require password after, fingerprint, clock and date, now playing, notifications, animated wallpaper, screen off", pane: "lockscreen" },
        { title: "Lock screen: type your password (any key or click shows the field), Return unlocks, Esc clears; or touch the fingerprint reader", keys: "Super+L" },
        { title: "Lock screen stuck (hearth crashed while locked)? Ctrl+Alt+F2, log in, run hearth-recover-lock, then switch back", keys: "Ctrl+Alt+F2" },
        { title: "Keyboard shortcuts", keys: "Super+/", guide: "shortcuts" },
        { title: "Trackpad gestures", guide: "gestures" },
        { title: "How windows work", guide: "windows" },
        { title: "Getting started", guide: "welcome" }
    ]

    // Search everything: [{ title, keys, kind, item }].
    function search(text) {
        const q = text.trim().toLowerCase();
        if (!q) return [];
        const words = q.split(/\s+/);
        const hit = s => words.every(w => s.toLowerCase().includes(w));
        const out = [];
        for (const a of actions) if (hit(a.title + " " + (a.keys || ""))) out.push({ title: a.title, keys: a.keys || "", kind: "action", item: a });
        const seen = new Set(out.map(r => r.title.toLowerCase()));
        for (const s of shortcuts)
            if (hit(s.title + " " + s.keys + " " + s.group) && !seen.has(s.title.toLowerCase()))
                out.push({ title: s.title, keys: s.keys, kind: "shortcut", item: s });
        for (const g of gestures) if (hit(g.title + " " + g.keys + " gesture trackpad")) out.push({ title: g.title, keys: g.keys, kind: "gesture", item: g });
        return out.slice(0, 12);
    }

    // Run a search result: an action runs, a setting opens its pane, a
    // shortcut or gesture opens the cheat sheet on it.
    function activate(r) {
        const a = r.item;
        if (r.kind === "action") {
            if (a.run) a.run();
            else if (a.pane) Settings.openRequested(a.pane);
            else if (a.guide) root.guideRequested(a.guide, "");
        } else {
            root.guideRequested(r.kind === "gesture" ? "gestures" : "shortcuts", r.title);
        }
    }

    // The Help window: page ("shortcuts", "gestures", "windows", "welcome")
    // and an optional search to pre-fill.
    signal guideRequested(string page, string query)

    IpcHandler {
        target: "help"
        function shortcuts(): void { root.guideRequested("shortcuts", ""); }
        function gestures(): void { root.guideRequested("gestures", ""); }
        function windows(): void { root.guideRequested("windows", ""); }
        function welcome(): void { root.guideRequested("welcome", ""); }
        function search(text: string): string { return JSON.stringify(root.search(text).map(r => [r.title, r.keys])); }
    }

    // --- arbor config ---
    readonly property string arborConfig: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/arbor/config.kdl"

    function groupFor(action) {
        const a = action.toLowerCase();
        if (/screenshot/.test(a)) return "Screenshots";
        if (/^zoom-|reduce-motion/.test(a)) return "Accessibility";
        if (/workspace|overview|monitor/.test(a)) return "Workspaces & Overview";
        if (/spawn|launch/.test(a)) return "Apps & Launcher";
        if (/quit|power|lock|session|hotkey|inhibit/.test(a)) return "System";
        return "Windows";
    }
    function humanAction(action) {
        // "focus-column-left" -> "Focus column left"; spawn "x" -> "Run x"
        const m = action.match(/^spawn(?:-sh)?\s+(.*)$/);
        if (m) return "Run " + m[1].replace(/"/g, "").split(" ")[0].split("/").pop();
        const s = action.split(/\s+/)[0].replace(/-/g, " ");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
    function parseArbor(text) {
        const out = [];
        const start = text.search(/^\s*binds\s*\{/m);
        if (start < 0) return out;
        let depth = 0, i = text.indexOf("{", start), body = "";
        for (; i < text.length; i++) {
            const c = text[i];
            if (c === "{") { depth++; if (depth === 1) continue; }
            if (c === "}") { depth--; if (depth === 0) break; }
            body += c;
        }
        for (const raw of body.split("\n")) {
            const line = raw.replace(/\/\/.*$/, "").trim();
            const m = line.match(/^([A-Za-z0-9_+]+)\s*(.*?)\{\s*(.*?);?\s*\}/);
            if (!m) continue;
            const keys = m[1].replace(/Mod\+/, "Super+").replace(/\+/g, "+");
            const props = m[2];
            const action = m[3].trim();
            const t = props.match(/hotkey-overlay-title="([^"]*)"/);
            if (/hotkey-overlay-title=null/.test(props)) continue;
            const title = t ? t[1] : humanAction(action);
            out.push({ group: groupFor(action), title: title, keys: keys });
        }
        return out;
    }

    FileView {
        path: Compositor.isArbor ? root.arborConfig : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.arborShortcuts = root.parseArbor(text())
    }
}
