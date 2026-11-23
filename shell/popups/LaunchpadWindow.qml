import QtQuick
import Quickshell
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
// then closes; a click on empty space closes it.
//
// Motion after macOS: the grid zooms in from slightly larger while it fades
// in (and back out when it closes), over a dimmed, blurred desktop.
Scope {
    id: root

    PanelWindow {
        id: win
        readonly property var targetScreen: Quickshell.screens.find(s => s.name === Launchpad.screenName) || Compositor.focusedScreen
        screen: targetScreen
        visible: Launchpad.open || stage.opacity > 0.01
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "hearth-launchpad"
        WlrLayershell.keyboardFocus: Launchpad.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        readonly property real pt: Theme.pt
        // Device pixels per logical one (4/3 on Ben's display): icons are
        // rasterised at their device size and placed on whole device pixels.
        readonly property real dpr: devicePixelRatio || 1
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
        readonly property int cols: Math.max(3, Math.min(9, Math.floor((width - sideL - sideR) * 0.86 / cellW)))
        readonly property real gridW: cols * cellW

        // Where every icon goes: items [{ key, a, x, y, row, col }] and
        // section headers [{ title, y }] in content coordinates.
        readonly property var layout: {
            const items = [], heads = [];
            let y = 0, row = 0;
            for (const g of Launchpad.groups) {
                if (g.title) { heads.push({ key: "h:" + g.title, title: g.title, y: y }); y += headH; }
                for (let i = 0; i < g.items.length; i++) {
                    const c = i % cols, r = Math.floor(i / cols);
                    items.push({ key: g.items[i].key, a: g.items[i], x: c * cellW, y: y + r * cellH, row: row + r, col: c });
                }
                const rows = Math.ceil(g.items.length / cols);
                y += rows * cellH + (g.title ? Math.round(10 * pt) : 0);
                row += rows;
            }
            return { items: items, heads: heads, height: y };
        }

        // --- selection (keyboard) ---
        property int sel: 0
        readonly property var current: layout.items.length ? layout.items[Math.min(sel, layout.items.length - 1)] : null
        onLayoutChanged: if (sel >= layout.items.length) sel = Math.max(0, layout.items.length - 1)
        function moveRow(dir) {
            const cur = current;
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
            const it = current;
            if (!it) return;
            if (it.y < flick.contentY) flick.contentY = Math.max(0, it.y - headH);
            else if (it.y + cellH > flick.contentY + flick.height) flick.contentY = it.y + cellH - flick.height;
        }

        // --- the app being dragged toward the Dock ---
        property var dragApp: null
        property point dragPos
        property bool dragOverDock: false
        readonly property var dockHost: screen ? Launchpad.dockHosts[screen.name] || null : null
        function dragMove(a, p) {
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
            function onQueryChanged() { if (field.text !== Launchpad.query) field.text = Launchpad.query; win.sel = 0; flick.contentY = 0; }
        }

        Item {
            id: stage
            anchors.fill: parent
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
                onWheel: w => { flick.flick(0, w.angleDelta.y * 6); }
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
                    x: win.snap((win.width - width) / 2)
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
                            case Qt.Key_Enter: if (win.current) Launchpad.launch(win.current.a); break;
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
                    x: win.snap(win.sideL + (win.width - win.sideL - win.sideR - win.gridW) / 2)
                    y: fieldGlass.y + fieldGlass.height + Math.round(26 * win.pt)
                    width: win.gridW
                    height: win.height - y - win.bottomRoom
                    contentWidth: width
                    contentHeight: win.layout.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    // Scrolled position on whole device pixels (crisp icons).
                    onContentYChanged: { const s = win.snap(contentY); if (s !== contentY && !moving) contentY = s; }

                    // Empty space between icons closes too.
                    MouseArea {
                        width: flick.contentWidth
                        height: Math.max(flick.height, flick.contentHeight)
                        onClicked: { if (menu.visible) menu.close(); else Launchpad.hide(); }
                    }

                    Repeater {
                        model: ScriptModel { values: win.layout.heads; objectProp: "key" }
                        Label {
                            required property var modelData
                            x: Math.round(8 * win.pt)
                            y: modelData.y + Math.round(8 * win.pt)
                            text: modelData.title
                            color: Theme.fgSecondary
                            font.pointSize: Theme.fontSize + 1
                            font.weight: Font.DemiBold
                        }
                    }

                    // The keyboard selection.
                    Rectangle {
                        visible: !!win.current && Launchpad.open
                        x: win.current ? win.current.x + Math.round(6 * win.pt) : 0
                        y: win.current ? win.current.y + Math.round(2 * win.pt) : 0
                        width: win.cellW - Math.round(12 * win.pt)
                        height: win.cellH - Math.round(4 * win.pt)
                        radius: Math.round(14 * win.pt)
                        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.1)
                    }

                    Repeater {
                        model: ScriptModel { values: win.layout.items; objectProp: "key" }
                        MouseArea {
                            id: cell
                            required property var modelData
                            required property int index
                            x: modelData.x
                            y: modelData.y
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
                                win.dragMove(modelData.a, cell.mapToItem(null, mouse.x, mouse.y));
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
                                    win.sel = index;
                                    menu.openFor(modelData.a, cell.mapToItem(stage, mouse.x, mouse.y));
                                } else Launchpad.launch(modelData.a);
                            }
                            Icon {
                                x: win.snap((win.cellW - win.isz) / 2)
                                y: Math.round(8 * win.pt)
                                implicitSize: win.isz
                                rasterSize: win.isz * win.dpr
                                name: cell.modelData.a.icon
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
                                text: cell.modelData.a.name
                                font.pointSize: Theme.fontSize
                            }
                            Tooltip {
                                anchorItem: cell
                                text: (cell.modelData.a.entry.comment || cell.modelData.a.name) + " · click to open, drag to the Dock to keep it, right-click for options"
                                hovered: cell.containsMouse && !cell.pressed && !menu.visible && !win.dragApp
                            }
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
                    app = a;
                    x = Math.max(8, Math.min(win.width - width - 8, p.x));
                    y = Math.max(8, Math.min(win.height - height - 8, p.y));
                    visible = true;
                }
                function close() { visible = false; }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
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
