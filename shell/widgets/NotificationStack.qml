import QtQuick
import QtQuick.Layouts
import "../services"
import ".."

// One app's notifications in Notification Center, macOS style. Collapsed,
// the newest card sits on top with up to two more peeking out from under
// it; clicking the stack fans it out. Expanded, the app's name heads the
// list with "Show less" and ✕ (clear them all) on hover. A single
// notification is just its card: click runs it, ✕ clears it.
Item {
    id: stack
    required property var group
    readonly property var items: group.items
    readonly property int count: items.length
    readonly property bool expanded: count > 1 && !!Notifications.expanded[group.key]
    readonly property bool stacked: count > 1 && !expanded
    readonly property real peek: Math.round(9 * Theme.pt)
    readonly property real inset: Math.round(9 * Theme.pt)
    readonly property real spacing: Math.round(8 * Theme.pt)
    readonly property real headerH: expanded ? header.height + spacing : 0
    readonly property int animMs: 300
    readonly property bool hovered: hov.hovered

    width: Theme.notificationWidth
    implicitHeight: 0
    Behavior on implicitHeight { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
    property bool ready: false
    Component.onCompleted: { relayout(); ready = true; }
    onExpandedChanged: relayout()
    onCountChanged: Qt.callLater(relayout)

    HoverHandler { id: hov }

    // Card positions: fanned out in a list, or stacked under the newest.
    function relayout() {
        let y = headerH;
        const top = rep.itemAt(0);
        const topH = top ? top.fullHeight : 0;
        for (let i = 0; i < rep.count; i++) {
            const c = rep.itemAt(i);
            if (!c) continue;
            if (!stacked || i === 0) {
                c.tx = 0; c.tw = width; c.ty = stacked ? 0 : y; c.th = c.fullHeight; c.to = 1; c.clipTop = 0;
                y += c.fullHeight + spacing;
            } else {
                const k = Math.min(i, 2);
                const h = Math.min(c.fullHeight, Theme.notificationRadius * 2 + peek);
                c.tx = k * inset; c.tw = width - 2 * k * inset;
                c.th = h;
                c.ty = topH + k * peek - h;
                // Only what shows below the card in front of it.
                c.clipTop = Math.max(0, topH + (k - 1) * peek - 5 - c.ty);
                c.to = i <= 2 ? 1 - 0.12 * k : 0;
            }
        }
        implicitHeight = stacked ? topH + Math.min(count - 1, 2) * peek : Math.max(0, y - spacing);
    }

    // Header of an expanded stack.
    RowLayout {
        id: header
        width: parent.width
        opacity: stack.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        spacing: Math.round(6 * Theme.pt)
        GlassPill {
            text: stack.group.app
            fontSize: Theme.macPt(13)
            tooltip: "Show less"
            onClicked: Notifications.setExpanded(stack.group.key, false)
            Layout.maximumWidth: stack.width * 0.6
        }
        Item { Layout.fillWidth: true }
        GlassPill {
            text: "Show less"
            tooltip: "Stack " + stack.group.app + "'s notifications again"
            opacity: stack.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            onClicked: Notifications.setExpanded(stack.group.key, false)
        }
        CloseBadge {
            implicitWidth: Math.round(24 * Theme.pt)
            shown: stack.hovered
            tooltip: "Clear all of " + stack.group.app + "'s notifications"
            onClicked: Notifications.clearGroup(stack.group.key)
        }
    }

    Repeater {
        id: rep
        model: stack.items
        onItemAdded: Qt.callLater(stack.relayout)
        onItemRemoved: Qt.callLater(stack.relayout)

        NotificationCard {
            id: card
            required property var modelData
            required property int index
            n: modelData
            z: stack.count - index
            property real tx: 0
            property real ty: stack.headerH
            property real tw: stack.width
            property real th: fullHeight
            property real to: 1
            x: tx; y: ty; width: tw; height: th; opacity: to
            Behavior on x { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
            Behavior on opacity { enabled: stack.ready; NumberAnimation { duration: stack.animMs } }
            visible: opacity > 0.01
            contentShown: !stack.stacked || index === 0
            closeTip: stack.stacked ? "Clear all " + stack.count + " of " + stack.group.app + "'s notifications" : "Clear this notification"
            onFullHeightChanged: Qt.callLater(stack.relayout)
            onClicked: {
                if (stack.stacked) Notifications.setExpanded(stack.group.key, true);
                else Notifications.activate(n);
            }
            onCloseClicked: {
                if (stack.stacked) Notifications.clearGroup(stack.group.key);
                else Notifications.dismiss(n);
            }
        }
    }
}
