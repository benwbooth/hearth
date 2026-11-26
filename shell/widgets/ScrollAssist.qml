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
    property real lastT: 0
    function clampY(y) { return Math.max(root.minY, Math.min(root.maxY, y)); }
    function clampFor(f, y) { return Math.max(f.originY, Math.min(Math.max(0, f.contentHeight - f.height) + f.originY, y)); }
    // The list this scroll goes to: the innermost Flickable under the
    // pointer (x, y in this item) that can still move by dy, else ours.
    property var last: null
    function pick(x, y, dy) {
        // (No direction yet, as a swipe's first event can be: any list that
        // scrolls at all.)
        const canMove = f => f.contentHeight > f.height + 1
            && (dy === 0 ? true : dy > 0 ? f.contentY < Math.max(0, f.contentHeight - f.height) + f.originY - 0.5 : dy < 0 ? f.contentY > f.originY + 0.5 : false);
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

    // Touchpad samples of this swipe [{t, dy}], and the glide it started on.
    property var samples: []
    property real carry: 0
    // The swipe's speed (content px/s) from its last ~80 ms of events: the
    // first event has no previous one to time against, so it isn't timed on
    // its own (a quick swipe is only a few events).
    function swipeVelocity(now) {
        const s = root.samples.filter(e => now - e.t < 100);
        if (!s.length) return 0;
        let sum = 0;
        for (const e of s) sum += e.dy;
        const n = s.length;
        const span = s[n - 1].t - s[0].t;
        // n events cover n-1 gaps; one event alone: assume one 12 ms gap.
        const dt = n > 1 && span > 0 ? span * n / (n - 1) : 12;
        return sum / (Math.max(8, dt) / 1000);
    }

    // One wheel event: pixel deltas (touchpad), angle deltas (mouse), phase,
    // at x, y in this item. (Split out of the handler so tests can replay
    // real touchpad sequences with their timing.)
    function wheel(x, y, pdy, ady, phase, now) {
        const dir = pdy !== 0 ? -pdy : -ady;
        // (A scroll in progress stays with its list until it pauses.)
        const f = root.last && now - root.lastT < 200 && phase !== Qt.ScrollBegin ? root.last : root.pick(x, y, dir);
        if (f !== root.last) { root.samples = []; root.carry = 0; root.lastT = 0; }
        root.last = f;
        if (pdy !== 0 || phase === Qt.ScrollBegin || phase === Qt.ScrollUpdate || phase === Qt.ScrollEnd) {
            // Touchpad: follow the fingers. Touching stops a glide (as on a
            // Mac), but a swipe the same way while it glided adds to it.
            if (f.flicking) {
                const glide = -f.verticalVelocity;
                root.carry = Math.abs(glide) > 60 ? glide : 0;
                f.cancelFlick();
            }
            if (root.lastT === 0 || now - root.lastT > 200) root.samples = [];
            const dy = -pdy;
            if (dy !== 0) {
                f.contentY = root.clampFor(f, f.contentY + dy);
                root.samples = root.samples.concat([{ t: now, dy: dy }]).slice(-12);
            }
            root.lastT = now;
            // Fingers lifted: glide on.
            if (phase === Qt.ScrollEnd) {
                let v = root.swipeVelocity(now);
                if (root.carry !== 0 && Math.sign(root.carry) === Math.sign(v)) v += root.carry;
                if (Math.abs(v) > 60) f.flick(0, -v);
                root.samples = [];
                root.carry = 0;
                root.lastT = 0;
            }
        } else if (ady !== 0) {
            // Mouse wheel: a smooth glide per notch (120 = one notch),
            // adding up while the wheel keeps turning.
            const add = -ady / 120 * 1600;
            const v = f.flicking && Math.sign(-f.verticalVelocity) === Math.sign(-add) ? -f.verticalVelocity : 0;
            f.flick(0, -(v + add));
        }
        root.poke();
    }

    WheelHandler {
        target: null
        enabled: root.scrollable
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            root.wheel(point.position.x, point.position.y, event.pixelDelta.y, event.angleDelta.y, event.phase, Date.now());
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
