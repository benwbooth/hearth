pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import "compositor"

// What the shell needs from the compositor, for Hyprland and arbor.
//
// windows: [{ id (string), appId, title, workspaceId, output, focused, minimized,
//             floating, urgent, at: [x, y] | null (logical, relative to the
//             output), size: [w, h] | null, focusOrder (lower = more recent),
//             special (Hyprland special workspace), appMenu: { service_name,
//             object_path } | null (arbor only), toplevel (wlr
//             foreign-toplevel handle or null), hypr (HyprlandToplevel or null) }]
// workspaces: [{ id, idx, name, output, active, focused, urgent, special }]
//
// Backend: HEARTH_COMPOSITOR=hyprland|arbor, else whichever IPC socket the
// environment points at (an arbor session sets XDG_CURRENT_DESKTOP=arbor when
// both are inherited). Only the active backend is instantiated, so nothing
// touches Quickshell.Hyprland outside Hyprland.
Singleton {
    id: root

    readonly property string type: {
        const forced = (Quickshell.env("HEARTH_COMPOSITOR") || "").toLowerCase();
        if (forced === "hyprland") return forced;
        if (forced === "arbor" || forced === "niri") return "arbor";
        const hypr = !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE");
        const arbor = !!(Quickshell.env("ARBOR_SOCKET") || Quickshell.env("NIRI_SOCKET"));
        if (hypr && arbor) {
            const d = (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase();
            return d.includes("arbor") || d.includes("niri") ? "arbor" : "hyprland";
        }
        return arbor ? "arbor" : hypr ? "hyprland" : "none";
    }
    readonly property bool isHyprland: type === "hyprland"
    readonly property bool isArbor: type === "arbor"
    // Inside a Plasma session (or a test session that inherited its
    // environment), where plasmashell owns notifications and the Bluetooth
    // agent. arbor's own XDG_CURRENT_DESKTOP is "arbor:KDE" (so apps pick
    // KDE portals), which is not Plasma.
    readonly property bool underPlasma: {
        const d = (Quickshell.env("XDG_CURRENT_DESKTOP") || "").split(":");
        return d.includes("KDE") && !d.includes("arbor");
    }

    LazyLoader { id: hyprLoader; active: root.isHyprland; HyprBackend {} }
    LazyLoader { id: arborLoader; active: root.isArbor; ArborBackend {} }
    readonly property var backend: root.isHyprland ? hyprLoader.item : root.isArbor ? arborLoader.item : null

    readonly property var windows: backend ? backend.windows : []
    // The compositor's own overview is open (arbor's Mission Control).
    readonly property bool overviewOpen: !!(backend && backend.overviewOpen)
    readonly property var workspaces: backend ? backend.workspaces : []
    readonly property var focusedWindow: windows.find(w => w.focused) || null
    readonly property string focusedWindowId: focusedWindow && focusedWindow.id !== undefined ? String(focusedWindow.id) : ""
    readonly property var focusedWorkspace: workspaces.find(w => w.focused) || null
    readonly property string focusedOutput: (backend && backend.focusedOutput) || ""
    readonly property var focusedScreen: screenFor(focusedOutput)

    // Minimizing goes through the foreign-toplevel handle; niri has no
    // minimize of its own (arbor may honour the request).
    readonly property bool canMinimize: true

    // Window ids, most recently focused first.
    property var mru: []
    onFocusedWindowIdChanged: {
        const id = focusedWindowId;
        if (!id) return;
        const m = mru.filter(x => x !== id);
        m.unshift(id);
        mru = m.slice(0, 200);
    }

    // Raised for Hyprland `custom` socket2 events (hl.dsp.event(...)).
    signal customEvent(string data)
    // arbor: zone-snapping drags (see services/ArborZones.qml).
    signal zoneDrag(var drag)
    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onCustomEvent(data) { root.customEvent(data); }
        function onZoneDrag(drag) { root.zoneDrag(drag); }
    }

    function screenFor(outputName) {
        const s = Quickshell.screens;
        return s.find(x => x.name === outputName) || (s.length ? s[0] : null);
    }

    // Windows sorted most recently used first.
    function windowsByRecency() {
        const rank = id => { const i = mru.indexOf(id); return i < 0 ? 1e6 : i; };
        return windows.slice().sort((a, b) => (rank(a.id) - rank(b.id)) || (a.focusOrder - b.focusOrder));
    }

    function windowForToplevel(t) { return t ? (windows.find(w => w.toplevel === t) || null) : null; }
    function workspacesOn(outputName) {
        return workspaces.filter(w => !w.special && (!outputName || !w.output || w.output === outputName))
            .sort((a, b) => a.idx - b.idx);
    }
    function windowsOn(wsId) { return windows.filter(w => w.workspaceId === wsId); }

    function focusWindow(id) { if (backend) backend.focusWindow(id); }
    function closeWindow(id) { if (backend) backend.closeWindow(id); }
    function focusWorkspace(id) { if (backend) backend.focusWorkspace(id); }
    function focusWorkspaceRelative(delta) { if (backend) backend.focusWorkspaceRelative(delta); }
    function moveWindowToWorkspace(id, wsId) { if (backend) backend.moveWindowToWorkspace(id, wsId); }
    function focusEmptyWorkspace() { if (backend) backend.focusEmptyWorkspace(); }
    function refresh() { if (backend) backend.refresh(); }
    // arbor only: any IPC request, cb(reply) with { Ok } / { Err }.
    function arborRequest(req, cb) {
        if (root.isArbor && backend) backend.request(req, cb);
        else if (cb) cb({ Err: "not running under arbor" });
    }
    function arborAction(name, args) { if (root.isArbor && backend) backend.action(name, args); }
    function minimize(id) {
        if (backend && backend.minimize) { backend.minimize(id); return; }
        const w = windows.find(x => x.id === id);
        if (w && w.toplevel) w.toplevel.minimized = true;
    }
    // Minimize through the compositor when it can (arbor), else the
    // foreign-toplevel request.
    function minimizeToplevel(t) {
        const w = windowForToplevel(t);
        if (w && backend && backend.minimize) backend.minimize(w.id);
        else if (t) t.minimized = true;
    }
}
