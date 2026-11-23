pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The menu bar's status items (right side), like macOS's menu bar and
// Control Center settings: one ordered list, left to right, of every item
// with where it shows and its options. Stored in settings.json as
// `menubar.items`: [{ id, show, canMove?, ...options }].
//   show: "bar"      in the menu bar (moves into the ⌃ menu when the bar
//                    is full, if canMove)
//         "overflow" only in the ⌃ menu at the right of the bar
//         "hidden"   nowhere
// bar/MenuBar.qml builds the bar from `list`; Settings > Menu Bar
// (popups/settings/MenuBarPane.qml) and the bar itself (Super-drag, right
// click, Edit Menu Bar) change it.
//
//   hearth-ipc call menubar items
//   hearth-ipc call menubar place weather hidden     (bar | overflow | hidden)
//   hearth-ipc call menubar move weather 0
//   hearth-ipc call menubar settings clock
//   hearth-ipc call menubar edit | done | reset
Singleton {
    id: root

    // Every item, in the default order. `dropdown`: it has a row for the ⌃
    // menu. `canMove`: may move into the ⌃ menu when the bar is full
    // (default). `opts`: its options with defaults (Settings > Menu Bar).
    // `when`: it only shows while something is true (a battery, the camera
    // in use...). `rightAction`: what its right click did before the item
    // menu took the right click (kept as the menu's first entry).
    readonly property var catalog: [
        { id: "workspaces", label: "Workspace map", icon: "view-grid", group: "Desktop",
          note: "A small map of each workspace and its windows. Click one to go there; drag a window's box onto another to move it.",
          dropdown: true, canMove: true, opts: { size: "full" } },
        { id: "treetop.cpu", label: "CPU graph", icon: "cpu", group: "treetop",
          note: "How busy the processor is, from treetop. Click to open treetop; hover for the busiest programs.",
          dropdown: true, canMove: true, opts: { style: "graph" } },
        { id: "treetop.mem", label: "Memory graph", icon: "media-flash", group: "treetop",
          note: "How much memory is in use.", dropdown: true, canMove: true, opts: { style: "graph" } },
        { id: "treetop.gpu", label: "GPU graph", icon: "video-display", group: "treetop",
          note: "How busy the graphics card is (each card in use gets its own graph).", dropdown: true, canMove: true, opts: { style: "graph" } },
        { id: "treetop.vram", label: "Graphics memory graph", icon: "video-display", group: "treetop",
          note: "How much of the graphics card's memory (VRAM) is in use.", dropdown: true, canMove: true, opts: { style: "graph" } },
        { id: "treetop.disk", label: "Disk space graph", icon: "drive-harddisk", group: "treetop",
          note: "How full the system drive is; hover for every drive.", dropdown: true, canMove: true, opts: { style: "graph" } },
        { id: "treetop.net", label: "Network speed", icon: "network-wired", group: "treetop",
          note: "Upload and download speed right now.", dropdown: true, canMove: true, opts: {} },
        { id: "treetop.temp", label: "Temperatures", icon: "temperature-normal", group: "treetop",
          note: "Processor and graphics card temperatures; hover for every sensor and fan.", dropdown: true, canMove: true, opts: {} },
        { id: "devapps", label: "Dev apps", icon: "run-build", group: "Apps",
          note: "Builds and deploys run by devloop. Shows only while devloop runs.", dropdown: true, canMove: true, opts: {}, when: "devloop is running" },
        { id: "trayicons", label: "App icons", icon: "preferences-desktop-notification", group: "Apps",
          note: "Icons apps put in the menu bar (Slack, Steam, Discord…). When the bar is full they move into the ⌃ menu first.",
          dropdown: true, canMove: true, opts: {} },
        { id: "recording", label: "Screen recording", icon: "media-record", group: "Status",
          note: "A red dot while the screen is being recorded; click to stop.", dropdown: true, canMove: true, opts: {}, when: "recording" },
        { id: "media", label: "Now Playing", icon: "media-playback-start", group: "Status",
          note: "The song or video playing, with play/pause and skip.", dropdown: true, canMove: true, opts: {}, when: "something plays" },
        { id: "clipboard", label: "Clipboard", icon: "edit-paste", group: "Status",
          note: "What you copied lately; click one to copy it again.", dropdown: true, canMove: true, opts: {} },
        { id: "zones", label: "Window zones", icon: "view-split-left-right", group: "Status",
          note: "Snap zones for windows (FancyZones style): pick a layout or edit one.", dropdown: true, canMove: true, opts: {},
          rightAction: "Show Zone Overlay" },
        { id: "network", label: "Network", icon: "network-wireless", group: "Control Center",
          note: "Wi-Fi and wired network: connect, switch networks, VPN.", dropdown: true, canMove: false, opts: {} },
        { id: "rdp", label: "Remote desktop", icon: "krdc", group: "Status",
          note: "Shows while someone is connected to this computer; click to see who or disconnect.", dropdown: true, canMove: true, opts: {}, when: "someone connects" },
        { id: "camera", label: "Camera in use", icon: "camera-web", group: "Status",
          note: "Shows while an app uses the camera, and which one.", dropdown: true, canMove: true, opts: {}, when: "the camera is in use" },
        { id: "printers", label: "Printers", icon: "printer", group: "Status",
          note: "Print jobs and printers.", dropdown: true, canMove: true, opts: {}, when: "there is a printer" },
        { id: "drives", label: "Drives", icon: "drive-removable-media", group: "Status",
          note: "USB sticks, SD cards and other drives: open or eject them.", dropdown: true, canMove: true, opts: {}, when: "a drive is plugged in" },
        { id: "weather", label: "Weather", icon: "weather-few-clouds", group: "Status",
          note: "The temperature and sky outside; click for the forecast.", dropdown: true, canMove: true, opts: {} },
        { id: "keyboard", label: "Keyboard layout", icon: "input-keyboard", group: "Control Center",
          note: "The keyboard layout in use; click to switch.", dropdown: true, canMove: true, opts: {}, when: "you have more than one layout" },
        { id: "battery", label: "Battery", icon: "battery-good", group: "Control Center",
          note: "Charge left and power mode.", dropdown: true, canMove: false, opts: {}, when: "there is a battery" },
        { id: "bluetooth", label: "Bluetooth", icon: "preferences-system-bluetooth", group: "Control Center",
          note: "Connect headphones, mice and other Bluetooth devices.", dropdown: true, canMove: true, opts: {}, when: "there is Bluetooth" },
        { id: "brightness", label: "Display brightness", icon: "video-display-brightness", group: "Control Center",
          note: "Screen brightness (also for external monitors that allow it).", dropdown: true, canMove: true, opts: {} },
        { id: "volume", label: "Sound", icon: "audio-volume-high", group: "Control Center",
          note: "Volume and where sound plays; scroll on it to change the volume.", dropdown: true, canMove: false, opts: {} },
        { id: "notifications", label: "Notification Center", icon: "notifications", group: "System",
          note: "Your notifications; middle-click turns Do Not Disturb on or off.", dropdown: true, canMove: false, opts: {} },
        { id: "more", label: "⌃ More items", icon: "arrow-up", group: "System",
          note: "The menu with app icons and items that don't fit or that you put there. Shows only when it has something.",
          dropdown: false, canMove: false, fixed: true, opts: {} },
        { id: "help", label: "Help", icon: "help-contextual", group: "System",
          note: "Find a shortcut, setting or action by typing what you want to do.", dropdown: true, canMove: true, opts: {} },
        { id: "spotlight", label: "Spotlight", icon: "search", group: "System",
          note: "Search apps, files and settings, and calculate (also Super+Space).", dropdown: true, canMove: false, opts: {} },
        { id: "controlcenter", label: "Control Center", icon: "preferences-system", group: "System",
          note: "Wi-Fi, Bluetooth, sound, brightness and Do Not Disturb in one place.", dropdown: true, canMove: false, opts: {} },
        { id: "ai", label: "Assistant", icon: "assistant", group: "System",
          note: "Ask by voice or by typing; the assistant's model and memory.", dropdown: true, canMove: true, opts: {},
          rightAction: "AI Settings…", when: "an assistant is set up" },
        { id: "clock", label: "Clock", icon: "preferences-system-time", group: "System",
          note: "The date and time; click for the calendar.", dropdown: true, canMove: false, opts: { dateStyle: "short", format: "" } }
    ]
    readonly property var byId: { const m = {}; for (const c of catalog) m[c.id] = c; return m; }
    readonly property var treetopKinds: ({ "treetop.cpu": "cpu", "treetop.mem": "mem", "treetop.gpu": "gpu", "treetop.vram": "vram",
                                          "treetop.disk": "disk", "treetop.net": "net", "treetop.temp": "temp" })

    // When the bar is full, items move into the ⌃ menu in this order (the
    // least important first; app icons go before all of these, from the
    // left). Items not listed go after these.
    readonly property var overflowOrder: ["treetop.temp", "treetop.net", "treetop.disk", "treetop.vram", "treetop.gpu", "treetop.mem", "treetop.cpu",
        "workspaces", "weather", "devapps", "ai", "media", "clipboard", "zones", "rdp", "printers", "drives", "keyboard",
        "brightness", "bluetooth", "help", "camera", "recording", "volume", "network", "battery", "notifications", "spotlight",
        "controlcenter", "clock"]

    // ---- the list -------------------------------------------------------
    // Settings' `menubar.items`, or (never edited) one made from the old
    // per-item settings: showWorkspaces, showSysMonitor, hiddenIndicators
    // and overflow (hearth 9a2baeb). Items the list lacks (new in hearth)
    // go in after the item before them in the default order; unknown ids
    // are dropped.
    function defaultEntry(c) { return Object.assign({ id: c.id, show: "bar" }, c.opts); }
    function legacyList(mb) {
        const hidden = mb.hiddenIndicators || [];
        const ovf = mb.overflow || {};
        return catalog.map(c => {
            const e = defaultEntry(c);
            if (c.id === "workspaces" && mb.showWorkspaces === false) e.show = "hidden";
            if (c.group === "treetop" && mb.showSysMonitor === false) e.show = "hidden";
            if (hidden.indexOf(c.id) >= 0) e.show = "hidden";
            const o = ovf[c.group === "treetop" ? "sysmonitor" : c.id];
            if (o !== undefined && !!o !== c.canMove) e.canMove = !!o;
            return e;
        });
    }
    readonly property var list: {
        void Settings.data;
        const mb = (Settings.data && Settings.data.menubar) || {};
        const stored = Array.isArray(mb.items) ? mb.items : legacyList(mb);
        const out = [];
        const seen = {};
        for (const e of stored) {
            if (!e || !byId[e.id] || seen[e.id]) continue;
            seen[e.id] = true;
            out.push(Object.assign(defaultEntry(byId[e.id]), e));
        }
        for (let i = 0; i < catalog.length; i++) {
            const c = catalog[i];
            if (seen[c.id]) continue;
            let at = 0;
            for (let j = i - 1; j >= 0; j--) {
                const k = out.findIndex(e => e.id === catalog[j].id);
                if (k >= 0) { at = k + 1; break; }
            }
            out.splice(at, 0, defaultEntry(c));
            seen[c.id] = true;
        }
        return out;
    }
    readonly property var order: list.map(e => e.id)
    readonly property var entries: { const m = {}; for (const e of list) m[e.id] = e; return m; }

    function entry(id) { return entries[id] || null; }
    // Where an item shows ("bar" for anything not in the list).
    function show(id) {
        const e = entries[id];
        if (!e) return "bar";
        if (byId[id] && byId[id].fixed) return "bar";
        return e.show === "overflow" || e.show === "hidden" ? e.show : "bar";
    }
    function opt(id, key) {
        const e = entries[id];
        if (e && e[key] !== undefined) return e[key];
        const c = byId[id];
        return c && c.opts ? c.opts[key] : undefined;
    }
    function canMove(id) {
        const e = entries[id];
        if (e && e.canMove !== undefined) return !!e.canMove;
        return byId[id] ? !!byId[id].canMove : true;
    }
    function label(id) { return byId[id] ? byId[id].label : id; }

    // ---- changes -----------------------------------------------------------
    // Writes the whole list (the old per-item keys go: the list replaces them).
    function save(l) {
        Settings.set("menubar.items", l.map(e => {
            // Only what differs from the defaults, so new defaults reach
            // items nobody changed.
            const c = byId[e.id];
            const d = defaultEntry(c);
            const o = { id: e.id };
            for (const k in e) if (k !== "id" && JSON.stringify(e[k]) !== JSON.stringify(d[k])) o[k] = e[k];
            if (o.canMove !== undefined && o.canMove === c.canMove) delete o.canMove;
            return o;
        }));
        for (const k of ["showWorkspaces", "showSysMonitor", "hiddenIndicators", "overflow"])
            if (Settings.data.menubar && Settings.data.menubar[k] !== undefined) Settings.reset("menubar." + k);
    }
    function copyList() { return list.map(e => Object.assign({}, e)); }
    function setShow(id, v) {
        if (!byId[id] || byId[id].fixed) return;
        if (v === "overflow" && !byId[id].dropdown) v = "bar";
        const l = copyList();
        const e = l.find(x => x.id === id);
        if (e.show === v) return;
        e.show = v;
        save(l);
    }
    function setOpt(id, key, v) {
        const l = copyList();
        const e = l.find(x => x.id === id);
        if (!e) return;
        e[key] = v;
        save(l);
    }
    function setCanMove(id, v) { setOpt(id, "canMove", !!v); }
    // Move an item to position `to` in the whole list.
    function move(id, to) {
        const l = copyList();
        const i = l.findIndex(x => x.id === id);
        if (i < 0) return;
        const [e] = l.splice(i, 1);
        to = Math.max(0, Math.min(l.length, to));
        l.splice(to, 0, e);
        if (JSON.stringify(l.map(x => x.id)) === JSON.stringify(order)) return;
        save(l);
    }
    // Move an item just before `beforeId` ("" = to the end).
    function moveBefore(id, beforeId) {
        if (id === beforeId) return;
        const rest = order.filter(x => x !== id);
        const k = beforeId ? rest.indexOf(beforeId) : rest.length;
        move(id, k < 0 ? rest.length : k);
    }
    function resetAll() { Settings.reset("menubar.items"); }

    // ---- editing the bar in place --------------------------------------------
    // "Edit Menu Bar" (right click on an item): items can be dragged without
    // Super, and dragged off the bar to hide them, on every screen's bar.
    property bool editing: false
    // Settings > Menu Bar scrolls to and highlights this item when it opens.
    property string focusId: ""
    function openSettings(id) {
        focusId = id || "";
        Settings.openRequested("menubar");
    }

    IpcHandler {
        target: "menubar"
        function items(): string { return JSON.stringify(root.list); }
        function place(id: string, where: string): void { root.setShow(id, where); }
        function move(id: string, to: int): void { root.move(id, to); }
        function option(id: string, key: string, json: string): void {
            let v;
            try { v = JSON.parse(json); } catch (e) { v = json; }
            root.setOpt(id, key, v);
        }
        // Settings > Menu Bar, scrolled to this item with its options open.
        function settings(id: string): void { root.openSettings(id); }
        function edit(): void { root.editing = true; }
        function done(): void { root.editing = false; }
        function reset(): void { root.resetAll(); }
    }
}
