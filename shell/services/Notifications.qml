pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import ".."

// hearth's own notification server (org.freedesktop.Notifications),
// macOS style: banners slide in at the top right (popups/NotificationBanners.qml)
// and stay in Notification Center (popups/NotificationCenter.qml), stacked
// per app, until you clear them or the app withdraws them. Replaces
// SwayNotificationCenter so notifications get hearth's liquid glass.
//
// Not under Plasma (plasmashell is the server there), nor with
// HEARTH_NOTIFICATIONS=0. If another server holds the name, Quickshell
// takes over as soon as it goes away.
//
//   hearth-ipc call notifications toggle | open | close | clear
//   hearth-ipc call notifications dnd true|false | toggleDnd | count | list | test
//   hearth-ipc call notifications expand APP true|false
Singleton {
    id: root

    readonly property bool wanted: !Compositor.underPlasma && Quickshell.env("HEARTH_NOTIFICATIONS") !== "0"
    readonly property var cfg: Settings.notifications
    readonly property bool dnd: !!cfg.dnd
    readonly property bool grouped: cfg.group !== false

    // Every notification the server holds (oldest first).
    readonly property var all: server.item ? server.item.trackedNotifications.values : []
    // What Notification Center lists: not the transient ones, newest first.
    readonly property var list: { void root.timesVersion; return all.filter(n => !n.transient).slice().reverse(); }
    readonly property int count: list.length

    // Banners on screen now, newest first.
    property var banners: []
    // Notification Center.
    property bool centerOpen: false
    // Cards with an inline reply open: their window takes the keyboard.
    property int replying: 0
    // Apps whose stack is expanded in Notification Center.
    property var expanded: ({})

    // When each notification arrived (ms), by id; kept across reloads.
    property var times: ({})
    property int timesVersion: 0
    function timeOf(n) { void timesVersion; return n ? (times[n.id] || Date.now()) : 0; }
    function stamp(n) {
        const t = Object.assign({}, times);
        t[n.id] = Date.now();
        // Forget the times of notifications that are gone.
        const live = new Set(all.map(x => x.id));
        for (const k in t) if (!live.has(Number(k)) && Number(k) !== n.id) delete t[k];
        times = t;
        persist.json = JSON.stringify(t);
        timesVersion++;
    }
    // Kept across shell reloads (as text: objects don't survive one).
    PersistentProperties {
        id: persist
        reloadableId: "hearthNotificationTimes"
        property string json: "{}"
        onLoaded: { try { root.times = JSON.parse(json) || {}; } catch (e) {} root.timesVersion++; }
    }

    // Groups for Notification Center: [{ key, app, icon, items }], newest
    // first; one group per notification when grouping is off.
    readonly property var groups: {
        const out = [], byKey = {};
        for (const n of list) {
            const key = grouped ? appKey(n) : "#" + n.id;
            let g = byKey[key];
            if (!g) { g = byKey[key] = { key: key, app: appLabel(n), icon: n.appIcon, items: [] }; out.push(g); }
            g.items.push(n);
        }
        return out;
    }
    function byId(id) { return all.find(n => n.id === id) || null; }
    function appKey(n) { return (n.desktopEntry || n.appName || "?").toLowerCase(); }
    function appLabel(n) { return n.appName || n.desktopEntry || "Notification"; }

    // A minute clock for "5m ago".
    property real now: Date.now()
    Timer {
        interval: 30000
        repeat: true
        running: root.count > 0
        onTriggered: root.now = Date.now()
    }
    // macOS: "now", "5m ago", "2h ago", "Yesterday", "Mon", "12/3/26".
    function ago(n) {
        void root.now;
        const t = timeOf(n);
        const s = Math.max(0, (Date.now() - t) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m ago";
        const d = new Date(t), today = new Date();
        const days = Math.round((new Date(today.getFullYear(), today.getMonth(), today.getDate())
                               - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000);
        if (days === 0) return Math.floor(s / 3600) + "h ago";
        if (days === 1) return "Yesterday";
        if (days < 7) return d.toLocaleDateString(Qt.locale(), "ddd");
        return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    // How long a banner stays (ms): 0 = until dismissed.
    function bannerTimeout(n) {
        if (n.urgency === NotificationUrgency.Critical) return 0;
        const base = Math.max(2, Number(cfg.timeout) || 6) * 1000;
        if (n.expireTimeout > 0) return Math.max(2000, Math.min(n.expireTimeout, 60000));
        return n.urgency === NotificationUrgency.Low ? Math.round(base * 0.7) : base;
    }
    function showsBanner(n) {
        if (root.centerOpen) return false;
        if (!root.dnd) return true;
        return n.urgency === NotificationUrgency.Critical && cfg.urgentInDnd !== false;
    }

    function pushBanner(n) {
        if (!showsBanner(n)) {
            if (n.transient) n.expire();
            return;
        }
        const b = banners.filter(x => x !== n);
        b.unshift(n);
        // At most four at once; the oldest drop into Notification Center.
        while (b.length > 4) {
            const old = b.pop();
            if (old.transient && old.tracked) old.expire();
        }
        banners = b;
        bannerShown(n);
    }
    // The banner for `n` restarts its timer (an app replaced its text).
    signal bannerShown(var n)
    function hideBanner(n) {
        if (banners.indexOf(n) < 0) return;
        banners = banners.filter(x => x !== n);
        if (n && n.transient && n.tracked) n.expire();
    }

    // --- actions ---
    function dismiss(n) {
        hideBanner(n);
        if (n && n.tracked) n.dismiss();
    }
    function clearGroup(key) {
        for (const n of list.filter(x => (grouped ? appKey(x) : "#" + x.id) === key)) dismiss(n);
        setExpanded(key, false);
    }
    function clearAll() {
        for (const n of all.slice()) dismiss(n);
        expanded = {};
        banners = [];
    }
    function setExpanded(key, on) {
        const e = Object.assign({}, expanded);
        if (on) e[key] = true; else delete e[key];
        expanded = e;
    }
    // Clicking a notification: its default action, or else the app's
    // window comes to the front. Then it goes away, as on macOS.
    function activate(n) {
        if (!n) return;
        const def = n.actions.find(a => a.identifier === "default");
        if (def) { hideBanner(n); def.invoke(); if (n.tracked) n.dismiss(); }
        else { focusApp(n); dismiss(n); }
        closeCenter();
    }
    function invokeAction(n, a) {
        hideBanner(n);
        a.invoke();
    }
    function reply(n, text) {
        if (!n || !text) return;
        hideBanner(n);
        n.sendInlineReply(text);
    }
    function focusApp(n) {
        const keys = [n.desktopEntry, n.appName].filter(k => !!k).map(k => k.toLowerCase());
        if (!keys.length) return;
        const w = Compositor.windowsByRecency().find(w => {
            const id = String(w.appId || w.app_id || w.class || "").toLowerCase();
            return id && keys.some(k => id === k || id.endsWith("." + k) || id.split(".").pop() === k.replace(/\s+/g, ""));
        });
        if (w) Compositor.focusWindow(w.id);
    }

    function setDnd(on) { Settings.set("notifications.dnd", !!on); }
    function toggleDnd() { setDnd(!dnd); }
    onDndChanged: if (dnd) banners = banners.filter(n => n.urgency === NotificationUrgency.Critical && cfg.urgentInDnd !== false)

    function openCenter() {
        if (ShellState.activePopup && ShellState.activePopup.open) ShellState.activePopup.close();
        banners = [];
        centerOpen = true;
    }
    function closeCenter() { centerOpen = false; }
    function toggleCenter() { if (centerOpen) closeCenter(); else openCenter(); }
    onCenterOpenChanged: if (!centerOpen) expanded = {}
    // A menu or popover opening closes Notification Center.
    Connections {
        target: ShellState
        function onActivePopupChanged() { if (ShellState.activePopup) root.closeCenter(); }
    }

    // A test notification (Settings > Notifications).
    function sendTest() {
        Quickshell.execDetached(["notify-send", "-a", "hearth", "-i", "preferences-desktop-notification",
            "-A", "default=Open", "-A", "ok=Looks good",
            "Notifications work", "This is how a notification looks. Click it, or use the buttons."]);
    }

    // A swaync left over from an older hearth (orphaned, it outlives the
    // shell) would keep the notification name: stop it and its old
    // swaync-client watchers, but only those on this session's bus (test rigs run their own on private buses).
    Process {
        running: root.wanted
        command: ["sh", "-c", 'for p in $(pgrep -f "bin/[.]?swaync(-client)?(-wrapped)?( |$)"); do tr "\\0" "\\n" < /proc/$p/environ 2>/dev/null | grep -qxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" && kill "$p"; done; true']
    }

    LazyLoader {
        id: server
        active: root.wanted
        NotificationServer {
            keepOnReload: true
            persistenceSupported: true
            bodySupported: true
            bodyMarkupSupported: true
            bodyHyperlinksSupported: true
            bodyImagesSupported: false
            actionsSupported: true
            actionIconsSupported: false
            imageSupported: true
            inlineReplySupported: true

            onNotification: n => {
                n.tracked = true;
                // Kept across a shell reload: no banner again.
                if (n.lastGeneration) return;
                root.stamp(n);
                root.pushBanner(n);
                watch.createObject(root, { n: n });
            }
        }
    }

    // An app replaced a notification's text: it pops up again, newest.
    Component {
        id: watch
        QtObject {
            id: w
            required property var n
            property Connections c: Connections {
                target: w.n
                function onSummaryChanged() { replaced.restart(); }
                function onBodyChanged() { replaced.restart(); }
                function onClosed() { root.hideBanner(w.n); w.destroy(); }
            }
            property Timer replaced: Timer {
                interval: 50
                onTriggered: {
                    root.stamp(w.n);
                    root.pushBanner(w.n);
                }
            }
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.toggleCenter(); }
        function open(): void { root.openCenter(); }
        function close(): void { root.closeCenter(); }
        function clear(): void { root.clearAll(); }
        function dnd(on: bool): void { root.setDnd(on); }
        function toggleDnd(): void { root.toggleDnd(); }
        function count(): int { return root.count; }
        function list(): string {
            return JSON.stringify(root.list.map(n => ({ id: n.id, app: n.appName, summary: n.summary, body: n.body,
                urgency: n.urgency, time: root.timeOf(n), actions: n.actions.map(a => a.text) })));
        }
        function test(): void { root.sendTest(); }
        // Fan out (or stack again) an app's notifications by app name.
        function expand(app: string, on: bool): void {
            const g = root.groups.find(g => g.app.toLowerCase() === app.toLowerCase() || g.key === app.toLowerCase());
            if (g) { root.openCenter(); root.setExpanded(g.key, on); }
        }
    }
}
