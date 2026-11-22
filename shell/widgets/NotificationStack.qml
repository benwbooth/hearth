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
    // Every card's full height, by index (each card reports its own), so
    // the layout is plain bindings: it can't go stale when the stack is
    // rebuilt (a new notification rebuilds Notification Center's stacks;
    // an imperative relayout ran before the cards existed and left them
    // all piled at the top, text over text).
    property var heights: []
    function setHeight(i, h) {
        if (heights[i] === h) return;
        const a = heights.slice();
        a[i] = h;
        heights = a;
    }
    readonly property real topH: heights[0] || 0
    function yOf(i) {
        let y = headerH;
        for (let k = 0; k < i; k++) y += (heights[k] || 0) + spacing;
        return y;
    }
    implicitHeight: count === 0 ? 0
        : stacked ? topH + Math.min(count - 1, 2) * peek
        : yOf(count - 1) + (heights[count - 1] || 0)
    Behavior on implicitHeight { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
    // No animation while it is first laid out.
    property bool ready: false
    Component.onCompleted: Qt.callLater(() => stack.ready = true)

    HoverHandler { id: hov }

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

        NotificationCard {
            id: card
            required property var modelData
            required property int index
            n: modelData
            z: stack.count - index
            // Peeking out from under the top card of a collapsed stack:
            // blank glass, narrower and dimmer, only its bottom edge shows.
            readonly property bool behind: stack.stacked && index > 0
            readonly property int k: Math.min(index, 2)
            readonly property real sliverH: Math.min(fullHeight, Theme.notificationRadius * 2 + stack.peek)
            readonly property real ty: behind ? stack.topH + k * stack.peek - sliverH
                                     : stack.stacked ? 0 : stack.yOf(index)
            x: behind ? k * stack.inset : 0
            y: ty
            width: stack.width - 2 * (behind ? k * stack.inset : 0)
            height: behind ? sliverH : fullHeight
            opacity: !behind ? 1 : index <= 2 ? 1 - 0.12 * k : 0
            // Only what shows below the card in front of it.
            clipTop: behind ? Math.max(0, stack.topH + (k - 1) * stack.peek - 5 - ty) : 0
            Component.onCompleted: stack.setHeight(index, fullHeight)
            onFullHeightChanged: stack.setHeight(index, fullHeight)
            Behavior on x { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: stack.ready; NumberAnimation { duration: stack.animMs; easing.type: Easing.OutCubic } }
            Behavior on opacity { enabled: stack.ready; NumberAnimation { duration: stack.animMs } }
            visible: opacity > 0.01
            contentShown: !behind
            closeTip: stack.stacked ? "Clear all " + stack.count + " of " + stack.group.app + "'s notifications" : "Clear this notification"
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
