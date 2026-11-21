import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Compositor backend for arbor (Ben's niri fork), over its JSON IPC
// socket ($ARBOR_SOCKET; $NIRI_SOCKET from older builds): one long-lived connection subscribed to
// the event stream keeps the state, and each action opens a short-lived
// connection (what `arbor msg action ...` does, without a process per call).
// Field names follow niri-ipc's Window / Workspace / Event types.
Scope {
    id: root

    readonly property string socketPath: Quickshell.env("ARBOR_SOCKET") || Quickshell.env("NIRI_SOCKET") || ""
    property var winMap: ({})      // id -> niri Window JSON
    property var wsList: []        // [niri Workspace JSON]
    property bool streaming: false

    // wlr foreign-toplevel handles (thumbnails, minimize) matched to niri
    // windows by app id and title; niri doesn't share ids between the two.
    function matchToplevels(wins) {
        const tops = ToplevelManager.toplevels.values;
        const used = new Set();
        const out = {};
        const pass = (exact) => {
            for (const w of wins) {
                if (out[w.id]) continue;
                for (const t of tops) {
                    if (used.has(t)) continue;
                    if ((t.appId || "") !== (w.app_id || "")) continue;
                    if (exact && (t.title || "") !== (w.title || "")) continue;
                    used.add(t);
                    out[w.id] = t;
                    break;
                }
            }
        };
        pass(true);
        pass(false);
        return out;
    }

    readonly property var windows: {
        const raw = Object.values(root.winMap);
        const tops = root.matchToplevels(raw);
        const outOf = {};
        for (const ws of root.wsList) outOf[ws.id] = ws.output || "";
        return raw.map(w => {
            const l = w.layout || {};
            const ts = w.focus_timestamp ? w.focus_timestamp.secs + w.focus_timestamp.nanos / 1e9 : 0;
            return {
                id: String(w.id),
                appId: w.app_id || "",
                title: w.title || "",
                workspaceId: w.workspace_id !== null && w.workspace_id !== undefined ? w.workspace_id : null,
                output: w.workspace_id !== null && w.workspace_id !== undefined ? (outOf[w.workspace_id] || "") : "",
                focused: !!w.is_focused,
                minimized: !!w.is_minimized,   // arbor
                floating: !!w.is_floating,
                urgent: !!w.is_urgent,
                pid: w.pid || 0,
                at: l.tile_pos_in_workspace_view ? [l.tile_pos_in_workspace_view[0], l.tile_pos_in_workspace_view[1]] : null,
                size: l.tile_size ? [l.tile_size[0], l.tile_size[1]] : null,
                focusOrder: -ts,
                special: false,
                // arbor: {"service_name", "object_path"} of the window's
                // com.canonical.dbusmenu menu bar (KDE appmenu protocol).
                appMenu: w.app_menu || null,
                toplevel: tops[w.id] || null,
                hypr: null
            };
        });
    }

    readonly property var workspaces: root.wsList.map(w => ({
        id: w.id,
        idx: w.idx,
        name: w.name || String(w.idx),
        output: w.output || "",
        active: !!w.is_active,
        focused: !!w.is_focused,
        urgent: !!w.is_urgent,
        special: false
    }))

    readonly property string focusedOutput: {
        const f = root.wsList.find(w => w.is_focused);
        return f ? (f.output || "") : "";
    }

    signal customEvent(string data)

    // --- state from events ---

    function setWin(id, fn) {
        const m = Object.assign({}, root.winMap);
        if (!m[id]) return;
        m[id] = fn(Object.assign({}, m[id]));
        root.winMap = m;
    }

    function handle(line) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }
        if (ev.Ok !== undefined || ev.Err !== undefined) {
            if (ev.Err !== undefined) console.warn("arbor event stream:", ev.Err);
            return;
        }
        const name = Object.keys(ev)[0];
        const d = ev[name];
        switch (name) {
        case "WindowsChanged": {
            const m = {};
            for (const w of d.windows) m[w.id] = w;
            root.winMap = m;
            break;
        }
        case "WindowOpenedOrChanged": {
            const m = Object.assign({}, root.winMap);
            if (d.window.is_focused)
                for (const k in m) if (m[k].is_focused) m[k] = Object.assign({}, m[k], { is_focused: false });
            m[d.window.id] = d.window;
            root.winMap = m;
            break;
        }
        case "WindowClosed": {
            const m = Object.assign({}, root.winMap);
            delete m[d.id];
            root.winMap = m;
            break;
        }
        case "WindowFocusChanged": {
            const m = {};
            for (const k in root.winMap) {
                const w = root.winMap[k];
                const f = d.id !== null && w.id === d.id;
                m[k] = w.is_focused === f ? w : Object.assign({}, w, { is_focused: f });
            }
            root.winMap = m;
            break;
        }
        case "WindowFocusTimestampChanged":
            setWin(d.id, w => { w.focus_timestamp = d.focus_timestamp; return w; });
            break;
        case "WindowUrgencyChanged":
            setWin(d.id, w => { w.is_urgent = d.urgent; return w; });
            break;
        case "WindowLayoutsChanged": {
            const m = Object.assign({}, root.winMap);
            for (const [id, layout] of d.changes)
                if (m[id]) m[id] = Object.assign({}, m[id], { layout: layout });
            root.winMap = m;
            break;
        }
        case "WorkspacesChanged":
            root.wsList = d.workspaces;
            break;
        case "WorkspaceActivated": {
            const target = root.wsList.find(w => w.id === d.id);
            if (!target) break;
            root.wsList = root.wsList.map(w => {
                const n = Object.assign({}, w);
                if (w.output === target.output) n.is_active = w.id === d.id;
                if (d.focused) n.is_focused = w.id === d.id;
                return n;
            });
            break;
        }
        case "WorkspaceActiveWindowChanged":
            root.wsList = root.wsList.map(w => w.id === d.workspace_id
                ? Object.assign({}, w, { active_window_id: d.active_window_id }) : w);
            break;
        case "WorkspaceUrgencyChanged":
            root.wsList = root.wsList.map(w => w.id === d.id ? Object.assign({}, w, { is_urgent: d.urgent }) : w);
            break;
        }
    }

    Socket {
        id: stream
        path: root.socketPath
        connected: root.socketPath !== ""
        onConnectionStateChanged: {
            if (connected) {
                write('"EventStream"\n');
                flush();
                root.streaming = true;
            } else {
                root.streaming = false;
                if (root.socketPath !== "") reconnect.start();
            }
        }
        parser: SplitParser { onRead: line => root.handle(line) }
    }
    Timer {
        id: reconnect
        interval: 2000
        onTriggered: { stream.connected = false; stream.connected = true; }
    }

    // --- actions ---

    Component {
        id: requestComp
        Socket {
            id: req
            property string payload: ""
            path: root.socketPath
            onConnectionStateChanged: if (connected) { write(payload + "\n"); flush(); }
            parser: SplitParser {
                onRead: line => {
                    try {
                        const r = JSON.parse(line);
                        if (r.Err !== undefined) console.warn("arbor action failed:", req.payload, r.Err);
                    } catch (e) {}
                    req.connected = false;
                    Qt.callLater(() => req.destroy());
                }
            }
        }
    }

    function action(name, args) {
        if (!root.socketPath) return;
        const a = {};
        a[name] = args || {};
        const s = requestComp.createObject(root, { payload: JSON.stringify({ Action: a }) });
        s.connected = true;
    }

    function num(id) { return Number(id); }
    function focusWindow(id) { action("FocusWindow", { id: num(id) }); }
    // arbor: MinimizeWindow; focusing a minimized window restores it.
    function minimize(id) { action("MinimizeWindow", { id: num(id) }); }
    function closeWindow(id) { action("CloseWindow", { id: num(id) }); }
    function focusWorkspace(id) { action("FocusWorkspace", { reference: { Id: num(id) } }); }
    function focusWorkspaceRelative(delta) { action(delta > 0 ? "FocusWorkspaceDown" : "FocusWorkspaceUp", {}); }
    function moveWindowToWorkspace(id, wsId) {
        action("MoveWindowToWorkspace", { window_id: num(id), reference: { Id: num(wsId) }, focus: false });
    }
    // niri keeps an empty workspace at the end of every output.
    function focusEmptyWorkspace() {
        const out = root.focusedOutput;
        const used = new Set(Object.values(root.winMap).map(w => w.workspace_id));
        const empty = root.wsList.filter(w => w.output === out && !used.has(w.id)).sort((a, b) => b.idx - a.idx);
        if (empty.length) focusWorkspace(empty[0].id);
    }
    function refresh() {}
}
