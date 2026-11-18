pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The desktop notification server (org.freedesktop.Notifications).
//
// Every notification is kept (tracked) as history until it is dismissed
// from the bell popup, the app closes it, or it is transient. `popups` is
// the list currently shown on screen; a popup timing out only drops it from
// that list (unless the notification is transient, which also expires it).
// Do Not Disturb suppresses popups except for critical notifications.
Singleton {
    id: root

    // Newest first.
    readonly property var history: {
        const v = server.trackedNotifications.values.slice();
        v.reverse();
        return v;
    }
    property var popups: []
    property int unreadCount: 0

    signal notified(var notification)

    function dismiss(n) {
        hidePopup(n);
        if (n && n.tracked) n.dismiss();
    }
    function clearAll() {
        const all = server.trackedNotifications.values.slice();
        root.popups = [];
        for (const n of all) n.dismiss();
        root.unreadCount = 0;
    }
    function markRead() { root.unreadCount = 0; }
    function hidePopup(n) {
        if (root.popups.indexOf(n) >= 0) root.popups = root.popups.filter(p => p !== n);
    }
    // Popup timed out: transient notifications go away for good.
    function expirePopup(n) {
        hidePopup(n);
        if (n && n.transient && n.tracked) n.expire();
    }
    // Invoke the "default" action (click on the body), if there is one.
    function activate(n) {
        const a = n.actions.find(x => x.identifier === "default");
        if (a) a.invoke();
        if (!n.resident) dismiss(n);
        else hidePopup(n);
    }
    function appIcon(n) {
        if (n.appIcon) return n.appIcon;
        if (n.desktopEntry) {
            const e = DesktopEntries.heuristicLookup(n.desktopEntry);
            if (e && e.icon) return e.icon;
        }
        return "preferences-desktop-notification";
    }
    function appName(n) {
        if (n.appName) return n.appName;
        if (n.desktopEntry) {
            const e = DesktopEntries.heuristicLookup(n.desktopEntry);
            if (e) return e.name;
        }
        return "Notification";
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false

        onNotification: n => {
            n.tracked = true;
            root.unreadCount += 1;
            n.closed.connect(() => {
                root.hidePopup(n);
                root.unreadCount = Math.min(root.unreadCount, server.trackedNotifications.values.length);
            });
            if (!ShellState.doNotDisturb || n.urgency === NotificationUrgency.Critical) {
                if (root.popups.indexOf(n) < 0) root.popups = root.popups.concat([n]);
            }
            root.notified(n);
        }
    }
}
