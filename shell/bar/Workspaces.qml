import QtQuick
import Quickshell
import "../widgets"
import "../services"
import ".."

// Pager: one miniature per workspace with its windows drawn to scale, like
// Plasma's pager. Click to switch, scroll to move between workspaces, and
// drop a window's mini-rect on another workspace to move it there.
// `menuBarItem`: the macOS-style menu bar's look (outlines in the bar's text
// colour, which follows the wallpaper and bar style).
Row {
    id: root
    required property var screen
    property bool menuBarItem: false
    spacing: menuBarItem ? Math.round(3 * Theme.pt) : 4

    readonly property real monW: screen ? screen.width : 1920
    readonly property real monH: screen ? screen.height : 1080
    readonly property real itemH: menuBarItem ? Theme.menuBarHeight : Theme.barHeight
    // Settings > Menu Bar > Workspace map > Size: 1 = the bar's height,
    // smaller boxes for a quieter bar.
    property real boxScale: 1
    readonly property real boxH: Math.round((menuBarItem ? Theme.menuBarHeight - Math.round(6 * Theme.pt) : Theme.barHeight - 12) * boxScale)
    // The bar's text colour; the overflow dropdown passes its own.
    property color fg: Theme.barFg
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a); }
    readonly property real boxW: Math.round(boxH * monW / monH)

    readonly property var workspaces: Compositor.workspacesOn(screen ? screen.name : "")

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => Compositor.focusWorkspaceRelative(event.angleDelta.y < 0 ? 1 : -1)
    }

    Repeater {
        model: root.workspaces
        delegate: MouseArea {
            id: ws
            required property var modelData
            width: root.boxW
            height: root.itemH
            hoverEnabled: true
            onClicked: Compositor.focusWorkspace(modelData.id)

            DropArea {
                anchors.fill: parent
                keys: ["hearth-window"]
                onDropped: drop => Compositor.moveWindowToWorkspace(drop.source.address, ws.modelData.id)
            }

            Rectangle {
                id: frame
                anchors.centerIn: parent
                width: root.boxW
                height: root.boxH
                radius: 3
                color: root.menuBarItem
                    ? root.tint(ws.modelData.active ? 0.22 : ws.containsMouse ? 0.14 : 0.06)
                    : ws.modelData.active ? Theme.accentDim : ws.containsMouse ? Theme.bgRaised : Theme.bgAlt
                border.color: root.menuBarItem
                    ? root.tint(ws.modelData.active ? 0.95 : 0.45)
                    : ws.modelData.active ? Theme.accent : Theme.border
                border.width: root.menuBarItem && ws.modelData.active ? 1.5 : 1
                clip: true

                Repeater {
                    model: ScriptModel {
                        values: Compositor.windowsOn(ws.modelData.id)
                        objectProp: "id"
                    }
                    delegate: Rectangle {
                        id: win
                        required property var modelData
                        readonly property var ipc: modelData
                        readonly property string address: modelData.id
                        readonly property real sx: frame.width / root.monW
                        readonly property real sy: frame.height / root.monH
                        readonly property real ox: 0
                        readonly property real oy: 0
                        visible: !!ipc.at
                        x: ipc.at ? (ipc.at[0] - ox) * sx : 0
                        y: ipc.at ? (ipc.at[1] - oy) * sy : 0
                        width: ipc.size ? Math.max(4, ipc.size[0] * sx) : 0
                        height: ipc.size ? Math.max(4, ipc.size[1] * sy) : 0
                        radius: 2
                        color: root.menuBarItem
                            ? root.tint(modelData.focused ? 0.5 : 0.28)
                            : modelData.focused ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.16)
                        border.color: root.menuBarItem ? root.tint(0.6) : Qt.rgba(1, 1, 1, 0.4)
                        border.width: 1

                        Drag.active: dragArea.drag.active
                        Drag.keys: ["hearth-window"]
                        Drag.source: win
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2

                        Icon {
                            anchors.centerIn: parent
                            implicitSize: Math.min(parent.width, parent.height) - 4
                            visible: implicitSize >= 8
                            name: {
                                const e = DesktopEntries.heuristicLookup(win.ipc.appId || "");
                                return e ? e.icon : (win.ipc.appId || "");
                            }
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            drag.target: win
                            onReleased: {
                                win.Drag.drop();
                                // Snap back; the move (if any) redraws it.
                                win.x = Qt.binding(() => win.ipc.at ? (win.ipc.at[0] - win.ox) * win.sx : 0);
                                win.y = Qt.binding(() => win.ipc.at ? (win.ipc.at[1] - win.oy) * win.sy : 0);
                            }
                            onClicked: Compositor.focusWindow(win.address)
                        }
                    }
                }
            }

            Tooltip {
                anchorItem: ws
                text: `Workspace ${ws.modelData.name}` + (Compositor.windowsOn(ws.modelData.id).length ? "" : " (empty)")
                subtext: Compositor.windowsOn(ws.modelData.id).map(t => t.title).join("\n")
                    || "Click to go there, or drag a window's box here to move it"
                hovered: ws.containsMouse
            }
        }
    }
}
