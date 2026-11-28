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
        { group: "Apps & Launcher", title: "Search: apps, files, settings; calculate", keys: "Super+Space" },
        { group: "Apps & Launcher", title: "Voice assistant", keys: "Super+Alt+Space" },
        { group: "Apps & Launcher", title: "Search apps, files and more (Vicinae)", keys: "Super (tap), Alt+Space" },
        { group: "Apps & Launcher", title: "Open the Nth app in the Dock", keys: "Super+1 … Super+9" },
        { group: "Apps & Launcher", title: "Clipboard history: copy something you copied earlier", keys: "Super+V" },
        { group: "Apps & Launcher", title: "Vicinae's clipboard history (search with previews)", keys: "Super+Shift+V" },
        { group: "Apps & Launcher", title: "Dock app options: new window, hide, move to workspace, keep in Dock / remove from Dock, open at login, show in Files, assign to a workspace, quit", keys: "Right-click an app in the Dock" },
        { group: "Apps & Launcher", title: "Reorder or remove Dock apps", keys: "Drag an icon along the Dock, or out of it until it says Remove" },
        { group: "Apps & Launcher", title: "Launchpad: all apps in a full-screen grid", keys: "F4" },
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
        { group: "Windows", title: "Next / previous zone layout", keys: "Super+Ctrl+PgDn, Super+Ctrl+PgUp" },
        { group: "Workspaces & Overview", title: "Overview of all windows", keys: "Tap Super, or Super+W, Super+G" },
        { group: "Workspaces & Overview", title: "Show desktop", keys: "Super+D" },
        { group: "Workspaces & Overview", title: "Go to workspace 1 … 4", keys: "Ctrl+F1 … F4" },
        { group: "Workspaces & Overview", title: "Previous / next workspace", keys: "Super+Ctrl+Left / Right" },
        { group: "Workspaces & Overview", title: "Move window to previous / next workspace", keys: "Super+Ctrl+Shift+Left / Right" },
        { group: "Workspaces & Overview", title: "Move window to workspace 1 … 9", keys: "Ctrl+Shift+F1 … F9" },
        { group: "Workspaces & Overview", title: "Move a window to another workspace with the mouse: drag it onto that workspace in the overview (the empty one at the end makes a new workspace)", keys: "Super+W, drag" },
        { group: "Windows", title: "Camera back / forward", keys: "Super+Ctrl+Up / Down" },
        { group: "Workspaces & Overview", title: "Workspace map in the menu bar: click a workspace to go there, drag a window onto another", keys: "Click / drag" },
        { group: "Workspaces & Overview", title: "App icons in the menu bar (tray): click to bring the app's window to the front, click again to minimize it; right-click for its menu", keys: "Click" },
        { group: "Workspaces & Overview", title: "Zoom in / out / reset", keys: "Super+= / Super+- / Super+0" },
        { group: "Screenshots", title: "Screenshot tool: pick a region, window or screen; it is copied to the clipboard, then save or mark it up", keys: "Print" },
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
        { title: "Hibernate…: save everything to disk and power off; it all comes back when you turn the computer on (where the system supports it)", run: () => Session.request("hibernate") },
        { title: "Restart…", run: () => Session.request("reboot") },
        { title: "Shut down…", run: () => Session.request("poweroff") },
        { title: "Log out…", run: () => Session.request("logout") },
        { title: "Restart the window manager (arbor) without logging out: Qt/KDE apps stay open and in place, other apps (browsers, Electron, GTK) reopen, the menu bar restarts", run: () => Quickshell.execDetached(["arbor", "msg", "action", "reload-binary"]) },
        { title: "New arbor builds (devloop) switch in automatically the same way; to stop that: touch ~/.local/state/devloop/arbor/no-reload (delete the file to turn it back on)" },
        { title: "Window zones: snap the focused window into zone 1 … 9 (FancyZones)", keys: "Super+Ctrl+1 … 9" },
        { title: "Window zones: hold Shift while dragging a window to drop it into the zone under the pointer", keys: "Shift+drag" },
        { title: "Window zones: next zone layout (the tray's zones picker lists and edits them)", keys: "Super+Ctrl+PgDn", run: () => ArborZones.setLayout("", "next") },
        { title: "Window zones: previous zone layout", keys: "Super+Ctrl+PgUp", run: () => ArborZones.setLayout("", "prev") },
        { title: "Window zones: show the zones of this display", run: () => ArborZones.toggleOverlay() },
        { title: "Window zones: make or edit a zone layout (drag zones, resize by edges and corners, split, fill gaps, grid, snapping, undo)", run: () => ZoneEditor.edit(null, "") },
        { title: "Take a screenshot: region, window, screen or all screens (Spectacle)", keys: "Print", run: () => Screenshots.overlayRequested("") },
        { title: "Screenshot of the whole screen", keys: "Shift+Print", run: () => Screenshots.captureScreen() },
        { title: "Screenshot of the active window", keys: "Super+Print, Alt+Print", run: () => Screenshots.captureActiveWindow() },
        { title: "Screenshot of a region", keys: "Super+Shift+Print, Super+Shift+S", run: () => Screenshots.overlayRequested("region") },
        { title: "Record the screen, a window or a region (video); stop from the menu bar", keys: "Super+Shift+R", run: () => Screenshots.overlayRequested("record") },
        { title: "Screenshot tool: drag a region, handles resize, arrows nudge (Shift resizes), Enter takes it, Esc cancels; R W S A switch mode", keys: "Print" },
        { title: "Screenshot window: mark up with arrows, boxes, text, numbers, blur; Ctrl+C copies, Ctrl+S saves, drag the picture into an app", keys: "Ctrl+C, Ctrl+S, Ctrl+Z" },
        { title: "Settings: screenshots: what Print does, folder, file name, format, copy/save right away, pointer, window shadow, recordings", pane: "screenshots" },
        { title: "Search: apps, documents, folders, pictures, settings; calculate and convert units", keys: "Super+Space", run: () => Spotlight.toggle() },
        { title: "Search keys: ↑ ↓ choose, Tab or Ctrl+↑ Ctrl+↓ jump between groups, Enter opens, Ctrl+Enter shows the file in the file manager, Ctrl+C copies, Esc clears then closes", keys: "Super+Space", run: () => Spotlight.toggle() },
        { title: "Search words: kind:pdf, kind:image, kind:folder, date:today, date:yesterday, date:2026-11-20", keys: "Super+Space", run: () => Spotlight.toggle() },
        { title: "Calculator and conversions in Search: 2^10, 15% of 80, 5 ft to m, 72F in C, 100 USD in EUR (Return copies the result)", keys: "Super+Space", run: () => Spotlight.toggle() },
        { title: "Settings: Search: which folders are searched, what's left out (privacy), result groups, web suggestions, rebuild the index", pane: "spotlight" },
        { title: "Settings: Appearance: light or dark mode for the desktop and apps (Auto switches at 7:00 and 19:00), accent colour, glass", pane: "appearance" },
        { title: "Speak selected text: select text in any app and press the key to hear it read aloud (in Settings > Voice's voice); press again to stop. No need to copy: it reads what's selected (the middle-click selection). F13 does the same (a keyboard's spare key: keystone programs the Kinesis Game Bank keys to send it)", keys: "Alt+Esc", run: () => Voice.speakSelection() },
        { title: "Voice assistant (like Siri): press, speak, it stops when you stop talking: open apps and files, find documents, volume, weather, dark mode…", keys: "Super+Alt+Space", run: () => Voice.toggle() },
        { title: "Settings: voice assistant: shortcut, language, Whisper model, pause length, spoken replies (Piper voices), glowing edge, sounds", pane: "voice" },
        { title: "Assistant menu (the sparkle next to Control Center): ask by voice or by typing, the last answer, switch the assistant's model, see graphics memory (VRAM) and load or unload AI models", run: () => ShellState.openIndicator("ai") },
        { title: "AI models: GPU % and graphics memory %, which models are loaded and how much memory each takes, every installed model by category (language, speech to text, text to speech, image, video, audio, embeddings, vision), install more (Ollama, Magnitude, Hugging Face), unload or keep loaded", run: () => ShellState.openIndicator("ai") },
        { title: "Assistant can use the computer (read windows, click, type) and run terminal commands, asking first with Allow / Deny", pane: "ai" },
        { title: "Assistant can work in the Turbine editor (open files, type, menus) through Turbine's own tools, asking first", pane: "ai" },
        { title: "Settings: AI: unload unused models after a few minutes, make room for new requests by unloading idle models, GPU use in the menu bar", pane: "ai" },
        { title: "Settings: AI: Apps: let apps such as Tessera use hearth's models (an OpenAI-compatible server on this computer), their default and fast models", pane: "ai" },
        { title: "Settings: AI: installed and loaded models (Ollama, llama.cpp), download or delete models, the assistant's model, cloud AI (Claude Code, Codex, Gemini), unload when full screen", pane: "ai" },
        { title: "Search apps (Vicinae launcher)", keys: "Alt+Space", run: () => Quickshell.execDetached(["vicinae", "toggle"]) },
        { title: "Launchpad: every installed app in a full-screen grid, grouped (Internet, Office, Games…); type to search, Enter opens the first match", keys: "F4", run: () => Launchpad.show() },
        { title: "Launchpad keys: arrows choose, Enter opens, Page Up/Down scroll, Esc clears the search then closes", keys: "F4", run: () => Launchpad.show() },
        { title: "Add an app to the Dock: drag it from the Launchpad onto the Dock, or right-click it there for Add to Dock", run: () => Launchpad.show() },
        { title: "Remove an app from the Dock: drag it out of the Dock until it says Remove, or right-click it for Remove from Dock" },
        { title: "Settings: Launchpad: arrange apps by kind, by name, most used or in your own groups; icon size; Launchpad icon in the Dock", pane: "dock" },
        { title: "Launchpad: arrange apps by kind, by name, most used, or your own way (the button next to Search)", keys: "F4", run: () => Launchpad.show() },
        { title: "Launchpad: rearrange apps by dragging them between others or onto a group's title (switches to your own arrangement)", keys: "F4", run: () => Launchpad.show() },
        { title: "Launchpad groups: right-click a group's title to rename it, add a group or a subgroup, move it up or down, or delete it (its apps stay); click a title to fold it", keys: "Right-click", run: () => Launchpad.show() },
        { title: "Show all windows (overview)", keys: "Super+W", run: () => ShellState.overviewRequested() },
        { title: "Control Center: Wi-Fi, Bluetooth, Focus, Dark Mode, brightness, sound, now playing", run: () => ShellState.openIndicator("controlcenter") },
        { title: "Volume and brightness slider: appears at the top right when the level changes (keys, or scrolling on the menu bar item); drag or click it to set the level, scroll on it to step; it stays while the pointer is on it" },
        { title: "Volume chime: a pop on every volume change, so you hear the new level (turn off in Settings > Sound)", run: () => Settings.openRequested("sound") },
        { title: "Use menus with the keyboard: arrows, Enter, Esc, type a letter", keys: "↑ ↓ ← → Enter Esc", guide: "shortcuts" },
        { title: "Choose from a menu in one go: press a title, drag, release", guide: "shortcuts" },
        { title: "The app's own menus (File, Edit, View…) are in the menu bar, next to the app's name in bold (global menu: Qt, KDE, GTK, LibreOffice, Brave/Chrome; Electron and X11 apps when they run on X11)" },
        { title: "App-name menu: About, New Window, Close Window, Hide, Hide Others, Show All, Quit" },
        { title: "Window menu: Minimize, Zoom, Full Screen, Float, move to another workspace, switch between the app's windows" },
        { title: "Settings: pointer (macOS-style or Breeze)", pane: "appearance" },
        { title: "Settings: monochrome menu bar icons, menu bar style", pane: "menubar" },
        { title: "Rearrange the menu bar: hold Super and drag an item left or right (like Cmd-drag on a Mac); drag it below the bar to hide it", keys: "Super+drag" },
        { title: "Edit Menu Bar: drag menu bar items without holding Super, Done when finished", run: () => BarItems.editing = true },
        { title: "Menu bar item menu: right-click an item for Hide This Item, Show Only in the ⌃ Menu, Edit Menu Bar, Menu Bar Settings…", keys: "Right-click" },
        { title: "Settings: menu bar items: show, hide, reorder, only in the ⌃ menu; each treetop graph (CPU, memory, GPU, VRAM, disk, network, temperatures) as graph or number; workspace map size", pane: "menubar" },
        { title: "Show a hidden menu bar item again (weather, battery, workspace map, treetop graphs…)", pane: "menubar" },
        { title: "Settings: clock date and time format: 24-hour, seconds, date style (short, long, numeric, ISO) or your own format", run: () => BarItems.openSettings("clock") },
        { title: "Settings: Dock show delay, hide delay, slide animation", pane: "dock" },
        { title: "Settings: appearance, light/dark mode, accent colour", pane: "appearance" },
        { title: "Settings: transparency and blur", pane: "appearance" },
        { title: "Settings: menu bar, clock, logo, calendar from Almanac, next event", pane: "menubar" },
        { title: "Calendar: click the clock for this month, today's and tomorrow's events from Almanac; click a day for its events, an event to open it in Almanac" },
        { title: "New calendar event: click the clock, pick a day, New Event… (opens Almanac)", run: () => Calendar.newEvent(Calendar.today) },
        { title: "Menu bar too full (laptop, many app icons): what doesn't fit moves into the ⌃ menu at its right; choose what may move in Settings", pane: "menubar" },
        { title: "Settings: Dock size, magnification, position, hiding", pane: "dock" },
        { title: "Settings: Dock: minimize effect: Genie pours the window into the Dock (like macOS), Scale shrinks it, None; minimize into the app's icon", pane: "dock" },
        { title: "Settings: switch between Mac layout and classic panel", pane: "layout" },
        { title: "Settings: wallpaper: pictures of the day (Bing, NASA, Wikimedia, Spotlight, Earth View…), dynamic, video, shaders, Wallpaper Engine, slideshows", pane: "wallpaper" },
        { title: "Settings: wallpaper fit, smart crop, per display, lock screen and login screen picture", pane: "wallpaper" },
        { title: "Settings: animated wallpaper: still image only, frame rate, pause when covered, full screen, on battery", pane: "wallpaper" },
        { title: "Settings: wallpaper from the web: Wallhaven, Reddit, Unsplash, Pexels, Flickr (API keys)", pane: "wallpaper" },
        { title: "Next wallpaper (picture of the day or slideshow)", run: () => Wallpaper.next("") },
        { title: "Previous wallpaper (earlier picture of the day)", run: () => Wallpaper.previous("") },
        { title: "About this wallpaper: title, credit, save a copy", run: () => Wallpaper.infoRequested() },
        { title: "Settings: night light", pane: "night" },
        { title: "Settings: notifications, Do Not Disturb, banner time, urgent notifications, group by app", pane: "notifications" },
        { title: "Notification Center: your notifications, stacked by app (click the bell in the menu bar)", run: () => Notifications.openCenter() },
        { title: "Notification Center: click a stack to see all of an app's notifications; Show less stacks them again, ✕ clears them" },
        { title: "Notifications: click one to open it, hover and click ✕ to clear it, drag a banner to the right to put it away" },
        { title: "Do Not Disturb: turn banners off (middle-click the bell, or Control Center > Focus)", run: () => Notifications.toggleDnd() },
        { title: "Clear all notifications", run: () => Notifications.clearAll() },
        { title: "Send a test notification", run: () => Notifications.sendTest() },
        { title: "Clipboard history: copy something you copied earlier (paste, Klipper)", keys: "Super+V", run: () => Clipboard.toggleRequested() },
        { title: "Clipboard: in the history, ↑ ↓ choose, Return copies, Delete removes, Ctrl+P pins, Ctrl+E edits, Ctrl+O opens a link", keys: "Super+V", run: () => Clipboard.toggleRequested() },
        { title: "Settings: clipboard history size, pictures, passwords, apps to ignore, clear on logout", pane: "clipboard" },
        { title: "Settings: Bluetooth: turn it on or off, connect, disconnect or forget your devices, pair new headphones, keyboards and mice", pane: "bluetooth" },
        { title: "Settings: Printers: add a printer (found on the network, USB or by IP address; no driver needed for AirPrint / IPP Everywhere), make it the default, pause, remove, print queue, test page, paper size, two-sided, colour", pane: "printers" },
        { title: "Settings: Printers: add a printer by its IP address or host name, or pick a driver for an old printer", pane: "printers:add" },
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
        { title: "Settings: passwords & keys: see, copy, change or delete saved passwords, add one, lock the keyring, SSH key passphrases", pane: "passwords" },
        { title: "Saved passwords: unlock the keyring, change its password", guide: "passwords" },
        { title: "App requests: camera/location permission, Open With, print, share your name, add web app, dark mode in apps", guide: "requests" },
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
    readonly property string arborConfig: ArborConfig.mainConfig

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
