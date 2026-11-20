import QtQuick
import Quickshell
import Quickshell.Hyprland
import ".."

// Compositor backend for Hyprland: Quickshell.Hyprland's toplevels and
// workspaces, normalized to the shape services/Compositor.qml documents.
// Dispatches go through services/Hypr.qml (Lua or legacy syntax).
Scope {
    id: root

    function addr(a) { return String(a).replace(/^0x/, ""); }

    readonly property var windows: Hyprland.toplevels.values.filter(t => t.wayland).map(t => {
        const o = t.lastIpcObject || {};
        const mon = t.monitor || (t.workspace ? t.workspace.monitor : null);
        const mx = mon ? mon.x : 0, my = mon ? mon.y : 0;
        return {
            id: root.addr(t.address),
            appId: o.class || t.wayland.appId || "",
            title: t.title || "",
            workspaceId: t.workspace ? t.workspace.id : null,
            output: mon ? mon.name : "",
            focused: t.activated,
            minimized: !!(t.wayland && t.wayland.minimized),
            floating: !!o.floating,
            urgent: t.urgent,
            at: o.at ? [o.at[0] - mx, o.at[1] - my] : null,
            size: o.size ? [o.size[0], o.size[1]] : null,
            focusOrder: o.focusHistoryID !== undefined ? o.focusHistoryID : 1e6,
            special: !!(t.workspace && t.workspace.id < 0),
            appMenu: null,
            toplevel: t.wayland,
            hypr: t
        };
    })

    readonly property var workspaces: Hyprland.workspaces.values.map(w => ({
        id: w.id,
        idx: w.id,
        name: w.name,
        output: w.monitor ? w.monitor.name : "",
        active: w.active,
        focused: w.focused,
        urgent: w.urgent,
        special: w.id < 0
    }))

    readonly property string focusedOutput: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    function focusWindow(id) { Hypr.focusWindow(id); }
    function closeWindow(id) { Hypr.closeWindow(id); }
    function focusWorkspace(id) { Hypr.focusWorkspace(id); }
    function focusWorkspaceRelative(delta) { Hypr.focusWorkspace(delta > 0 ? "e+1" : "e-1"); }
    function moveWindowToWorkspace(id, wsId) { Hypr.moveWindowToWorkspace(id, wsId); }
    function focusEmptyWorkspace() { Hypr.focusWorkspace("empty"); }
    function refresh() { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); }

    // Hyprland binds reach the switcher/overview through socket2 `custom`
    // events (hl.dsp.event("hearth-switcher next")); forwarded as
    // Compositor.customEvent(data).
    signal customEvent(string data)
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "custom") root.customEvent(event.data);
        }
    }

    // Touch Hypr so its geometry refresh (lastIpcObject) runs.
    Component.onCompleted: void Hypr
}
