import QtQuick
import Quickshell
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
//   that to the app), as grove's Kinetic.qml; a swipe during a glide starts
//   a new one. A mouse wheel glides smoothly instead of jumping.
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

    // Touchpad momentum, grove's (Kinetic.qml, Chrome's physics on Linux):
    // the content follows the fingers; the release speed is a smoothed
    // average of the last moves; then a constant-deceleration glide of our
    // own, frame by frame. Fingers lifted = Qt's ScrollEnd, or no event for
    // 45 ms (not every compositor sends the end). A new swipe stops the
    // glide and starts its own, at its own speed.
    property var glider: null           // the Flickable gliding
    property real glideV: 0             // px/s, positive = down
    property real pixelV: 0
    property double lastPixelTime: 0
    readonly property real maxV: 9000
    readonly property real decel: 2300  // px/s²
    function stopGlide() { glide.stop(); release.stop(); root.glideV = 0; root.pixelV = 0; root.lastPixelTime = 0; }
    function applyPixels(f, dy, now) {
        glide.stop(); root.glideV = 0;
        if (f.flicking) f.cancelFlick();
        f.contentY = root.clampFor(f, f.contentY + dy);
        root.glider = f;
        const dt = root.lastPixelTime > 0 ? (now - root.lastPixelTime) / 1000 : 0;
        if (dt >= 0.004 && dt <= 0.08) {
            const inst = dy / dt;
            root.pixelV = root.pixelV === 0 ? inst : root.pixelV * 0.65 + inst * 0.35;
        } else {
            root.pixelV = dy * 60;          // first move: one frame's worth
        }
        root.pixelV = Math.max(-root.maxV, Math.min(root.maxV, root.pixelV));
        root.lastPixelTime = now;
        release.restart();
    }
    function finishPixels() {
        release.stop();
        root.lastPixelTime = 0;
        root.glideV = root.pixelV;
        root.pixelV = 0;
        if (Math.abs(root.glideV) < 40 || !root.glider) { root.glideV = 0; return; }
        glide.start();
    }
    Timer { id: release; interval: 45; onTriggered: root.finishPixels() }
    FrameAnimation {
        id: glide
        onTriggered: {
            const f = root.glider;
            const dt = Math.min(0.05, frameTime);
            if (!f) { root.stopGlide(); return; }
            if (dt <= 0) return;
            const next = root.clampFor(f, f.contentY + root.glideV * dt);
            const hit = next === f.contentY;
            f.contentY = next;
            const speed = Math.max(0, Math.abs(root.glideV) - root.decel * dt);
            root.glideV = Math.sign(root.glideV) * speed;
            if (hit || speed < 1) root.stopGlide();
        }
    }

    // The first few wheel events of each list go to the journal (as grove's
    // do), so what the compositor really sends shows up when scrolling
    // misbehaves; HEARTH_WHEEL_DEBUG=1 logs every one.
    readonly property bool wheelDebug: Quickshell.env("HEARTH_WHEEL_DEBUG") === "1"
    property int debugLeft: 4

    // One wheel event: pixel deltas (touchpad), angle deltas (mouse), phase,
    // at x, y in this item.
    function wheel(x, y, pdy, ady, phase, now) {
        if (root.wheelDebug || root.debugLeft > 0) {
            root.debugLeft--;
            console.warn("hearth wheel: pixel", pdy, "angle", ady, "phase", phase, "t", now % 100000);
        }
        // No amount (a swipe's ScrollBegin, its ScrollEnd): decides nothing,
        // except that the fingers lifted.
        if (pdy === 0 && ady === 0) {
            if (phase === Qt.ScrollEnd && root.lastPixelTime > 0) root.finishPixels();
            return;
        }
        const dir = pdy !== 0 ? -pdy : -ady;
        // (A scroll in progress stays with its list until it pauses.)
        const f = root.last && now - root.lastT < 200 ? root.last : root.pick(x, y, dir);
        if (f !== root.last && root.glider && root.glider !== f) root.stopGlide();
        root.last = f;
        root.lastT = now;
        if (pdy !== 0) {
            root.applyPixels(f, -pdy, now);
            if (phase === Qt.ScrollEnd) root.finishPixels();
        } else {
            // Mouse wheel: a smooth glide per notch (120 = one notch),
            // adding up while the wheel keeps turning.
            root.stopGlide();
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
            onPressed: mouse => { grabY = mapToItem(root, 0, mouse.y).y; startY = root.flickable.contentY; root.flickable.cancelFlick(); root.stopGlide(); }
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
