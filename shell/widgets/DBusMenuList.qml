import QtQuick
import Quickshell
import "../services"
import ".."

// One global-menu (dbusmenu) menu in its own glass pane: items,
// separators, check/radio items, shortcuts, and submenus that cascade to
// the right. Submenus are drawn in the same surface (the popup grows to
// fit), not as separate popups, so clicks in them never fall outside the
// menu's focus grab. Always reads the live tree (AppMenu.find), so updates
// while open show at once. `done()` fires after an item is activated.
//
// Submenus open after Theme.submenuDelayMs of hover (at once by keyboard)
// and slide/fade in. While the pointer heads for an open submenu (inside
// the triangle from where it was to the submenu's near corners, macOS's
// "safe triangle"), crossing other rows doesn't switch submenus.
Item {
    id: root
    property int itemId: 0
    property var hostPopup: null    // unused; kept for callers
    // The row whose submenu this is (keyboard Left goes back to it).
    property Item ownerItem: null
    signal done()
    readonly property var node: { void AppMenu.menu; return AppMenu.find(root.itemId); }
    readonly property var items: node ? (node.children || []).filter(i => i.visible) : []
    readonly property bool anyGutter: items.some(i => i.toggleType !== "" || (i.icon && i.icon !== ""))
    // The open submenu: its id and the row that owns it.
    property int openSub: -1
    property Item openSubRow: null
    // Keyboard navigation: this menu's rows are one level.
    readonly property Item levelItem: col

    implicitWidth: pane.width + (sub.item ? sub.item.implicitWidth - overlap : 0)
    implicitHeight: Math.max(pane.height, sub.item ? sub.y + sub.item.implicitHeight : 0)
    readonly property real overlap: Math.round(3 * Theme.pt)

    Component.onCompleted: Qt.callLater(() => AppMenu.open(root.itemId))
    Component.onDestruction: AppMenu.close(root.itemId)

    onOpenSubChanged: {
        if (openSub < 0) sub.source = "";
        else sub.setSource("DBusMenuList.qml", { itemId: openSub, ownerItem: openSubRow });
    }
    function showSub(row) {
        if (!row || !row.modelData.submenu) { openSubRow = null; openSub = -1; return; }
        if (openSub === row.modelData.id) return;
        openSub = -1;
        openSubRow = row.entryItem;
        openSubY = row.y;
        openSub = row.modelData.id;
    }
    property real openSubY: 0

    // --- safe triangle ---
    property point lastPos: Qt.point(0, 0)
    property point prevPos: Qt.point(0, 0)
    property var pendingRow: null
    Timer {
        id: subTimer
        interval: Theme.submenuDelayMs
        onTriggered: root.decide()
    }
    function sign(p1, p2, p3) { return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y); }
    function inTriangle(p, a, b, c) {
        const d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a);
        const neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
        return !(neg && pos);
    }
    // Heading for the open submenu: still inside the triangle from the
    // previous pointer position to the submenu's left corners.
    function headingToSub() {
        if (!sub.item) return false;
        const a = prevPos;
        const tl = Qt.point(sub.x, sub.y - 4), bl = Qt.point(sub.x, sub.y + sub.item.implicitHeight + 4);
        return lastPos.x > a.x - 0.5 && inTriangle(lastPos, a, tl, bl);
    }
    function rowHovered(row) {
        pendingRow = row;
        if (openSub >= 0 && headingToSub()) { subTimer.interval = 320; subTimer.restart(); }
        else { subTimer.interval = row.modelData.submenu ? Theme.submenuDelayMs : 60; subTimer.restart(); }
    }
    function decide() {
        const row = pendingRow;
        if (!row) return;
        // Still moving towards the submenu: wait for the pointer to settle.
        if (openSub >= 0 && row.modelData.id !== openSub && headingToSub()
                && (lastPos.x !== prevPos.x || lastPos.y !== prevPos.y)) {
            prevPos = lastPos;
            subTimer.interval = 160;
            subTimer.restart();
            return;
        }
        if (!row.entryItem.containsMouse) return;
        showSub(row);
    }

    GlassFrame {
        id: pane
        width: col.width + 2 * Theme.menuPadding
        height: col.implicitHeight + 2 * Theme.menuPadding

        HoverHandler {
            onPointChanged: {
                const p = pane.mapToItem(root, point.position.x, point.position.y);
                root.prevPos = root.lastPos;
                root.lastPos = p;
            }
        }

        Column {
            id: col
            readonly property bool menuLevel: true
            readonly property Item ownerItem: root.ownerItem
            readonly property bool menuGutter: root.anyGutter
            x: Theme.menuPadding
            y: Theme.menuPadding
            width: Math.max(Math.round(200 * Theme.pt), widest)
            readonly property real widest: {
                let w = 0;
                for (let i = 0; i < children.length; i++) w = Math.max(w, children[i].implicitWidth || 0);
                return w;
            }

            Repeater {
                model: ScriptModel {
                    values: root.items
                    objectProp: "id"
                }
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool sep: modelData.type === "separator"
                    readonly property Item entryItem: entry
                    readonly property bool menuGutter: root.anyGutter
                    width: col.width
                    implicitWidth: sep ? 0 : entry.implicitWidth
                    height: sep ? sepItem.implicitHeight : entry.implicitHeight

                    MenuSeparator { id: sepItem; visible: row.sep; width: parent.width }

                    MenuItem {
                        id: entry
                        visible: !row.sep
                        width: parent.width
                        enabled: row.modelData.enabled
                        text: row.modelData.label
                        icon: row.modelData.toggleType === "" ? (row.modelData.icon || "") : ""
                        checkable: row.modelData.toggleType !== ""
                        radio: row.modelData.toggleType === "radio"
                        checked: row.modelData.toggleState === 1
                        shortcut: row.modelData.shortcut || ""
                        hasSubmenu: !!row.modelData.submenu
                        hoverOpensSubmenu: false
                        submenuLevel: root.openSub === row.modelData.id && sub.item ? sub.item.levelItem : null
                        // Keep the submenu's row highlighted while it's open.
                        highlighted: root.openSub === row.modelData.id
                        onOpenSubmenu: root.showSub(row)
                        onCloseSubmenu: if (root.openSub === row.modelData.id) root.showSub(null)
                        onContainsMouseChanged: if (containsMouse) root.rowHovered(row)
                        onTriggered: {
                            AppMenu.click(row.modelData.id);
                            root.done();
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: sub
        x: pane.width - root.overlap
        // The submenu's first row level with its parent row.
        y: Math.max(0, root.openSubY)
        onLoaded: {
            item.done.connect(root.done);
            item.opacity = 0;
            item.x = -6;
            subIn.restart();
        }
        ParallelAnimation {
            id: subIn
            NumberAnimation { target: sub.item; property: "opacity"; to: 1; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { target: sub.item; property: "x"; to: 0; duration: 160; easing.type: Easing.OutCubic }
        }
    }
}
