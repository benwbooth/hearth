import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// The macOS-style dock (layout "mac"): pinned apps, a divider, running and
// recently used apps, and (unless "minimize into application icon")
// minimized windows. Bottom, left or right edge; magnifies under the
// pointer; auto-hides (shown when the pointer touches the screen edge,
// hidden `autohideDelay` ms after it leaves, kept up while one of its menus
// or previews is open). Drag a pinned icon to reorder it, drag it out of the
// dock to remove it, drag a running app among the pins to keep it.
// All of it is set in Settings > Dock (services/Settings.qml `dockWin.*`).
PanelWindow {
    id: dockWin
    required property ShellScreen modelData
    screen: modelData

    readonly property var cfg: Settings.dock
    readonly property string edge: ["left", "right"].indexOf(cfg.position) >= 0 ? cfg.position : "bottom"
    readonly property bool vertical: edge !== "bottom"
    // The set size, shrunk when every app wouldn't fit along the edge.
    readonly property int appCount: TaskGroups.groups.length + (cfg.showRecents ? TaskGroups.recentGroups.length : 0)
    readonly property int fitSize: Math.floor(((vertical ? height : width) - 60 - 2 * 17) / Math.max(1, appCount)) - 10
    readonly property int iconSize: Math.max(20, Math.min(128, cfg.size, fitSize))
    // macOS 26 proportions (README "Look"): icons ~17% apart (macOS icon
    // art has its own margin, most Linux icons fill their square), a slab
    // a third of an icon thicker than the icons with the running dots in
    // its lower padding, corners ~38% of its thickness, floating 4 pt off
    // the screen edge.
    readonly property real cell: iconSize + Math.round(iconSize * 0.17)
    readonly property real sepLen: Math.round(iconSize * 0.36)
    readonly property real pad: Math.round(iconSize * 0.12)
    readonly property real thickness: iconSize + Math.round(iconSize / 3)
    readonly property real margin: Math.round(4 * Theme.pt)
    readonly property real maxZoom: cfg.magnify ? Math.max(1, cfg.magnifySize / iconSize) : 1
    readonly property real extra: iconSize * (maxZoom - 1)
    // Room above the icons for the app-name label (drawn inside this
    // surface, so hovering never maps or unmaps popup windows).
    // Side docks put it beside the icons, so they need the label's width.
    readonly property real labelSpace: vertical ? 300 : 64
    readonly property real winThickness: margin + thickness + extra + 14 + labelSpace
    readonly property bool autohide: cfg.autohide

    // Read by BarPopup: popups clear the dock when it reserves no space.
    readonly property int popupGap: autohide ? margin + thickness : 0

    anchors {
        bottom: dockWin.edge === "bottom"
        left: dockWin.edge !== "right"
        right: dockWin.edge !== "left"
        top: dockWin.vertical
    }
    implicitHeight: vertical ? 0 : winThickness
    implicitWidth: vertical ? winThickness : 0
    exclusionMode: autohide ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: autohide ? 0 : margin + thickness
    color: "transparent"
    WlrLayershell.namespace: "hearth-dock"
    WlrLayershell.layer: WlrLayer.Top
    // While one of its menus is open the dock takes the keyboard under the
    // pointer and hands keys to the menu (arrows, Return, Esc, type-ahead),
    // like the menu bar.
    WlrLayershell.keyboardFocus: menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    Item {
        focus: true
        Keys.onPressed: event => {
            const a = ShellState.activePopup;
            if (a && a.open && a.barWindow === dockWin) a.handleKey(event);
        }
    }
    // Input only on the dock itself; hidden, a 4 px strip along the edge.
    mask: Region { item: dockWin.shown ? frameMask : trigger }
    // The slab's resting geometry out to the screen edge (so the pointer
    // can rest on the edge), outside the sliding (transformed) body:
    // Region doesn't follow transforms.
    // While magnified it also takes in the band the grown icons reach into,
    // as on macOS: moving up onto a magnified icon kept it magnified there,
    // but here the pointer left the input region and the zoom fell away.
    Item {
        id: frameMask
        readonly property real band: dockWin.extra * dockWin.magLevel
        x: dockWin.edge === "left" ? 0 : frame.x - (dockWin.edge === "right" ? band : 0)
        y: frame.y - (dockWin.vertical ? 0 : band)
        width: dockWin.vertical ? dockWin.width - (dockWin.edge === "left" ? 0 : frame.x - band) : frame.width
        height: dockWin.vertical ? frame.height : dockWin.height - frame.y + band
    }

    // --- show / hide ---
    property int previews: 0
    readonly property bool menuOpen: !!ShellState.activePopup && ShellState.activePopup.open && ShellState.activePopup.barWindow === dockWin
    property bool held: false
    // `held` goes up when the pointer touches the edge strip or the dock and
    // drops `autohideDelay` ms after it leaves.
    // Always up in the overview, like macOS's Mission Control.
    readonly property bool shown: !autohide || held || menuOpen || previews > 0 || dragKey !== "" || Compositor.overviewOpen
    // True once the slide-in has finished (the name label waits for it).
    property bool settled: false
    Component.onCompleted: settled = shown
    onShownChanged: { if (shown) slideInTimer.restart(); else { slideInTimer.stop(); settled = false; } }
    Timer { id: slideInTimer; interval: Math.max(0, Number(dockWin.cfg.animationMs) || 0) + 20; onTriggered: dockWin.settled = true }
    Timer {
        id: hideTimer
        interval: Math.max(0, dockWin.cfg.autohideDelay)
        onTriggered: if (!hover.hovered) dockWin.held = false
    }
    // macOS waits `autohide-delay` (0.5 s by default) after the pointer
    // reaches the edge before the Dock comes out (Settings > Dock).
    Timer {
        id: showTimer
        interval: Math.max(0, Number(dockWin.cfg.showDelay) || 0)
        onTriggered: if (edgeHover.hovered || hover.hovered) { dockWin.held = true; hideTimer.stop(); }
    }
    Connections {
        target: hover
        function onHoveredChanged() {
            if (hover.hovered) {
                if (dockWin.shown) { dockWin.held = true; hideTimer.stop(); }
                // Hidden, the input region is only the edge strip, so any
                // hover here is the pointer touching the edge. The strip's
                // own HoverHandler never fired at Ben's 4/3 scale (the
                // pointer's last row and the 2 px strip didn't overlap), so
                // the dock never came out.
                else if (dockWin.autohide) {
                    if (showTimer.interval <= 0) { dockWin.held = true; hideTimer.stop(); }
                    else if (!showTimer.running) showTimer.restart();
                }
            }
            else { showTimer.stop(); hideTimer.restart(); }
        }
    }
    onPreviewsChanged: if (previews === 0 && !hover.hovered) hideTimer.restart()
    onMenuOpenChanged: if (!menuOpen && !hover.hovered) hideTimer.restart()

    // Peek: `hearth-ipc call dock reveal|hide|toggle` (binds, tests).
    IpcHandler {
        target: ShellState.isActiveScreen(dockWin.screen) ? "dock" : ""
        function reveal(): void { dockWin.held = true; hideTimer.restart(); }
        function hide(): void { dockWin.held = false; }
        // Tests: show the drag preview for app `key` held at `x` (window
        // coordinates along the dock), as if dragged there; dragEnd drops it.
        function dragAt(key: string, x: real, out: bool): void {
            const t = { modelData: { key: key }, entry: DesktopEntries.byId(key) };
            const p = dockWin.vertical ? Qt.point(dockWin.width / 2, x) : Qt.point(x, out ? 0 : dockWin.height - dockWin.margin - dockWin.thickness / 2);
            if (dockWin.dragKey !== key) dockWin.dragHost.begin(t, p);
            else dockWin.dragHost.move(t, p);
        }
        function dragEnd(): void { dockWin.drop(dockWin.dragPos); }
        function toggle(): void { dockWin.held = !dockWin.held; }
        function state(): string {
            return JSON.stringify({ shown: dockWin.shown, held: dockWin.held, hovered: hover.hovered, pointer: dockWin.pointer,
                                    frame: [frameMask.x, frameMask.y, frameMask.width, frameMask.height],
                                    win: [dockWin.width, dockWin.height], previews: dockWin.previews, hot: (() => { const o = []; for (let k = 0; k < rep.count; k++) { const it = rep.itemAt(k); if (it && it.task && it.task.containsMouse) o.push(it.modelData.key + "@" + Math.round(it.x) + "+" + Math.round(it.width)); } return o; })(), drag: [dockWin.dragKey, dockWin.dragIndex, dockWin.dragOut] });
        }
    }

    // Hidden, the pointer reveals the dock by touching the screen edge
    // under it (like macOS). It must lie inside frameMask, so showing the
    // dock never moves the input region out from under a resting pointer
    // (that toggled show/hide in a loop along the rest of the edge).
    Item {
        id: trigger
        // 4 px: at a fractional scale (Ben's 4/3) the pointer's last row
        // can fall outside a 2 px strip.
        x: dockWin.vertical ? (dockWin.edge === "right" ? parent.width - 4 : 0) : frameMask.x
        y: dockWin.vertical ? frameMask.y : parent.height - 4
        width: dockWin.vertical ? 4 : frameMask.width
        height: dockWin.vertical ? frameMask.height : 4
        HoverHandler {
            id: edgeHover
            onHoveredChanged: {
                if (!hovered) { showTimer.stop(); return; }
                if (showTimer.interval <= 0 || dockWin.shown) { dockWin.held = true; hideTimer.stop(); }
                else showTimer.restart();
            }
        }
    }

    // --- model ---
    // The slot list never changes during a drag (that would recreate the
    // dragged delegate, which holds the pointer grab); the drag preview is
    // done in `geo` instead: the dragged slot collapses and a gap opens
    // where it would land, so the neighbours slide aside live.
    readonly property var slots: {
        const out = [];
        const all = TaskGroups.groups;
        const pinned = all.filter(g => g.pinned);
        const rest = all.filter(g => !g.pinned).concat(cfg.showRecents ? TaskGroups.recentGroups : []);
        for (const g of pinned) out.push({ key: g.key, kind: "app", group: g, pinned: true });
        if (rest.length) {
            if (out.length) out.push({ key: "sep:apps", kind: "sep" });
            for (const g of rest) out.push({ key: g.key, kind: "app", group: g, pinned: false });
        }
        if (!cfg.minimizeIntoApp) {
            // Minimized: arbor reports it per window; elsewhere the
            // foreign-toplevel state.
            const mins = Compositor.isArbor
                ? Compositor.windows.filter(w => w.minimized && w.toplevel).map(w => w.toplevel)
                : ToplevelManager.toplevels.values.filter(t => t.minimized);
            if (mins.length) {
                out.push({ key: "sep:min", kind: "sep" });
                for (const t of mins) out.push({ key: "min:" + (t.appId || "") + ":" + mins.indexOf(t), kind: "min", toplevel: t });
            }
        }
        let pos = 0;
        for (const s of out) {
            s.len = s.kind === "sep" ? sepLen : cell;
            s.base = pos;
            pos += s.len;
        }
        return out;
    }
    readonly property real baseLength: slots.length ? slots[slots.length - 1].base + slots[slots.length - 1].len : cell
    readonly property real axisLength: vertical ? height : width
    readonly property real baseStart: Math.round((axisLength - baseLength) / 2)

    // Magnification, as on macOS: one smooth lens along the dock. Every
    // point x of the resting layout is drawn at F(x) = x + A·G(x − pointer),
    // G being the integral of a cosine bump (zoom 1 + A·bump), so F(pointer)
    // = pointer: the spot under the pointer never moves, and each slot's
    // drawn start and end, and so its size, come from the same curve.
    // Neighbours move together, nothing feeds back (the pointer is read
    // in resting coordinates), and the ends of the dock stay put while the
    // pointer sweeps across it (zooming slots one by one, the sum of their
    // growth rose and fell with the pointer's place inside a cell, so the
    // whole dock breathed by a fraction of a pixel per frame: the wobble).
    // `magLevel` eases the whole effect in and out, so nothing snaps when
    // the pointer arrives or leaves.
    readonly property bool tracking: hover.hovered && cfg.magnify && dragKey === ""
    readonly property real livePointer: hover.hovered
        ? (vertical ? hover.point.position.y : hover.point.position.x) - baseStart : NaN
    // The lens follows the pointer once per rendered frame, at the moment
    // the frame starts (like macOS): a 1000 Hz mouse moved it six times per
    // 165 Hz frame, each time re-laying out every icon (~0.45 ms each).
    property real pointer: 0
    property bool pointerPending: false
    onLivePointerChanged: if (!isNaN(livePointer) && !pointerPending) {
        pointerPending = true;
        body.Window.window?.update();
    }
    Connections {
        target: body.Window.window
        function onAfterAnimating() {
            if (!dockWin.pointerPending) return;
            dockWin.pointerPending = false;
            if (!isNaN(dockWin.livePointer)) dockWin.pointer = dockWin.livePointer;
        }
    }
    property real magLevel: 0
    // Slots ease to new places (reorder, drag gap, apps coming and going)
    // only while magnification is at rest: the magnify easing already moves
    // them every frame, and a 260 ms slide chasing that moving target made
    // the icons wobble as the dock grew and shrank.
    readonly property bool slide: !tracking && (magLevel === 0 || dragKey !== "")
    // macOS grows the icons quickly when the pointer arrives and settles
    // them a little slower when it leaves; in between they follow the
    // pointer with no lag.
    // (Two animations started from onTrackingChanged: a Behavior read its
    // duration before `tracking` had changed, so the zoom left in the
    // arrival's 150 ms and dropped a fifth of the way in the first frame.)
    // Both ease in and out: an OutQuad start jumped 20% in one frame.
    onTrackingChanged: {
        magOut.stop(); magIn.stop();
        (tracking ? magIn : magOut).start();
    }
    NumberAnimation { id: magIn; target: dockWin; property: "magLevel"; to: 1; duration: 160; easing.type: Easing.InOutQuad }
    NumberAnimation { id: magOut; target: dockWin; property: "magLevel"; to: 0; duration: 260; easing.type: Easing.InOutQuad }
    // Half-width of the lens: about 2.6 icons each side, like macOS.
    readonly property real lensRange: cell * 2.6
    // G(x) = ∫0..x of the bump (cos(πu/R) + 1) / 2; odd, ±R/2 beyond R.
    function lensG(x) {
        const R = lensRange, a = Math.min(Math.abs(x), R);
        const g = (a + R / Math.PI * Math.sin(Math.PI * a / R)) / 2;
        return x < 0 ? -g : g;
    }
    // A is chosen so a slot centred under the pointer is drawn at exactly
    // magnifySize (its length is the lens's average over the slot).
    readonly property real lensGain: (maxZoom - 1) * cell / (2 * lensG(cell / 2))
    readonly property var geo: {
        const z = [], pos = [], lens = [];
        const A = magLevel > 0 ? lensGain * magLevel : 0;
        const p = pointer;
        const F = x => A > 0 ? x + A * lensG(x - p) : x;
        // Drag preview: collapse the dragged slot, open a gap at dragIndex
        // among the other pins (in the resting layout; magnification is
        // off while dragging).
        const gapAt = dragKey && !dragOut && dragIndex >= 0 ? dragIndex : -1;
        const collapse = dragKey && (gapAt >= 0 || (dragOut && dragWasPinned)) ? dragKey : "";
        let acc = 0, pinIdx = 0, gapDone = gapAt < 0;
        for (let i = 0; i < slots.length; i++) {
            const s = slots[i];
            const isPin = s.kind === "app" && s.pinned;
            if (!gapDone && (!isPin || (s.key !== collapse && pinIdx === gapAt))) { acc += cell; gapDone = true; }
            const len = s.key === collapse ? 0 : s.len;
            const a = F(s.base + acc), b = F(s.base + acc + len);
            pos.push(baseStart + a);
            lens.push(b - a);
            z.push(len > 0 ? (b - a) / len : 1);
            acc += len - s.len;
            if (isPin && s.key !== collapse) pinIdx++;
        }
        const start = pos.length ? pos[0] : baseStart;
        const end = pos.length ? pos[pos.length - 1] + lens[lens.length - 1] : baseStart + cell;
        return { zoom: z, pos: pos, len: lens, start: start, end: Math.max(end, start + cell) };
    }

    // The slot under the pointer, from the drawn layout.
    readonly property int hotIndex: {
        if (!hover.hovered || dragKey !== "") return -1;
        const p = livePointer + baseStart;
        for (let i = 0; i < slots.length; i++)
            if (slots[i].kind === "app" && p >= geo.pos[i] && p < geo.pos[i] + geo.len[i]) return i;
        return -1;
    }

    // Super+N activates the Nth app.
    IpcHandler {
        target: Settings.mac && ShellState.isActiveScreen(dockWin.screen) ? "tasks" : ""
        function activate(n: int): void {
            let i = 0;
            for (let k = 0; k < rep.count; k++) {
                const it = rep.itemAt(k);
                if (it && it.task) { i++; if (i === n) { it.task.trigger(); return; } }
            }
        }
    }

    // --- drag to reorder / remove ---
    property string dragKey: ""
    property bool dragWasPinned: false
    property point dragPos
    property bool dragOut: false
    property int dragIndex: -1
    property real dragStart: 0      // where the first pin starts, at drag start
    property int dragPins: 0        // pins other than the dragged one
    property string dragIcon: ""
    property var seen: ({})          // keys that have had a delegate
    readonly property var dragHost: ({
        begin: (task, p) => {
            const key = task.modelData.key;
            const first = dockWin.slots.find(s => s.kind === "app");
            dockWin.dragStart = dockWin.baseStart + (first ? first.base : 0);
            dockWin.dragWasPinned = Pins.isPinned(key);
            dockWin.dragPins = TaskGroups.groups.filter(g => g.pinned && g.key !== key).length;
            dockWin.dragIcon = task.entry ? task.entry.icon : "";
            dockWin.dragPos = p;
            dockWin.dragIndex = -1;
            dockWin.dragOut = false;
            dockWin.dragKey = key;
            dockWin.dragHost.move(task, p);
        },
        move: (task, p) => {
            dockWin.dragPos = p;
            const off = dockWin.edge === "left" ? p.x - (dockWin.margin + dockWin.thickness)
                      : dockWin.edge === "right" ? (dockWin.width - dockWin.margin - dockWin.thickness) - p.x
                      : (dockWin.height - dockWin.margin - dockWin.thickness) - p.y;
            dockWin.dragOut = off > 60;
            const along = (dockWin.vertical ? p.y : p.x) - dockWin.dragStart;
            const idx = Math.floor(along / dockWin.cell + 0.5);
            // Unpinned apps only join the pins when dropped among them.
            const inPins = along < (dockWin.dragPins + 0.5) * dockWin.cell;
            dockWin.dragIndex = dockWin.dragWasPinned || inPins ? Math.max(0, Math.min(dockWin.dragPins, idx)) : -1;
        },
        end: (task, p) => dockWin.drop(p),
        cancel: task => { dockWin.dragKey = ""; dockWin.dragIndex = -1; dockWin.dragOut = false; }
    })

    // The dropped app reorders first, while its slot is still hidden, and
    // then appears in place: clearing the drag first put it back in its old
    // slot for a moment and slid it (running dot and all) across its
    // neighbours to the new one.
    property string settleKey: ""
    Timer { id: settleTimer; interval: 50; onTriggered: dockWin.settleKey = "" }
    function drop(p) {
        const key = dragKey, idx = dragIndex, out = dragOut;
        if (key && !out && idx >= 0) {
            settleKey = key;
            if (!dragWasPinned) Pins.pin(key);
            Pins.move(key, idx);
        }
        dragKey = "";
        dragIndex = -1;
        dragOut = false;
        if (settleKey) settleTimer.restart();
        if (key && out && dragWasPinned) { Pins.unpin(key); poof.at(p); }
    }

    // Tests: HEARTH_DOCK_TRACE=1 logs the drawn layout every frame
    // ("docktrace" lines: ms, pointer, magLevel, slab start/width, then
    // each slot's start and length) for measuring magnification smoothness.
    FrameAnimation {
        running: !!Quickshell.env("HEARTH_DOCK_TRACE")
        onTriggered: {
            const o = [Date.now(), dockWin.pointer.toFixed(2), dockWin.magLevel.toFixed(4),
                       (dockWin.vertical ? frame.y : frame.x).toFixed(2), (dockWin.vertical ? frame.height : frame.width).toFixed(2)];
            for (let k = 0; k < rep.count; k++) {
                const it = rep.itemAt(k);
                if (!it) continue;
                let s = (dockWin.vertical ? it.y : it.x).toFixed(2) + ":" + (dockWin.vertical ? it.height : it.width).toFixed(2);
                // Where the icon image itself lands (centre along the dock).
                const im = it.task && it.task.iconItem;
                if (im) { const c = im.mapToItem(null, im.width / 2, im.height / 2); s += ":" + (dockWin.vertical ? c.y : c.x).toFixed(2); }
                o.push(s);
            }
            console.log("docktrace " + o.join(" "));
        }
    }

    // --- drawing ---
    Item {
        id: body
        anchors.fill: parent
        // Slide out across the edge when hidden.
        // Out past the slab's shadow too.
        readonly property real hideOffset: dockWin.shown ? 0 : dockWin.margin + dockWin.thickness + 24
        // macOS: decelerates in, accelerates out (Settings > Dock > Animation).
        readonly property int slideEase: dockWin.shown ? Easing.OutCubic : Easing.InCubic
        transform: Translate {
            x: (dockWin.edge === "left" ? -body.hideOffset : dockWin.edge === "right" ? body.hideOffset : 0) + 0.001
            y: (dockWin.edge === "bottom" ? body.hideOffset : 0) + 0.001
            Behavior on x { NumberAnimation { duration: dockWin.cfg.animationMs; easing.type: body.slideEase } }
            Behavior on y { NumberAnimation { duration: dockWin.cfg.animationMs; easing.type: body.slideEase } }
        }

        // One app-name label (macOS-style) that glides to the icon under the
        // pointer, instead of a popup window per icon: those mapped and
        // unmapped one after another as the pointer crossed the dock, which
        // read as flicker.
        Item {
            id: nameLabel
            readonly property int idx: dockWin.hotIndex
            // Only once the dock is all the way out, like macOS: the pointer at
            // the edge is already over an icon while it slides in, and the
            // label showed up first, over an empty edge.
            readonly property bool want: idx >= 0 && hover.hovered && dockWin.settled && !dockWin.menuOpen
                                         && dockWin.previews === 0 && dockWin.dragKey === ""
            property string text: ""
            // Apps that aren't open also say what they are and what a click
            // does (beginner friendly, like the old per-icon tooltips).
            property string sub: ""
            property real cx: 0
            onIdxChanged: if (idx >= 0) {
                const sl = dockWin.slots[idx];
                const g = sl && sl.group;
                text = g && g.entry ? g.entry.name : (sl ? sl.key : "");
                const open = g && g.windows && g.windows.length > 0;
                sub = !g || open ? "" : (g.entry && g.entry.comment ? g.entry.comment : "Click to open · right-click for options");
            }
            // Follow the hot icon's centre.
            readonly property real tcx: idx >= 0 ? (dockWin.geo.pos[idx] ?? 0) + (dockWin.geo.len[idx] ?? 0) / 2 : cx
            onTcxChanged: cx = tcx
            // macOS moves the label straight to the next icon; a very short
            // glide keeps it from flickering between neighbours.
            Behavior on cx { enabled: nameLabel.opacity > 0.01; NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
            visible: opacity > 0
            opacity: want ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: nameLabel.want ? Theme.labelFadeMs : 90 } }
            readonly property real maxText: dockWin.vertical ? dockWin.labelSpace - 44 : 420
            // macOS's Dock label: the app's name alone, 13 pt, in a compact
            // rounded box (6 pt corners) of dense glass.
            width: labelCol.implicitWidth + 2 * Math.round(10 * Theme.pt)
            height: labelCol.implicitHeight + Math.round(8 * Theme.pt)
            // A steady height above the magnified icons, as on macOS: it
            // followed the hot icon's own zoom, which dips ~2 px between two
            // icons, so the label bobbed as the pointer swept the dock.
            readonly property real inner: dockWin.margin + dockWin.thickness + dockWin.extra * dockWin.magLevel + Math.round(8 * Theme.pt)
            // Whole device pixels (crisp text), not whole logical ones: at 4/3
            // those are 1.33 device px, so the label moved in uneven steps.
            readonly property real dpr: dockWin.devicePixelRatio || 1
            function snap(v) { return Math.round(v * dpr) / dpr; }
            x: snap(!dockWin.vertical ? Math.max(4, Math.min(dockWin.width - width - 4, cx - width / 2))
                    : dockWin.edge === "left" ? inner : dockWin.width - inner - width)
            y: snap(dockWin.vertical ? Math.max(4, Math.min(dockWin.height - height - 4, cx - height / 2))
                    : dockWin.height - inner - height)
            GlassFrame {
                anchors.fill: parent
                radius: Math.round(6 * Theme.pt)
                tint: Theme.glassTip
                shadowBlur: 12
                shadowY: 3
            }
            Column {
                id: labelCol
                anchors.centerIn: parent
                Label {
                    id: nameText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, nameLabel.maxText)
                    elide: Text.ElideRight
                    text: nameLabel.text
                    font.pointSize: Theme.menuFontSize
                    font.letterSpacing: Theme.menuTracking
                }
                // (No description line: macOS shows the name only. What an
                // app does is in its right-click menu and in Search.)
                Label {
                    visible: false
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, nameLabel.maxText)
                    elide: Text.ElideRight
                    text: nameLabel.sub
                    color: Theme.fgSecondary
                    font.pointSize: Theme.menuSmallFontSize
                }
            }
        }

        HoverHandler { id: hover }

        // The glass slab under the icons.
        Item {
            id: frame
            readonly property real s: dockWin.geo.start - dockWin.pad
            readonly property real e: dockWin.geo.end + dockWin.pad
            x: dockWin.vertical ? (dockWin.edge === "left" ? dockWin.margin : dockWin.width - dockWin.margin - dockWin.thickness) : s
            y: dockWin.vertical ? s : dockWin.height - dockWin.margin - dockWin.thickness
            width: dockWin.vertical ? dockWin.thickness : e - s
            height: dockWin.vertical ? e - s : dockWin.thickness
            // Slide with the icons when apps come and go (not while the
            // pointer drives magnification: that has to follow it at once).
            Behavior on x { enabled: dockWin.slide && !dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: dockWin.slide && !dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: dockWin.slide && dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: dockWin.slide && dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            // The liquid-glass slab (GlassFrame): clearer than menus, with
            // the specular rim, edge lensing and a wide soft shadow.
            GlassFrame {
                id: slab
                anchors.fill: parent
                radius: Math.round(dockWin.thickness * 0.38)
                // Hyprland blurs behind the dock, arbor draws real glass
                // under the slab (services/RealGlass.qml); arbor's layer-rule
                // blur can't (it would cover the whole wide surface, see
                // arbor/hearth-layer-rules.kdl), so more tint without it.
                tint: Compositor.isHyprland || RealGlass.active ? Theme.glassDock : Theme.glassDockSolid
                // Nothing blurs the dock's whole surface, so its own shadow
                // is fine everywhere.
                shadow: true
                shadowBlur: 30
                shadowY: 8
                glow: Theme.glassGlow * 1.25
            }
        }

        // Right-click on the dock itself (not an app): the Dock menu.
        MouseArea {
            x: frame.x
            y: frame.y
            width: frame.width
            height: frame.height
            acceptedButtons: Qt.RightButton
            onClicked: mouse => {
                const p = mapToItem(body, mouse.x, mouse.y);
                menuAnchor.x = p.x;
                menuAnchor.y = p.y;
                dockMenu.toggle();
            }
        }
        Item { id: menuAnchor; width: 1; height: 1 }

        Repeater {
            id: rep
            model: ScriptModel {
                values: dockWin.slots
                objectProp: "key"
            }
            delegate: Item {
                id: slot
                required property var modelData
                required property int index
                readonly property var task: loader.item && slot.modelData.kind === "app" ? loader.item : null
                readonly property real p: dockWin.geo.pos[index] ?? 0
                readonly property real l: dockWin.geo.len[index] ?? dockWin.cell
                x: dockWin.vertical ? frame.x : p
                y: dockWin.vertical ? p : frame.y
                width: dockWin.vertical ? dockWin.thickness : l
                height: dockWin.vertical ? l : dockWin.thickness
                readonly property bool settling: slot.modelData.key === dockWin.settleKey
                Behavior on x { enabled: dockWin.slide && !dockWin.vertical && !slot.settling; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: dockWin.slide && dockWin.vertical && !slot.settling; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: dockWin.slide && !dockWin.vertical && !slot.settling; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: dockWin.slide && dockWin.vertical && !slot.settling; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                // New apps fade and grow in; the dragged one is hidden (the
                // ghost under the pointer stands in for it).
                opacity: slot.modelData.key === dockWin.dragKey || slot.settling ? 0 : appear
                // Only apps new to the dock fade in; a delegate recreated for
                // a reorder starts visible.
                property real appear: dockWin.seen[slot.modelData.key] ? 1 : 0
                Component.onCompleted: { dockWin.seen[slot.modelData.key] = true; appear = 1; }
                Behavior on appear { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 160 } }

                readonly property bool previewOpen: task ? task.previewOpen : false
                onPreviewOpenChanged: dockWin.previews += previewOpen ? 1 : -1
                Component.onDestruction: if (previewOpen) dockWin.previews -= 1

                Loader {
                    id: loader
                    anchors.fill: parent
                    sourceComponent: slot.modelData.kind === "app" ? appComp
                                   : slot.modelData.kind === "sep" ? sepComp
                                   : slot.modelData.kind === "min" ? minComp : null
                }
                Component {
                    id: appComp
                    TaskButton {
                        modelData: slot.modelData.group
                        dock: true
                        vertical: dockWin.vertical
                        iconSize: dockWin.iconSize
                        cellLength: dockWin.cell
                        thickness: dockWin.thickness
                        zoom: dockWin.geo.zoom[slot.index] ?? 1
                        maxZoom: dockWin.maxZoom
                        showIndicator: dockWin.cfg.showIndicators
                        dragHost: dockWin.dragHost
                        hostHovered: hover.hovered
                        hot: dockWin.hotIndex === slot.index
                    }
                }
                Component {
                    id: sepComp
                    Item {
                        // macOS: a hairline across ~55% of the slab.
                        Rectangle {
                            anchors.centerIn: parent
                            width: dockWin.vertical ? Math.round(parent.width * 0.55) : 1
                            height: dockWin.vertical ? 1 : Math.round(parent.height * 0.55)
                            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(0, 0, 0, 0.22)
                        }
                    }
                }
                Component {
                    id: minComp
                    MinimizedTile {
                        toplevel: slot.modelData.toplevel
                        zoom: dockWin.geo.zoom[slot.index] ?? 1
                    }
                }
            }
        }

        // The icon being dragged, and the poof when one is dropped outside.
        Icon {
            visible: dockWin.dragKey !== ""
            name: dockWin.dragIcon
            implicitSize: dockWin.iconSize
            x: dockWin.dragPos.x - width / 2
            y: dockWin.dragPos.y - height / 2
            opacity: dockWin.dragOut ? 0.5 : 0.9
            Icon {
                visible: dockWin.dragOut
                anchors.right: parent.right
                anchors.top: parent.top
                implicitSize: 18
                name: "list-remove"
            }
        }
        Item {
            id: poof
            width: dockWin.iconSize
            height: dockWin.iconSize
            opacity: 0
            function at(p) {
                x = Math.max(0, Math.min(dockWin.width - width, p.x - width / 2));
                y = Math.max(0, Math.min(dockWin.height - height, p.y - height / 2));
                anim.restart();
            }
            Repeater {
                model: 6
                Rectangle {
                    required property int index
                    readonly property real a: index * Math.PI / 3
                    width: 10 + poof.spread * 6
                    height: width
                    radius: width / 2
                    color: Theme.dark ? "#d8dde3" : "#9aa3ad"
                    x: poof.width / 2 - width / 2 + Math.cos(a) * poof.spread * 18
                    y: poof.height / 2 - height / 2 + Math.sin(a) * poof.spread * 18
                }
            }
            property real spread: 0
            ParallelAnimation {
                id: anim
                NumberAnimation { target: poof; property: "spread"; from: 0; to: 1; duration: 350; easing.type: Easing.OutQuad }
                SequentialAnimation {
                    NumberAnimation { target: poof; property: "opacity"; from: 0; to: 1; duration: 60 }
                    NumberAnimation { target: poof; property: "opacity"; to: 0; duration: 290 }
                }
            }
        }
    }

    // The Dock menu (right-click on the dock background or a divider).
    BarPopup {
        id: dockMenu
        anchorItem: menuAnchor
        padding: Theme.menuPadding
        Column {
            width: Math.round(210 * Theme.pt)
            readonly property bool menuGutter: true
            MenuItem {
                text: dockWin.cfg.autohide ? "Turn Hiding Off" : "Turn Hiding On"
                onTriggered: { dockMenu.close(); Settings.set("dock.autohide", !dockWin.cfg.autohide); }
            }
            MenuItem {
                text: dockWin.cfg.magnify ? "Turn Magnification Off" : "Turn Magnification On"
                onTriggered: { dockMenu.close(); Settings.set("dock.magnify", !dockWin.cfg.magnify); }
            }
            MenuSeparator {}
            MenuHeader { text: "Position on Screen" }
            Repeater {
                model: [{ v: "left", l: "Left" }, { v: "bottom", l: "Bottom" }, { v: "right", l: "Right" }]
                MenuItem {
                    required property var modelData
                    text: modelData.l
                    checkable: true
                    checked: dockWin.edge === modelData.v
                    onTriggered: { dockMenu.close(); Settings.set("dock.position", modelData.v); }
                }
            }
            MenuSeparator {}
            MenuItem {
                text: "Dock Settings…"
                onTriggered: { dockMenu.close(); Settings.openRequested("dock"); }
            }
        }
    }

    component MinimizedTile: MouseArea {
        id: tile
        property var toplevel
        property real zoom: 1
        readonly property var entry: toplevel ? DesktopEntries.heuristicLookup(toplevel.appId) : null
        hoverEnabled: true
        onClicked: if (toplevel) toplevel.activate()
        // Built at the largest size and scaled, so magnifying doesn't
        // re-capture the snapshot or reload the icon every frame.
        Rectangle {
            // Centred exactly (anchors.centerIn rounds to whole pixels, so
            // the tile jittered while zooming).
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
            width: Math.ceil(dockWin.iconSize * Math.max(1, dockWin.maxZoom))
            height: width * 0.75
            scale: dockWin.iconSize * tile.zoom / width
            radius: 4
            color: Theme.bgRaised
            border.color: Theme.glassEdge
            ScreencopyView {
                anchors.fill: parent
                anchors.margins: 2
                captureSource: tile.toplevel
                live: false
                constraintSize: Qt.size(width, height)
            }
            Icon {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -4
                implicitSize: parent.width * 0.45
                name: tile.entry ? tile.entry.icon : (tile.toplevel ? tile.toplevel.appId : "")
            }
        }
        Tooltip {
            anchorItem: tile
            text: tile.toplevel ? tile.toplevel.title : ""
            hovered: tile.containsMouse
        }
    }
}
