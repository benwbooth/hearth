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
    readonly property real cell: iconSize + 10
    readonly property real sepLen: 17
    readonly property real pad: 6
    readonly property real thickness: iconSize + 18
    readonly property real margin: 4
    readonly property real maxZoom: cfg.magnify ? Math.max(1, cfg.magnifySize / iconSize) : 1
    readonly property real extra: iconSize * (maxZoom - 1)
    readonly property real winThickness: margin + thickness + extra + 14
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
    // Input only on the dock itself; hidden, a 2 px strip along the edge.
    mask: Region { item: dockWin.shown ? frameMask : trigger }
    // The slab's resting geometry out to the screen edge (so the pointer
    // can rest on the edge), outside the sliding (transformed) body:
    // Region doesn't follow transforms.
    Item {
        id: frameMask
        x: dockWin.edge === "left" ? 0 : frame.x
        y: frame.y
        width: dockWin.vertical ? dockWin.width - (dockWin.edge === "left" ? 0 : frame.x) : frame.width
        height: dockWin.vertical ? frame.height : dockWin.height - frame.y
    }

    // --- show / hide ---
    property int previews: 0
    readonly property bool menuOpen: !!ShellState.activePopup && ShellState.activePopup.barWindow === dockWin
    property bool held: false
    // `held` goes up when the pointer touches the edge strip or the dock and
    // drops `autohideDelay` ms after it leaves.
    readonly property bool shown: !autohide || held || menuOpen || previews > 0 || dragKey !== ""
    Timer {
        id: hideTimer
        interval: Math.max(0, dockWin.cfg.autohideDelay)
        onTriggered: if (!hover.hovered) dockWin.held = false
    }
    Connections {
        target: hover
        function onHoveredChanged() {
            if (hover.hovered) { dockWin.held = true; hideTimer.stop(); }
            else hideTimer.restart();
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
                                    win: [dockWin.width, dockWin.height], previews: dockWin.previews, drag: [dockWin.dragKey, dockWin.dragIndex, dockWin.dragOut] });
        }
    }

    // Hidden, the pointer reveals the dock by touching the screen edge
    // under it (like macOS). It must lie inside frameMask, so showing the
    // dock never moves the input region out from under a resting pointer
    // (that toggled show/hide in a loop along the rest of the edge).
    Item {
        id: trigger
        x: dockWin.vertical ? (dockWin.edge === "right" ? parent.width - 2 : 0) : frameMask.x
        y: dockWin.vertical ? frameMask.y : parent.height - 2
        width: dockWin.vertical ? 2 : frameMask.width
        height: dockWin.vertical ? frameMask.height : 2
        HoverHandler { onHoveredChanged: if (hovered) { dockWin.held = true; hideTimer.stop(); } }
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
            const mins = Compositor.isNiri
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

    // Magnification: each slot's zoom from its distance to the pointer (in
    // the un-magnified layout, so nothing feeds back), and how far the
    // growth pushes neighbours: slots before the pointer grow toward the
    // start, slots after it toward the end. `magLevel` eases the whole
    // effect in and out, so nothing snaps when the pointer arrives or leaves.
    readonly property bool tracking: hover.hovered && cfg.magnify && dragKey === ""
    readonly property real livePointer: hover.hovered
        ? (vertical ? hover.point.position.y : hover.point.position.x) - baseStart : NaN
    property real pointer: 0
    onLivePointerChanged: if (!isNaN(livePointer)) pointer = livePointer
    property real magLevel: tracking ? 1 : 0
    Behavior on magLevel { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    readonly property var geo: {
        const z = [], pos = [], lens = [];
        const range = cell * 2.6;
        let before = 0;
        // Drag preview: collapse the dragged slot, open a gap at dragIndex
        // among the other pins.
        const gapAt = dragKey && !dragOut && dragIndex >= 0 ? dragIndex : -1;
        const collapse = dragKey && (gapAt >= 0 || (dragOut && dragWasPinned)) ? dragKey : "";
        for (const s of slots) {
            const c = s.base + s.len / 2;
            let k = 1;
            if (magLevel > 0 && (s.kind === "app" || s.kind === "min")) {
                const d = Math.abs(pointer - c);
                if (d < range) k = 1 + (maxZoom - 1) * magLevel * (Math.cos(Math.PI * d / range) + 1) / 2;
            }
            z.push(k);
            const ext = s.len * (k - 1);
            if (magLevel > 0) {
                if (s.base + s.len <= pointer) before += ext;
                else if (s.base < pointer) before += ext * (pointer - s.base) / s.len;
            }
        }
        let acc = 0, pinIdx = 0, gapDone = gapAt < 0;
        for (let i = 0; i < slots.length; i++) {
            const s = slots[i];
            const isPin = s.kind === "app" && s.pinned;
            if (!gapDone && (!isPin || (s.key !== collapse && pinIdx === gapAt))) { acc += cell; gapDone = true; }
            pos.push(baseStart + s.base + acc - before);
            const len = s.key === collapse ? 0 : s.len * z[i];
            lens.push(len);
            acc += len - s.len;
            if (isPin && s.key !== collapse) pinIdx++;
        }
        if (!gapDone) acc += cell;
        const start = pos.length ? pos[0] : baseStart;
        const end = pos.length ? pos[pos.length - 1] + lens[lens.length - 1] : baseStart + cell;
        return { zoom: z, pos: pos, len: lens, start: start, end: Math.max(end, start + cell) };
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

    function drop(p) {
        const key = dragKey, idx = dragIndex, out = dragOut;
        dragKey = "";
        dragIndex = -1;
        dragOut = false;
        if (!key) return;
        if (out) {
            if (dragWasPinned) { Pins.unpin(key); poof.at(p); }
            return;
        }
        if (idx < 0) return;
        if (!dragWasPinned) Pins.pin(key);
        Pins.move(key, idx);
    }

    // --- drawing ---
    Item {
        id: body
        anchors.fill: parent
        // Slide out across the edge when hidden.
        readonly property real hideOffset: dockWin.shown ? 0 : dockWin.margin + dockWin.thickness + 8
        transform: Translate {
            x: (dockWin.edge === "left" ? -body.hideOffset : dockWin.edge === "right" ? body.hideOffset : 0) + 0.001
            y: (dockWin.edge === "bottom" ? body.hideOffset : 0) + 0.001
            Behavior on x { NumberAnimation { duration: dockWin.cfg.animationMs; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: dockWin.cfg.animationMs; easing.type: Easing.OutCubic } }
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
            Behavior on x { enabled: !dockWin.tracking && !dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: !dockWin.tracking && !dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !dockWin.tracking && dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: !dockWin.tracking && dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            // Soft shadow.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                anchors.topMargin: dockWin.vertical ? -3 : -1
                radius: slab.radius + 3
                color: "transparent"
                border.width: 3
                border.color: Qt.rgba(0, 0, 0, Theme.dark ? 0.18 : 0.08)
            }
            Rectangle {
                id: slab
                anchors.fill: parent
                radius: Math.min(22, dockWin.thickness * 0.32)
                // Hyprland blurs behind the dock; niri can't for this wide
                // surface (see niri/hearth-layer-rules.kdl), so more tint.
                color: Compositor.isHyprland ? Theme.glassDock : Theme.glassDockSolid
                border.color: Theme.glassEdge
                border.width: 1
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.color: Theme.glassRim
                    border.width: 1
                }
                // Top highlight, like light catching the glass edge.
                Rectangle {
                    visible: !dockWin.vertical
                    x: parent.radius
                    y: 1
                    width: parent.width - parent.radius * 2
                    height: 1
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.9)
                }
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
                Behavior on x { enabled: !dockWin.tracking && !dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: !dockWin.tracking && dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: !dockWin.tracking && !dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: !dockWin.tracking && dockWin.vertical; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                // New apps fade and grow in; the dragged one is hidden (the
                // ghost under the pointer stands in for it).
                opacity: slot.modelData.key === dockWin.dragKey ? 0 : appear
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
                        showIndicator: dockWin.cfg.showIndicators
                        dragHost: dockWin.dragHost
                        hostHovered: hover.hovered
                    }
                }
                Component {
                    id: sepComp
                    Item {
                        Rectangle {
                            anchors.centerIn: parent
                            width: dockWin.vertical ? parent.width - 22 : 1
                            height: dockWin.vertical ? 1 : parent.height - 22
                            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(0, 0, 0, 0.28)
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
        padding: 5
        Column {
            width: 230
            MenuItem {
                text: dockWin.cfg.autohide ? "Turn Hiding Off" : "Turn Hiding On"
                onTriggered: { dockMenu.close(); Settings.set("dock.autohide", !dockWin.cfg.autohide); }
            }
            MenuItem {
                text: dockWin.cfg.magnify ? "Turn Magnification Off" : "Turn Magnification On"
                onTriggered: { dockMenu.close(); Settings.set("dock.magnify", !dockWin.cfg.magnify); }
            }
            MenuSeparator {}
            Label { x: 8; height: 24; text: "Position on Screen"; color: Theme.fgDim; font.pointSize: Theme.smallFontSize }
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
        Rectangle {
            anchors.centerIn: parent
            width: dockWin.iconSize * tile.zoom
            height: width * 0.75
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
