import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// Launchpad (services/Launchpad.qml): every installed app in a full-screen
// glass overlay, grouped logically into sections (Internet & Chat, Games,
// Development...) or A to Z, with a search field on top.
//
// Click an app to open it; drag it onto the Dock to keep it there (the
// Dock sits above the Launchpad while it's open and opens a gap where it
// will land); right-click for Open, Keep in Dock / Remove from Dock, Open at
// Login, Show in Files. Typing searches (Enter opens the first match),
// arrows move the selection, Page Up/Down scroll, Esc clears the search,
// then closes; a click on empty space closes it. Click a section's title
// to fold it shut or open (remembered). Resting the pointer on an app shows
// a card with what it is, its command, package, desktop file and more.
//
// Motion after macOS: the grid zooms in from slightly larger while it fades
// in (and back out when it closes), over a dimmed, blurred desktop.
Scope {
    id: root

    PanelWindow {
        id: win
        readonly property var targetScreen: Quickshell.screens.find(s => s.name === Launchpad.screenName) || Compositor.focusedScreen
        screen: targetScreen
        // Never unmapped: closed, it's a 1x1 surface that takes no input and
        // draws nothing. Unmapping dropped the window to a pixel ratio of 1,
        // so every icon was rasterised again on each open (seconds of blank
        // icons); this way they're loaded once and opening is instant.
        readonly property bool shown: Launchpad.open || stage.opacity > 0.01
        visible: true
        anchors { top: true; left: true; bottom: shown; right: shown }
        implicitWidth: shown ? 0 : 1
        implicitHeight: shown ? 0 : 1
        mask: shown ? allInput : noInput
        Region { id: noInput }
        Region { id: allInput; item: stage }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "hearth-launchpad"
        WlrLayershell.keyboardFocus: Launchpad.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        readonly property real pt: Theme.pt
        // Device pixels per logical one (4/3 on Ben's display): icons are
        // rasterised at their device size and placed on whole device pixels.
        readonly property real dpr: devicePixelRatio || 1
        // The screen's size, so the layout doesn't change while it's 1x1.
        readonly property real sw: targetScreen ? targetScreen.width : width
        readonly property real sh: targetScreen ? targetScreen.height : height
        function snap(v) { return Math.round(v * dpr) / dpr; }
        readonly property int isz: Math.max(48, Math.min(160, Number(Settings.launchpad.iconSize) || 88))
        readonly property real labelH: Math.round(20 * pt)
        readonly property real cellW: snap(isz * 1.8)
        readonly property real cellH: snap(isz + labelH + Math.round(22 * pt))
        readonly property real headH: snap(Math.round(40 * pt))
        // Clear of the Dock at its edge.
        readonly property real dockRoom: Settings.mac ? Math.round(Settings.dock.size * 1.45 + 24) : 0
        readonly property real sideL: Settings.dock.position === "left" ? dockRoom : 0
        readonly property real sideR: Settings.dock.position === "right" ? dockRoom : 0
        readonly property real bottomRoom: Settings.dock.position === "left" || Settings.dock.position === "right" ? 24 : dockRoom
        readonly property int cols: Math.max(3, Math.min(9, Math.floor((sw - sideL - sideR) * 0.86 / cellW)))
        readonly property real gridW: cols * cellW

        // Where every icon goes: items [{ key, a, x, y, row, col }] and
        // section headers [{ title, y }] in content coordinates.
        readonly property var layout: {
            const items = [], heads = [];
            let y = 0, row = 0;
            for (const g of Launchpad.groups) {
                if (g.title) { heads.push({ key: "h:" + g.id, id: g.id, title: g.title, collapsed: g.collapsed, count: g.items.length, y: y }); y += headH; }
                if (g.collapsed) { y += Math.round(6 * pt); continue; }
                for (let i = 0; i < g.items.length; i++) {
                    const c = i % cols, r = Math.floor(i / cols);
                    items.push({ key: g.items[i].key, a: g.items[i], x: c * cellW, y: y + r * cellH, row: row + r, col: c });
                }
                const rows = Math.ceil(g.items.length / cols);
                y += rows * cellH + (g.title ? Math.round(10 * pt) : 0);
                row += rows;
            }
            const spots = {};
            for (let i = 0; i < items.length; i++) spots[items[i].key] = { x: items[i].x, y: items[i].y, index: i };
            return { items: items, heads: heads, height: y, spots: spots };
        }

        // Loading the icons out of view waits until the visible ones are in.
        property bool prefetch: false
        Timer { running: true; interval: 4000; onTriggered: win.prefetch = true }

        // --- selection (keyboard) ---
        property int sel: 0
        readonly property var selected: layout.items.length ? layout.items[Math.min(sel, layout.items.length - 1)] : null
        onLayoutChanged: if (sel >= layout.items.length) sel = Math.max(0, layout.items.length - 1)
        function moveRow(dir) {
            const cur = selected;
            if (!cur) return;
            const want = cur.row + dir;
            let best = -1, bestD = 1e9;
            for (let i = 0; i < layout.items.length; i++) {
                const it = layout.items[i];
                if (it.row !== want) continue;
                const d = Math.abs(it.col - cur.col);
                if (d < bestD) { bestD = d; best = i; }
            }
            if (best >= 0) sel = best;
        }
        onSelChanged: ensureVisible()
        function ensureVisible() {
            const it = selected;
            if (!it) return;
            if (it.y < flick.contentY) scrollTo(Math.max(0, it.y - headH));
            else if (it.y + cellH > flick.contentY + flick.height) scrollTo(it.y + cellH - flick.height);
        }

        // --- scrolling ---
        // One wheel handler over the whole Launchpad (the grid's own
        // Flickable wheel handling only worked beside the grid, and a
        // pixel snap on every change stopped its flicks). Mouse wheel:
        // smooth steps of about a row. Trackpad: follows the fingers, then
        // glides on with the speed it had when they lift.
        readonly property real maxY: Math.max(0, layout.height - flick.height)
        function clampY(v) { return Math.max(0, Math.min(maxY, v)); }
        function scrollTo(v) {
            glide.stop();
            wheelAnim.stop();
            wheelAnim.to = snap(clampY(v));
            wheelAnim.start();
        }
        property real wheelTarget: 0
        property real velocity: 0          // px per ms, trackpad
        property real lastPadT: 0
        NumberAnimation { id: wheelAnim; target: flick; property: "contentY"; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { id: glide; target: flick; property: "contentY"; easing.type: Easing.OutQuad }
        Timer { id: padEnd; interval: 70; onTriggered: win.startGlide() }
        function startGlide() {
            const v = velocity;
            velocity = 0;
            if (Math.abs(v) < 0.15) { flick.contentY = snap(flick.contentY); return; }
            // Distance as if decelerating evenly: v * 350 ms, over ~0.7 s.
            glide.stop();
            glide.to = snap(clampY(flick.contentY + v * 350));
            glide.duration = Math.min(900, Math.max(300, Math.abs(v) * 420));
            glide.start();
        }
        function onWheel(e) {
            hoverCard.hide();
            if (e.pixelDelta.y !== 0) {
                wheelAnim.stop();
                glide.stop();
                const now = Date.now(), dt = Math.max(1, Math.min(60, now - lastPadT));
                lastPadT = now;
                const d = -e.pixelDelta.y;
                flick.contentY = clampY(flick.contentY + d);
                velocity = velocity * 0.6 + (d / dt) * 0.4;
                if (e.phase === Qt.ScrollEnd) { padEnd.stop(); startGlide(); }
                else padEnd.restart();
            } else if (e.angleDelta.y !== 0) {
                const from = wheelAnim.running ? wheelAnim.to : flick.contentY;
                scrollTo(from - e.angleDelta.y / 120 * cellH * 0.75);
            }
        }

        // --- the app being dragged toward the Dock ---
        property var dragApp: null
        property point dragPos
        property bool dragOverDock: false
        readonly property var dockHost: screen ? Launchpad.dockHosts[screen.name] || null : null
        function dragMove(a, p) {
            hoverCard.hide();
            dragApp = a;
            dragPos = p;
            const h = dockHost;
            dragOverDock = !!h && h.over(p);
            if (!h) return;
            if (dragOverDock) h.move(a.key, a.icon, p);
            else h.leave();
        }
        function dragEnd(p) {
            const h = dockHost, a = dragApp;
            let added = false;
            if (h && a) {
                if (h.over(p)) { h.move(a.key, a.icon, p); added = h.drop(p); }
                else h.leave();
            }
            dragApp = null;
            dragOverDock = false;
            if (added) toast.show("Added " + a.name + " to the Dock");
        }

        // --- open / close motion ---
        Connections {
            target: Launchpad
            function onOpenChanged() {
                if (Launchpad.open) {
                    field.text = Launchpad.query;
                    field.forceActiveFocus();
                    win.sel = 0;
                    flick.contentY = 0;
                    menu.close();
                    hoverCard.hide();
                    closeAnim.stop();
                    openAnim.restart();
                } else {
                    openAnim.stop();
                    closeAnim.restart();
                    menu.close();
                    if (win.dragApp && win.dockHost) win.dockHost.leave();
                    win.dragApp = null;
                }
            }
            function onQueryChanged() { if (field.text !== Launchpad.query) field.text = Launchpad.query; win.sel = 0; wheelAnim.stop(); glide.stop(); flick.contentY = 0; hoverCard.hide(); }
        }

        Item {
            id: stage
            width: win.sw
            height: win.sh
            visible: win.shown
            opacity: 0
            transform: Translate { x: 0.001; y: 0.001 }

            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: stage; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: content; property: "scale"; from: 1.12; to: 1; duration: 320; easing.type: Easing.OutCubic }
            }
            ParallelAnimation {
                id: closeAnim
                NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                NumberAnimation { target: content; property: "scale"; to: 1.1; duration: 180; easing.type: Easing.InCubic }
            }

            // The blurred, dimmed desktop.
            GlassFrame {
                anchors.fill: parent
                radius: 0
                shadow: false
                rimVisible: false
                rim: 0
                glow: 0
                sheen: 0
                tint: Theme.dark ? Qt.rgba(0.07, 0.075, 0.09, 0.62) : Qt.rgba(0.86, 0.87, 0.89, 0.6)
                glassParams: ({ blur_radius: 40 })
            }

            // Empty space: a click closes (or just closes the menu).
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: { if (menu.visible) menu.close(); else Launchpad.hide(); }
            }
            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: e => win.onWheel(e)
            }

            Item {
                id: content
                anchors.fill: parent
                opacity: win.dragApp ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: 160 } }

                // --- the search field ---
                GlassFrame {
                    id: fieldGlass
                    width: Math.round(280 * win.pt)
                    height: Math.round(32 * win.pt)
                    x: win.snap((win.sw - width) / 2)
                    y: win.snap(Math.round(46 * win.pt))
                    radius: height / 2
                    tint: Theme.glassColor(Theme.dark ? Qt.rgba(0.2, 0.205, 0.22, 1) : Qt.rgba(0.97, 0.97, 0.975, 1), 0.7)
                    shadowBlur: 14
                    shadowY: 3
                    Icon {
                        id: mag
                        x: Math.round(11 * win.pt)
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: Math.round(16 * win.pt)
                        name: "search"
                        fallback: "edit-find"
                    }
                    TextInput {
                        id: field
                        anchors.left: mag.right
                        anchors.leftMargin: Math.round(8 * win.pt)
                        anchors.right: parent.right
                        anchors.rightMargin: Math.round(12 * win.pt)
                        anchors.verticalCenter: parent.verticalCenter
                        renderType: Text.NativeRendering
                        color: Theme.fg
                        selectionColor: Theme.accentDim
                        selectedTextColor: Theme.fg
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSize + 2
                        clip: true
                        onTextEdited: Launchpad.query = text
                        Label {
                            anchors.fill: parent
                            visible: !field.text
                            text: "Search"
                            color: Theme.fgSecondary
                            font: field.font
                        }
                        Keys.onPressed: e => {
                            const n = win.layout.items.length;
                            if (menu.visible && e.key === Qt.Key_Escape) { menu.close(); e.accepted = true; return; }
                            switch (e.key) {
                            case Qt.Key_Right: win.sel = Math.min(n - 1, win.sel + 1); break;
                            case Qt.Key_Left: win.sel = Math.max(0, win.sel - 1); break;
                            case Qt.Key_Down: win.moveRow(1); break;
                            case Qt.Key_Up: win.moveRow(-1); break;
                            case Qt.Key_PageDown: flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + flick.height * 0.9); break;
                            case Qt.Key_PageUp: flick.contentY = Math.max(0, flick.contentY - flick.height * 0.9); break;
                            case Qt.Key_Home: if (!field.text) { win.sel = 0; break; } return;
                            case Qt.Key_End: if (!field.text) { win.sel = n - 1; break; } return;
                            case Qt.Key_Return:
                            case Qt.Key_Enter: if (win.selected) Launchpad.launch(win.selected.a); break;
                            case Qt.Key_Escape:
                                if (field.text) { field.text = ""; Launchpad.query = ""; } else Launchpad.hide();
                                break;
                            default: return;
                            }
                            e.accepted = true;
                        }
                    }
                }

                // --- the apps ---
                Flickable {
                    id: flick
                    x: win.snap(win.sideL + (win.sw - win.sideL - win.sideR - win.gridW) / 2)
                    y: fieldGlass.y + fieldGlass.height + Math.round(26 * win.pt)
                    width: win.gridW
                    height: win.sh - y - win.bottomRoom
                    contentWidth: width
                    contentHeight: win.layout.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    // Scrolled by win.onWheel / scrollTo (whole device
                    // pixels at rest, so the icons stay crisp).
                    interactive: false

                    // Empty space between icons closes too.
                    MouseArea {
                        width: flick.contentWidth
                        height: Math.max(flick.height, flick.contentHeight)
                        onClicked: { if (menu.visible) menu.close(); else Launchpad.hide(); }
                    }

                    Repeater {
                        model: ScriptModel { values: win.layout.heads; objectProp: "key" }
                        // A section's title: click to fold it shut or open.
                        MouseArea {
                            id: head
                            required property var modelData
                            x: 0
                            y: modelData.y
                            width: headRow.implicitWidth + Math.round(20 * win.pt)
                            height: win.headH
                            hoverEnabled: true
                            onClicked: { hoverCard.hide(); Launchpad.toggleSection(modelData.id); }
                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: Math.round(4 * win.pt)
                                anchors.bottomMargin: Math.round(4 * win.pt)
                                radius: height / 2
                                color: head.containsMouse ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"
                            }
                            Row {
                                id: headRow
                                x: Math.round(10 * win.pt)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Math.round(6 * win.pt)
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: head.modelData.collapsed ? "▸" : "▾"
                                    color: Theme.fgSecondary
                                    font.pointSize: Theme.fontSize
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: head.modelData.title
                                    color: head.containsMouse ? Theme.fg : Theme.fgSecondary
                                    font.pointSize: Theme.fontSize + 1
                                    font.weight: Font.DemiBold
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: head.modelData.collapsed ? head.modelData.count + (head.modelData.count === 1 ? " app" : " apps") : ""
                                    color: Theme.fgDim
                                    font.pointSize: Theme.fontSize
                                }
                            }
                        }
                    }

                    // The keyboard selection.
                    Rectangle {
                        visible: !!win.selected && Launchpad.open
                        x: win.selected ? win.selected.x + Math.round(6 * win.pt) : 0
                        y: win.selected ? win.selected.y + Math.round(2 * win.pt) : 0
                        width: win.cellW - Math.round(12 * win.pt)
                        height: win.cellH - Math.round(4 * win.pt)
                        radius: Math.round(14 * win.pt)
                        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.1)
                    }

                    Repeater {
                        // One cell per installed app for as long as the shell
                        // runs: a search or a folded section only hides or
                        // moves them, so their icons never load twice.
                        model: ScriptModel { values: Launchpad.apps; objectProp: "key" }
                        MouseArea {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var spot: win.layout.spots[modelData.key] || null
                            visible: !!spot
                            enabled: !!spot
                            x: spot ? spot.x : 0
                            y: spot ? spot.y : 0
                            width: win.cellW
                            height: win.cellH
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            property point pressPos
                            property bool dragging: false
                            onPressed: mouse => { pressPos = Qt.point(mouse.x, mouse.y); dragging = false; }
                            onPositionChanged: mouse => {
                                if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
                                if (!dragging && Math.hypot(mouse.x - pressPos.x, mouse.y - pressPos.y) < 10) return;
                                dragging = true;
                                win.dragMove(modelData, cell.mapToItem(null, mouse.x, mouse.y));
                            }
                            onReleased: mouse => {
                                if (!dragging) return;
                                win.dragEnd(cell.mapToItem(null, mouse.x, mouse.y));
                                Qt.callLater(() => cell.dragging = false);
                            }
                            onCanceled: if (dragging) { win.dragEnd(Qt.point(-1, -1)); dragging = false; }
                            onClicked: mouse => {
                                if (dragging) return;
                                if (mouse.button === Qt.RightButton) {
                                    win.sel = cell.spot.index;
                                    menu.openFor(modelData, cell.mapToItem(stage, mouse.x, mouse.y));
                                } else Launchpad.launch(modelData);
                            }
                            // Icons load once they come near the view (what's on
                                // screen first), then stay loaded; the rest follow
                                // in the background a moment after opening.
                                readonly property bool near: !!spot && spot.y + win.cellH > flick.contentY - flick.height * 0.5
                                                             && spot.y < flick.contentY + flick.height * 1.5
                                property bool want: false
                                onNearChanged: if (near) want = true
                                Component.onCompleted: if (near) want = true
                                Connections { target: win; function onPrefetchChanged() { if (win.prefetch) cell.want = true; } }
                            Icon {
                                visible: cell.want
                                x: win.snap((win.cellW - win.isz) / 2)
                                y: Math.round(8 * win.pt)
                                implicitSize: win.isz
                                rasterSize: win.isz * win.dpr
                                name: cell.want || win.prefetch ? cell.modelData.icon : ""
                                opacity: cell.dragging ? 0.3 : 1
                                scale: cell.pressed && !cell.dragging ? 0.92 : 1
                                Behavior on scale { NumberAnimation { duration: 90 } }
                            }
                            Label {
                                x: Math.round(4 * win.pt)
                                y: Math.round(8 * win.pt) + win.isz + Math.round(6 * win.pt)
                                width: win.cellW - Math.round(8 * win.pt)
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: cell.modelData.name
                                font.pointSize: Theme.fontSize
                            }
                            onContainsMouseChanged: {
                                if (containsMouse) hoverCard.restFor(cell.modelData, cell);
                                else hoverCard.leave(cell.modelData);
                            }
                            onPressedChanged: if (pressed) hoverCard.hide()
                        }
                    }
                }

                // Nothing found.
                Label {
                    visible: Launchpad.query.trim() !== "" && win.layout.items.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: flick.y + Math.round(80 * win.pt)
                    text: "No apps match “" + Launchpad.query.trim() + "”"
                    color: Theme.fgSecondary
                    font.pointSize: Theme.fontSize + 4
                }
            }

            // The app under the pointer while dragging it to the Dock.
            // (Over the Dock, the Dock's own drag overlay draws it.)
            Icon {
                visible: !!win.dragApp && !win.dragOverDock
                implicitSize: win.isz
                rasterSize: win.isz * win.dpr
                name: win.dragApp ? win.dragApp.icon : ""
                x: win.dragPos.x - width / 2
                y: win.dragPos.y - height / 2
                scale: win.dragOverDock ? 0.7 : 1
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
            GlassFrame {
                visible: !!win.dragApp && !win.dragOverDock
                x: win.snap(win.dragPos.x - width / 2)
                y: win.snap(win.dragPos.y - win.isz / 2 - height - Math.round(8 * win.pt))
                width: dragHint.implicitWidth + 2 * Math.round(10 * win.pt)
                height: dragHint.implicitHeight + Math.round(8 * win.pt)
                radius: Math.round(6 * win.pt)
                tint: Theme.glassTip
                shadowBlur: 12
                shadowY: 3
                Label { id: dragHint; anchors.centerIn: parent; text: "Drop on the Dock to keep it there"; font.pointSize: Theme.menuFontSize }
            }

            // Right-click menu.
            GlassFrame {
                id: menu
                property var app: null
                visible: false
                width: Math.round(220 * win.pt)
                height: menuCol.implicitHeight + 2 * Theme.menuPadding
                radius: Theme.menuRadius
                function openFor(a, p) {
                    hoverCard.hide();
                    app = a;
                    x = Math.max(8, Math.min(win.sw - width - 8, p.x));
                    y = Math.max(8, Math.min(win.sh - height - 8, p.y));
                    visible = true;
                }
                function close() { visible = false; }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
                // Solid enough that the icons under it don't show through.
                Rectangle {
                    anchors.fill: parent
                    radius: menu.radius
                    color: Theme.dark ? Qt.rgba(0.13, 0.135, 0.15, 0.94) : Qt.rgba(0.97, 0.97, 0.975, 0.94)
                }
                Column {
                    id: menuCol
                    x: Theme.menuPadding
                    y: Theme.menuPadding
                    width: parent.width - 2 * Theme.menuPadding
                    readonly property bool menuGutter: true
                    readonly property string key: menu.app ? menu.app.key : ""
                    MenuHeader { text: menu.app ? menu.app.name : "" }
                    MenuItem {
                        text: "Open"
                        icon: "system-run"
                        onTriggered: { const a = menu.app; menu.close(); Launchpad.launch(a); }
                    }
                    Repeater {
                        model: menu.app ? menu.app.entry.actions : []
                        MenuItem {
                            required property var modelData
                            text: modelData.name
                            icon: modelData.icon
                            onTriggered: { const id = menu.app.key; menu.close(); Launch.app(modelData, id); Launchpad.hide(); }
                        }
                    }
                    MenuSeparator {}
                    MenuItem {
                        readonly property bool pinned: Pins.isPinned(menuCol.key)
                        text: pinned ? "Remove from Dock" : "Add to Dock"
                        icon: pinned ? "list-remove" : "list-add"
                        onTriggered: {
                            const k = menuCol.key, name = menu.app.name;
                            menu.close();
                            if (pinned) { Pins.unpin(k); toast.show("Removed " + name + " from the Dock"); }
                            else { Pins.pin(k); toast.show("Added " + name + " to the Dock"); }
                        }
                    }
                    MenuItem {
                        text: "Open at Login"
                        checkable: true
                        checked: Autostart.isOn(menuCol.key)
                        onTriggered: { Autostart.set(menuCol.key, !checked); menu.close(); }
                    }
                    MenuItem {
                        text: "Show in Files"
                        icon: "system-file-manager"
                        onTriggered: { const k = menuCol.key; menu.close(); Launchpad.hide(); Launchpad.showInFiles(k); }
                    }
                }
            }

            // Details about the app under the pointer, after it rests there:
            // what it is, its kind and categories, the command it runs, its
            // package (Flatpak or Nix store), its desktop file, whether it's
            // in the Dock, running, opened at login, and how often you open it.
            GlassFrame {
                id: hoverCard
                property var app: null
                property var pending: null
                property Item anchorCell: null
                property string fileInfo: ""
                readonly property var e: app ? app.entry : null
                visible: opacity > 0.01
                opacity: shown ? 1 : 0
                property bool shown: false
                Behavior on opacity { NumberAnimation { duration: hoverCard.shown ? 140 : 90 } }
                width: Math.round(360 * win.pt)
                height: cardCol.implicitHeight + 2 * Math.round(14 * win.pt)
                radius: Math.round(14 * win.pt)
                // Nearly solid: the icons under it must not show through.
                tint: Theme.dark ? Qt.rgba(0.15, 0.155, 0.17, 0.97) : Qt.rgba(0.97, 0.97, 0.975, 0.97)
                compositorGlass: false
                shadowBlur: 18
                shadowY: 5
                function restFor(a, cell) { pending = a; anchorCell = cell; restTimer.restart(); }
                function leave(a) { if (pending === a) { restTimer.stop(); pending = null; } if (app === a) hide(); }
                function hide() { restTimer.stop(); shown = false; }
                Timer {
                    id: restTimer
                    interval: 550
                    onTriggered: {
                        const c = hoverCard.anchorCell;
                        if (!hoverCard.pending || !c || menu.visible || win.dragApp || !Launchpad.open) return;
                        hoverCard.app = hoverCard.pending;
                        hoverCard.fileInfo = "";
                        // Beside the icon, on whichever side has room.
                        const p = c.mapToItem(stage, 0, 0);
                        const right = p.x + c.width + 8;
                        hoverCard.x = win.snap(right + hoverCard.width < stage.width - 16 ? right : p.x - hoverCard.width - 8);
                        hoverCard.y = win.snap(Math.max(16, Math.min(stage.height - hoverCard.height - 16, p.y)));
                        hoverCard.shown = true;
                        fileProc.running = false;
                        fileProc.command = ["sh", "-c",
                            'id="$1"; for d in "${XDG_DATA_HOME:-$HOME/.local/share}" $(echo "${XDG_DATA_DIRS:-/run/current-system/sw/share}" | tr : " "); do '
                            + 'f="$d/applications/$id.desktop"; if [ -f "$f" ]; then echo "$f"; r=$(readlink -f "$f"); [ "$r" != "$f" ] && echo "$r"; '
                            + 'case "$r" in /nix/store/*) ;; *) stat -c %y "$r" | cut -c1-16 ;; esac; exit 0; fi; done', "sh", hoverCard.app.key];
                        fileProc.running = true;
                    }
                }
                Process {
                    id: fileProc
                    stdout: StdioCollector { onStreamFinished: hoverCard.fileInfo = text.trim() }
                }
                // The package, from the command: Flatpak, a Nix store path, or the PATH.
                readonly property string pkg: {
                    if (!e) return "";
                    const x = e.execString || "";
                    const fp = x.match(/flatpak\s+run\s+(?:--\S+\s+)*([\w.-]+)/);
                    if (fp) return "Flatpak · " + fp[1];
                    const ns = x.match(/\/nix\/store\/[a-z0-9]{32}-([^/\s]+)/);
                    if (ns) return "Nix · " + ns[1];
                    const f = fileInfo.match(/\/nix\/store\/[a-z0-9]{32}-([^/\s]+)/);
                    if (f) return "Nix · " + f[1];
                    if (/flatpak\/exports/.test(fileInfo)) return "Flatpak";
                    return "";
                }
                readonly property var group: app ? TaskGroups.groups.find(g => g.key === app.key) : null
                readonly property int windows: group ? group.windows.length : 0
                readonly property int opens: app ? (Spotlight.usage["app:" + app.key] || 0) : 0
                function row(label, value) { return value ? [{ l: label, v: value }] : []; }
                readonly property var rows: !e ? [] : [].concat(
                    row("Kind", Launchpad.sectionTitle(app.section)),
                    row("Categories", (e.categories || []).join(", ")),
                    row("Keywords", (e.keywords || []).join(", ")),
                    row("Runs", (e.execString || "") + (e.runInTerminal ? "  (in a terminal)" : "")),
                    row("Package", pkg),
                    row("App ID", app.key),
                    row("Desktop file", fileInfo.split("\n").filter(l => l.startsWith("/")).join("\n→ ")),
                    row("Modified", fileInfo.split("\n").filter(l => /^\d{4}-/.test(l))[0] || ""),
                    row("Shortcuts", (e.actions || []).map(a => a.name).join(", ")),
                    row("Dock", Pins.isPinned(app.key) ? "Kept in the Dock" : "Not in the Dock"),
                    row("Running", windows ? windows + (windows === 1 ? " window" : " windows") : "No"),
                    row("At login", Autostart.isOn(app.key) ? "Opens at login" : ""),
                    row("Opened", opens ? opens + (opens === 1 ? " time from Search or Launchpad" : " times from Search or Launchpad") : ""))
                Rectangle {
                    anchors.fill: parent
                    radius: hoverCard.radius
                    color: Theme.dark ? Qt.rgba(0.13, 0.135, 0.15, 0.94) : Qt.rgba(0.97, 0.97, 0.975, 0.94)
                }
                Column {
                    id: cardCol
                    x: Math.round(14 * win.pt)
                    y: Math.round(14 * win.pt)
                    width: hoverCard.width - 2 * x
                    spacing: Math.round(8 * win.pt)
                    Row {
                        spacing: Math.round(12 * win.pt)
                        Icon {
                            implicitSize: Math.round(52 * win.pt)
                            rasterSize: Math.round(52 * win.pt) * win.dpr
                            name: hoverCard.app ? hoverCard.app.icon : ""
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: cardCol.width - Math.round(64 * win.pt)
                            Label {
                                width: parent.width
                                text: hoverCard.e ? hoverCard.e.name : ""
                                font.pointSize: Theme.fontSize + 3
                                font.weight: Font.DemiBold
                            }
                            Label {
                                width: parent.width
                                visible: text !== ""
                                text: hoverCard.e ? hoverCard.e.genericName : ""
                                color: Theme.fgSecondary
                            }
                        }
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        text: hoverCard.e ? hoverCard.e.comment : ""
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08) }
                    Repeater {
                        model: hoverCard.rows
                        Row {
                            required property var modelData
                            spacing: Math.round(8 * win.pt)
                            Label {
                                width: Math.round(86 * win.pt)
                                text: modelData.l
                                color: Theme.fgSecondary
                                font.pointSize: Theme.smallFontSize
                                horizontalAlignment: Text.AlignRight
                            }
                            Label {
                                width: cardCol.width - Math.round(94 * win.pt)
                                text: modelData.v
                                font.pointSize: Theme.smallFontSize
                                wrapMode: Text.WrapAnywhere
                                elide: Text.ElideNone
                                maximumLineCount: 4
                            }
                        }
                    }
                    Label {
                        width: parent.width
                        text: "Click to open · drag to the Dock to keep it · right-click for options"
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }
                }
            }

            // A short note after adding or removing an app.
            GlassFrame {
                id: toast
                property string text: ""
                function show(t) { text = t; opacity = 1; toastTimer.restart(); }
                anchors.horizontalCenter: parent.horizontalCenter
                y: fieldGlass.y - height - Math.round(10 * win.pt) + Math.round(4 * win.pt)
                width: toastText.implicitWidth + 2 * Math.round(12 * win.pt)
                height: toastText.implicitHeight + Math.round(8 * win.pt)
                radius: height / 2
                tint: Theme.glassTip
                shadowBlur: 10
                shadowY: 2
                opacity: 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Label { id: toastText; anchors.centerIn: parent; text: toast.text; font.pointSize: Theme.menuFontSize }
                Timer { id: toastTimer; interval: 1800; onTriggered: toast.opacity = 0 }
            }
        }
    }
}
