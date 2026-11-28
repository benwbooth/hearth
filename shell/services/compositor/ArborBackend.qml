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
    property bool overviewOpen: false  // arbor's overview (Mission Control)
    // A compositor began sending this stream (first connect, reconnect, or a
    // swap carried over by the proxy): state it keeps only in memory, like
    // the zones, has to be sent again.
    signal compositorStarted()

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
                // arbor: where a GTK window's GMenuModel menus live
                // (gtk_shell1 set_dbus_properties): unique_bus_name,
                // menubar_path, app_menu_path, window_object_path,
                // application_object_path.
                gtkMenu: w.gtk_menu || null,
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
    // arbor: a window drag that snaps into zones ({ output, area: [x, y, w, h],
    // zone: index | null }), or null when it ended (services/ArborZones.qml).
    signal zoneDrag(var drag)

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
            // Only sent in the burst that starts an event stream: a new
            // compositor, also one that took over this connection through
            // arbor's proxy after a swap (the stream never disconnects then).
            root.compositorStarted();
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
        case "ZoneDragChanged":
            root.zoneDrag(d.drag || null);
            break;
        case "WorkspaceUrgencyChanged":
            root.wsList = root.wsList.map(w => w.id === d.id ? Object.assign({}, w, { is_urgent: d.urgent }) : w);
            break;
        case "OverviewOpenedOrClosed":
            root.overviewOpen = !!d.is_open;
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
                // arbor restarted in place (reload-binary, or after a crash: its
                // supervisor keeps the sockets). With arbor's Wayland proxy
                // (ARBOR_WAYLAND_PROXY=1) this shell's Wayland connection and its
                // layer surfaces survive: just reconnect the event stream (the
                // first events re-send the whole state). Without it, Qt could
                // reconnect the Wayland connection, but Quickshell's own protocol
                // objects don't survive that, so quit and let the hearth wrapper
                // start a fresh shell (exit 75, see flake.nix). Only under that
                // wrapper; test runs reconnect.
                if (root.streaming && Quickshell.env("HEARTH_RESTARTER") === "1"
                        && Quickshell.env("ARBOR_WAYLAND_PROXY") !== "1") {
                    console.info("arbor restarted: restarting the shell");
                    Qt.exit(75);
                }
                root.streaming = false;
                if (root.socketPath !== "") reconnect.start();
            }
        }
        parser: SplitParser { onRead: line => root.handle(line) }
    }
    Timer {
        id: reconnect
        interval: Quickshell.env("ARBOR_WAYLAND_PROXY") === "1" ? 300 : 2000
        onTriggered: { stream.connected = false; stream.connected = true; }
    }

    // --- liquid glass (arbor's SetGlass, services/RealGlass.qml) ---
    // A persistent connection for SetGlass requests (sent up to once per
    // frame per window, so no socket per request). The first request after
    // connecting is an empty probe: arbor builds without glass reply an
    // error (unknown request), which turns the feature off.
    property var glassSupported: undefined
    // Bumped on every (re)connect: RealGlass resends all shapes.
    property int glassEpoch: 0
    property bool glassProbing: false
    Socket {
        id: glassSock
        path: root.socketPath
        connected: root.socketPath !== ""
        onConnectionStateChanged: {
            if (connected) {
                root.glassProbing = true;
                write('{"SetGlass":{"namespace":"hearth-probe","shapes":[]}}\n');
                flush();
            } else if (root.socketPath !== "") {
                glassReconnect.start();
            }
        }
        parser: SplitParser {
            onRead: line => {
                let r = null;
                try { r = JSON.parse(line); } catch (e) { return; }
                if (root.glassProbing) {
                    root.glassProbing = false;
                    root.glassSupported = r.Ok !== undefined;
                    root.glassEpoch++;
                } else if (r.Err !== undefined) {
                    console.warn("arbor SetGlass failed:", r.Err);
                }
            }
        }
    }
    Timer {
        id: glassReconnect
        interval: Quickshell.env("ARBOR_WAYLAND_PROXY") === "1" ? 300 : 2000
        onTriggered: { glassSock.connected = false; glassSock.connected = true; }
    }
    function setGlass(req) {
        if (!glassSock.connected || root.glassSupported !== true) return false;
        glassSock.write(JSON.stringify({ SetGlass: req }) + "\n");
        glassSock.flush();
        return true;
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

    // Any IPC request (a JSON-able value such as "Outputs" or
    // { Output: {...} }); `cb(reply)` gets the parsed reply ({ Ok: ... } or
    // { Err: "..." }), or { Err: "not connected" }.
    Component {
        id: queryComp
        Socket {
            id: q
            property string payload: ""
            property var cb: null
            property bool done: false
            path: root.socketPath
            function finish(r) {
                if (done) return;
                done = true;
                if (cb) cb(r);
                q.connected = false;
                Qt.callLater(() => q.destroy());
            }
            onConnectionStateChanged: {
                if (connected) { write(payload + "\n"); flush(); }
                else if (!done) finish({ Err: "arbor closed the connection" });
            }
            parser: SplitParser {
                onRead: line => {
                    let r;
                    try { r = JSON.parse(line); } catch (e) { r = { Err: "bad reply: " + line }; }
                    q.finish(r);
                }
            }
        }
    }
    function request(req, cb) {
        if (!root.socketPath) { if (cb) cb({ Err: "not connected" }); return; }
        const s = queryComp.createObject(root, { payload: JSON.stringify(req), cb: cb || null });
        s.connected = true;
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
