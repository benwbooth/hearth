pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Thin wrapper over Hyprland IPC. Hyprland 0.55 configs are Lua, where
// `hyprctl dispatch` takes a Lua dispatcher expression instead of the old
// "workspace 3" strings; every call here sends whichever form is in use.
Singleton {
    id: root

    function dispatch(legacy, lua) {
        Hyprland.dispatch(Hyprland.usingLua ? lua : legacy);
    }

    function lit(v) { return JSON.stringify(v); }

    function focusWorkspace(ws) {
        dispatch(`workspace ${ws}`, `hl.dsp.focus({ workspace = ${lit(ws)} })`);
    }

    function focusWindow(address) {
        const a = address.startsWith("0x") ? address : "0x" + address;
        dispatch(`focuswindow address:${a}`, `hl.dsp.focus({ window = ${lit("address:" + a)} })`);
    }

    function closeWindow(address) {
        const a = address.startsWith("0x") ? address : "0x" + address;
        dispatch(`closewindow address:${a}`, `hl.dsp.window.close({ window = ${lit("address:" + a)} })`);
    }

    function moveWindowToWorkspace(address, ws) {
        const a = address.startsWith("0x") ? address : "0x" + address;
        dispatch(`movetoworkspacesilent ${ws},address:${a}`,
                 `hl.dsp.window.move({ workspace = ${lit(ws)}, window = ${lit("address:" + a)}, silent = true })`);
    }

    function exec(cmd) {
        dispatch(`exec ${cmd}`, `hl.dsp.exec_cmd(${lit(cmd)})`);
    }

    // Toplevel (wlr foreign-toplevel) -> HyprlandToplevel, for urgency,
    // workspace and geometry.
    function hyprFor(toplevel) {
        const all = Hyprland.toplevels.values;
        for (let i = 0; i < all.length; i++)
            if (all[i].wayland === toplevel) return all[i];
        return null;
    }

    // Keep window geometry (lastIpcObject) fresh for the pager.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow": case "closewindow": case "movewindow": case "movewindowv2":
            case "changefloatingmode": case "fullscreen": case "activewindowv2":
            case "workspacev2": case "createworkspacev2": case "destroyworkspacev2":
                refresh.restart();
            }
        }
    }
    Timer {
        id: refresh
        interval: 60
        onTriggered: { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); }
    }
}
