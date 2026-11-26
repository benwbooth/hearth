import QtQuick
import ".."

// macOS-style scrolling for a Flickable, put next to it (not inside: a
// Flickable's children scroll with its content):
//
//   Flickable { id: list; ... }
//   ScrollAssist { flickable: list }
//
// - An overlay scroll bar: thin, shown while scrolling or when the pointer
//   comes near the right edge, fading out a moment after; it widens under
//   the pointer and can be dragged.
// - Momentum: touchpad scrolling follows the fingers and keeps gliding
//   after they lift (Wayland sends no momentum of its own: libinput leaves
//   that to the app); a mouse wheel glides smoothly instead of jumping.
// - Nested lists: this sits above everything in its Flickable, so it gets
//   the wheel first; it scrolls the innermost list under the pointer that
//   can still move that way (a list inside a scrolling page), and the page
//   itself only when none can (as browsers chain scrolling).
Item {
    id: root
    required property Flickable flickable
    anchors.fill: flickable
    z: (flickable ? flickable.z : 0) + 1

    readonly property bool scrollable: !!flickable && flickable.contentHeight > flickable.height + 1
    readonly property real maxY: flickable ? Math.max(0, flickable.contentHeight - flickable.height) + flickable.originY : 0
    readonly property real minY: flickable ? flickable.originY : 0

    // --- momentum ---------------------------------------------------------
    property real velocity: 0      // content px/s, positive = scrolling down
    property real lastT: 0
    function clampY(y) { return Math.max(root.minY, Math.min(root.maxY, y)); }
    function clampFor(f, y) { return Math.max(f.originY, Math.min(Math.max(0, f.contentHeight - f.height) + f.originY, y)); }
    // The list this scroll goes to: the innermost Flickable under the
    // pointer (x, y in this item) that can still move by dy, else ours.
    property var last: null
    function pick(x, y, dy) {
        const canMove = f => f.contentHeight > f.height + 1
            && (dy > 0 ? f.contentY < Math.max(0, f.contentHeight - f.height) + f.originY - 0.5 : dy < 0 ? f.contentY > f.originY + 0.5 : false);
        let found = null;
        let item = root.flickable.contentItem;
        let p = root.mapToItem(item, x, y);
        for (let depth = 0; item && depth < 64; depth++) {
            const c = item.childAt(p.x, p.y);
            if (!c) break;
            p = item.mapToItem(c, p.x, p.y);
            item = c;
            // Another ScrollAssist (it covers its list), or a list itself.
            const f = c.flickable !== undefined && c.flickable && c.flickable.contentItem ? c.flickable
                    : (c.contentItem !== undefined && c.contentY !== undefined && typeof c.flick === "function") ? c : null;
            if (f && f !== root.flickable && canMove(f)) found = f;
            if (f && f !== c) { item = f.contentItem; p = c.mapToItem(item, p.x, p.y); }
        }
        return found || root.flickable;
    }

    WheelHandler {
        target: null
        enabled: root.scrollable
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const dir = event.pixelDelta.y !== 0 ? -event.pixelDelta.y : -event.angleDelta.y;
            // (A scroll in progress stays with its list until it pauses.)
            const now = Date.now();
            const f = root.last && now - root.lastT < 200 && event.phase !== Qt.ScrollBegin ? root.last : root.pick(point.position.x, point.position.y, dir);
            if (f !== root.last) { root.velocity = 0; root.lastT = 0; }
            root.last = f;
            if (event.pixelDelta.y !== 0 || event.phase === Qt.ScrollUpdate || event.phase === Qt.ScrollEnd) {
                // Touchpad: follow the fingers, remember how fast they went.
                if (f.flicking) f.cancelFlick();
                const dy = -event.pixelDelta.y;
                if (dy !== 0) {
                    f.contentY = root.clampFor(f, f.contentY + dy);
                    const dt = Math.max(1, now - root.lastT) / 1000;
                    const v = dy / dt;
                    root.velocity = root.lastT && now - root.lastT < 100 ? root.velocity * 0.6 + v * 0.4 : v;
                }
                root.lastT = now;
                // Fingers lifted: glide on.
                if (event.phase === Qt.ScrollEnd) {
                    if (Math.abs(root.velocity) > 60) f.flick(0, -root.velocity);
                    root.velocity = 0;
                    root.lastT = 0;
                }
            } else if (event.angleDelta.y !== 0) {
                // Mouse wheel: a smooth glide per notch (120 = one notch),
                // adding up while the wheel keeps turning.
                const notches = -event.angleDelta.y / 120;
                const add = notches * 1600;
                const v = f.flicking && Math.sign(-f.verticalVelocity) === Math.sign(-add) ? -f.verticalVelocity : 0;
                f.flick(0, -(v + add));
            }
            root.poke();
            event.accepted = true;
        }
    }

    // --- overlay scroll bar ------------------------------------------------
    property bool shown: false
    function poke() { root.shown = true; hideTimer.restart(); }
    Timer { id: hideTimer; interval: 900; onTriggered: if (!barArea.containsMouse && !barArea.pressed) root.shown = false }
    Connections {
        target: root.flickable
        function onContentYChanged() { root.poke(); }
    }

    // The pointer near the right edge shows it, like macOS.
    MouseArea {
        id: edgeHover
        anchors.right: parent.right
        width: 16
        height: parent.height
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: if (containsMouse && root.scrollable) root.poke()
    }

    Rectangle {
        id: bar
        visible: root.scrollable
        readonly property real track: root.height - 4
        readonly property real h: Math.max(28, root.flickable.visibleArea.heightRatio * track)
        readonly property real frac: root.maxY > root.minY ? (root.flickable.contentY - root.minY) / (root.maxY - root.minY) : 0
        x: parent.width - width - 2
        y: 2 + Math.max(0, Math.min(1, frac)) * (track - h)
        width: barArea.containsMouse || barArea.pressed ? 9 : 6
        height: h
        radius: width / 2
        color: Theme.dark ? Qt.rgba(1, 1, 1, barArea.pressed ? 0.6 : 0.42) : Qt.rgba(0, 0, 0, barArea.pressed ? 0.55 : 0.38)
        opacity: root.shown || barArea.containsMouse || barArea.pressed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.shown ? 120 : 300; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 120 } }

        MouseArea {
            id: barArea
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            enabled: bar.opacity > 0.05
            property real grabY: 0
            property real startY: 0
            onPressed: mouse => { grabY = mapToItem(root, 0, mouse.y).y; startY = root.flickable.contentY; root.flickable.cancelFlick(); }
            onPositionChanged: mouse => {
                if (!pressed) return;
                const dy = mapToItem(root, 0, mouse.y).y - grabY;
                const span = bar.track - bar.h;
                if (span > 0) root.flickable.contentY = root.clampY(startY + dy / span * (root.maxY - root.minY));
            }
            onReleased: root.poke()
        }
    }
}
