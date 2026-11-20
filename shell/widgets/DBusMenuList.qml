import QtQuick
import Quickshell
import "../services"
import ".."

// The entries of one global-menu (dbusmenu) menu: items, separators,
// check/radio items, shortcuts, and submenus that cascade to the right on
// hover. Always reads the live tree (AppMenu.find), so updates while open
// show at once. `done()` fires after an item is activated.
Column {
    id: root
    property int itemId: 0
    // The BarPopup this menu is in: submenus join its focus grab.
    property var hostPopup: null
    signal done()
    readonly property var node: { void AppMenu.menu; return AppMenu.find(root.itemId); }
    readonly property var items: node ? (node.children || []).filter(i => i.visible) : []
    property int openSub: -1

    width: Math.max(220, implicitW)
    readonly property real implicitW: {
        let w = 0;
        for (let i = 0; i < children.length; i++) w = Math.max(w, children[i].implicitWidth || 0);
        return w;
    }

    Component.onCompleted: Qt.callLater(() => AppMenu.open(root.itemId))
    Component.onDestruction: AppMenu.close(root.itemId)

    Repeater {
        model: root.items
        delegate: Item {
            id: row
            required property var modelData
            readonly property bool sep: modelData.type === "separator"
            width: root.width
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
                onContainsMouseChanged: if (containsMouse) root.openSub = row.modelData.submenu ? row.modelData.id : -1
                onTriggered: {
                    if (row.modelData.submenu) { root.openSub = row.modelData.id; return; }
                    AppMenu.click(row.modelData.id);
                    root.done();
                }
            }

            PopupWindow {
                id: sub
                visible: row.modelData.submenu && root.openSub === row.modelData.id
                anchor.item: row
                anchor.edges: Edges.Right | Edges.Top
                anchor.gravity: Edges.Right | Edges.Bottom
                anchor.adjustment: PopupAdjustment.FlipX | PopupAdjustment.SlideY
                anchor.margins.top: -6
                onVisibleChanged: {
                    const h = root.hostPopup;
                    if (!h) return;
                    const rest = h.extraWindows.filter(w => w !== sub);
                    h.extraWindows = visible ? rest.concat([sub]) : rest;
                }
                color: "transparent"
                implicitWidth: subFrame.implicitWidth
                implicitHeight: subFrame.implicitHeight
                GlassFrame {
                    id: subFrame
                    anchors.fill: parent
                    implicitWidth: subLoader.implicitWidth + 12
                    implicitHeight: subLoader.implicitHeight + 12
                    Loader {
                        id: subLoader
                        x: 6
                        y: 6
                        active: sub.visible
                        source: "DBusMenuList.qml"
                        onLoaded: {
                            item.hostPopup = root.hostPopup;
                            item.itemId = row.modelData.id;
                            item.done.connect(root.done);
                        }
                    }
                }
            }
        }
    }
}
