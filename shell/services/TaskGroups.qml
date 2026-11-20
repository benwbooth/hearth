pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland

// Taskbar / dock model: pinned launchers plus running apps, grouped by
// desktop entry like Plasma's icontasks. Shared by bar/Tasks.qml (classic
// panel) and bar/Dock.qml.
//
// groups: [{ key, entry, windows: [Toplevel], pinned, recent }]: pins in
// order, then running unpinned apps in the order they appeared, then (dock,
// "show suggested and recent apps") up to 3 recently closed unpinned apps.
Singleton {
    id: root

    function keyFor(toplevel) {
        const e = DesktopEntries.heuristicLookup(toplevel.appId);
        return e ? e.id : (toplevel.appId || "unknown");
    }

    readonly property var groups: {
        // Desktop entries load asynchronously: depend on the list so the
        // pins resolve once it's filled.
        void DesktopEntries.applications.values;
        const pins = Pins.ids;
        const tops = ToplevelManager.toplevels.values;
        const byKey = {};
        const order = [];
        for (const id of pins) {
            if (byKey[id]) continue;
            byKey[id] = { key: id, entry: DesktopEntries.byId(id), windows: [], pinned: true, recent: false };
            order.push(id);
        }
        for (const t of tops) {
            const k = keyFor(t);
            if (!byKey[k]) {
                byKey[k] = { key: k, entry: DesktopEntries.heuristicLookup(t.appId), windows: [], pinned: false, recent: false };
                order.push(k);
            }
            byKey[k].windows.push(t);
        }
        // Drop pins whose desktop entry no longer exists and isn't running.
        return order.map(k => byKey[k]).filter(g => g.entry || g.windows.length > 0);
    }

    readonly property var recentGroups: {
        void DesktopEntries.applications.values;
        const have = new Set(groups.map(g => g.key));
        return (Settings.dock.recents || []).filter(k => !have.has(k))
            .map(k => ({ key: k, entry: DesktopEntries.byId(k), windows: [], pinned: false, recent: true }))
            .filter(g => g.entry).slice(0, 3);
    }

    // Unpinned apps whose last window closed become "recent".
    property var lastRunning: []
    onGroupsChanged: {
        const running = groups.filter(g => !g.pinned && g.windows.length > 0).map(g => g.key);
        const gone = lastRunning.filter(k => running.indexOf(k) < 0 && !Pins.isPinned(k));
        lastRunning = running;
        if (!gone.length) return;
        const rec = gone.concat((Settings.dock.recents || []).filter(k => gone.indexOf(k) < 0)).slice(0, 6);
        Settings.set("dock.recents", rec);
    }
}
