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
    readonly property int iconSize: Math.max(24, Math.min(128, cfg.size))
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
        function toggle(): void { dockWin.held = !dockWin.held; }
        function state(): string {
            return JSON.stringify({ shown: dockWin.shown, held: dockWin.held, hovered: hover.hovered, pointer: dockWin.pointer,
                                    frame: [frameMask.x, frameMask.y, frameMask.width, frameMask.height],
                                    win: [dockWin.width, dockWin.height], previews: dockWin.previews });
        }
    }

    Item {
        id: trigger
        width: dockWin.vertical ? 2 : parent.width
        height: dockWin.vertical ? parent.height : 2
        x: dockWin.edge === "right" ? parent.width - 2 : 0
        y: dockWin.edge === "bottom" ? parent.height - 2 : 0
        HoverHandler { onHoveredChanged: if (hovered) { dockWin.held = true; hideTimer.stop(); } }
    }

    // --- model ---
    readonly property var slots: {
        const out = [];
        const all = TaskGroups.groups;
        const pinned = all.filter(g => g.pinned);
        const rest = all.filter(g => !g.pinned).concat(cfg.showRecents ? TaskGroups.recentGroups : []);
        for (const g of pinned) out.push({ key: g.key, kind: "app", group: g });
        if (rest.length) {
            if (out.length) out.push({ key: "sep:apps", kind: "sep" });
            for (const g of rest) out.push({ key: g.key, kind: "app", group: g });
        }
        if (!cfg.minimizeIntoApp) {
            const mins = ToplevelManager.toplevels.values.filter(t => t.minimized);
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
    // start, slots after it toward the end.
    readonly property real pointer: hover.hovered && cfg.magnify && dragKey === ""
        ? (vertical ? hover.point.position.y : hover.point.position.x) - baseStart : NaN
    readonly property var geo: {
        const z = [], pos = [], lens = [];
        const range = cell * 2.6;
        let total = 0, before = 0;
        for (const s of slots) {
            const c = s.base + s.len / 2;
            let k = 1;
            if (!isNaN(pointer) && s.kind !== "sep") {
                const d = Math.abs(pointer - c);
                if (d < range) k = 1 + (maxZoom - 1) * (Math.cos(Math.PI * d / range) + 1) / 2;
            }
            z.push(k);
            const ext = s.len * (k - 1);
            total += ext;
            if (!isNaN(pointer)) {
                if (s.base + s.len <= pointer) before += ext;
                else if (s.base < pointer) before += ext * (pointer - s.base) / s.len;
            }
        }
        let acc = 0;
        for (let i = 0; i < slots.length; i++) {
            const s = slots[i];
            pos.push(baseStart + s.base + acc - before);
            lens.push(s.len * z[i]);
            acc += s.len * (z[i] - 1);
        }
        const start = pos.length ? pos[0] : baseStart;
        const end = pos.length ? pos[pos.length - 1] + lens[lens.length - 1] : baseStart + cell;
        return { zoom: z, pos: pos, len: lens, start: start, end: end };
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
    property point dragPos
    property bool dragOut: false
    readonly property var dragHost: ({
        begin: (task, p) => { dockWin.dragKey = task.modelData.key; dockWin.dragPos = p; dockWin.dragIcon = task.entry ? task.entry.icon : ""; },
        move: (task, p) => {
            dockWin.dragPos = p;
            const off = dockWin.vertical ? (dockWin.edge === "left" ? p.x - (dockWin.margin + dockWin.thickness) : (dockWin.width - dockWin.margin - dockWin.thickness) - p.x)
                                      : (dockWin.height - dockWin.margin - dockWin.thickness) - p.y;
            dockWin.dragOut = dockWin.edge === "left" ? off > 60 : off > 60;
        },
        end: (task, p) => dockWin.drop(task, p)
    })
    property string dragIcon: ""

    function drop(task, p) {
        const key = dragKey;
        dragKey = "";
        if (!key) return;
        if (dragOut) {
            dragOut = false;
            if (Pins.isPinned(key)) {
                Pins.unpin(key);
                poof.at(p);
            }
            return;
        }
        // Index among the pins at the drop point.
        const along = (vertical ? p.y : p.x);
        const pins = slots.filter(s => s.kind === "app" && s.group.pinned && s.key !== key);
        let idx = 0;
        for (const s of pins) if (baseStart + s.base + s.len / 2 < along) idx++;
        const lastPin = slots.filter(s => s.kind === "app" && s.group.pinned).pop();
        const inPins = !lastPin || along < baseStart + lastPin.base + lastPin.len + cell / 2;
        if (Pins.isPinned(key)) Pins.move(key, idx);
        else if (inPins) { Pins.pin(key); Pins.move(key, idx); }
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
                color: Theme.glassDock
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

                readonly property bool previewOpen: task ? task.previewOpen : false
                onPreviewOpenChanged: dockWin.previews += previewOpen ? 1 : -1
                Component.onDestruction: if (previewOpen) dockWin.previews -= 1

                Loader {
                    id: loader
                    anchors.fill: parent
                    sourceComponent: slot.modelData.kind === "app" ? appComp
                                   : slot.modelData.kind === "sep" ? sepComp : minComp
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
