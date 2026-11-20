import QtQuick
import Quickshell
import "../services"
import ".."

// One global-menu (dbusmenu) menu in its own glass pane: items,
// separators, check/radio items, shortcuts, and submenus that cascade to
// the right on hover. Submenus are drawn in the same surface (the popup
// grows to fit), not as separate popups, so clicks in them never fall
// outside the menu's focus grab. Always reads the live tree
// (AppMenu.find), so updates while open show at once. `done()` fires after
// an item is activated.
Item {
    id: root
    property int itemId: 0
    property var hostPopup: null    // unused; kept for callers
    signal done()
    readonly property var node: { void AppMenu.menu; return AppMenu.find(root.itemId); }
    readonly property var items: node ? (node.children || []).filter(i => i.visible) : []
    property int openSub: -1
    property real openSubY: 0

    implicitWidth: pane.width + (sub.item ? sub.item.implicitWidth - 4 : 0)
    implicitHeight: Math.max(pane.height, sub.item ? sub.y + sub.item.implicitHeight : 0)

    Component.onCompleted: Qt.callLater(() => AppMenu.open(root.itemId))
    Component.onDestruction: AppMenu.close(root.itemId)

    onOpenSubChanged: {
        if (openSub < 0) sub.source = "";
        else sub.setSource("DBusMenuList.qml", { itemId: openSub });
    }

    GlassFrame {
        id: pane
        width: col.width + 12
        height: col.implicitHeight + 12

        Column {
            id: col
            x: 6
            y: 6
            width: Math.max(220, widest)
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
                        icon: row.modelData.toggleType === "" ? row.modelData.icon : ""
                        checkable: row.modelData.toggleType !== ""
                        checked: row.modelData.toggleState === 1
                        shortcut: row.modelData.submenu ? "›" : row.modelData.shortcut
                        // Keep the submenu's row highlighted while it's open.
                        highlighted: root.openSub === row.modelData.id
                        function openIt() {
                            root.openSubY = row.y;
                            root.openSub = row.modelData.submenu ? row.modelData.id : -1;
                        }
                        onContainsMouseChanged: if (containsMouse) openIt()
                        onTriggered: {
                            if (row.modelData.submenu) { openIt(); return; }
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
        x: pane.width - 4
        y: root.openSubY
        onLoaded: item.done.connect(root.done)
    }
}
