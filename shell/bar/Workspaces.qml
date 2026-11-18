import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../widgets"
import "../services"
import ".."

// Pager: one miniature per workspace with its windows drawn to scale, like
// Plasma's pager. Click to switch, scroll to move between workspaces, and
// drop a window's mini-rect on another workspace to move it there.
Row {
    id: root
    required property var screen
    spacing: 4

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property real monW: monitor ? monitor.width / monitor.scale : 1920
    readonly property real monH: monitor ? monitor.height / monitor.scale : 1080
    readonly property real boxH: Theme.barHeight - 12
    readonly property real boxW: Math.round(boxH * monW / monH)

    readonly property var workspaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && (!w.monitor || !root.monitor || w.monitor === root.monitor))
        .sort((a, b) => a.id - b.id)

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => Hypr.focusWorkspace(event.angleDelta.y < 0 ? "e+1" : "e-1")
    }

    Repeater {
        model: root.workspaces
        delegate: MouseArea {
            id: ws
            required property var modelData
            width: root.boxW
            height: Theme.barHeight
            hoverEnabled: true
            onClicked: modelData.activate()

            DropArea {
                anchors.fill: parent
                keys: ["hearth-window"]
                onDropped: drop => Hypr.moveWindowToWorkspace(drop.source.address, ws.modelData.id)
            }

            Rectangle {
                id: frame
                anchors.centerIn: parent
                width: root.boxW
                height: root.boxH
                radius: 3
                color: ws.modelData.active ? Theme.accentDim : ws.containsMouse ? Theme.bgRaised : Theme.bgAlt
                border.color: ws.modelData.active ? Theme.accent : Theme.border
                clip: true

                Repeater {
                    model: ws.modelData.toplevels.values
                    delegate: Rectangle {
                        id: win
                        required property var modelData
                        readonly property var ipc: modelData.lastIpcObject
                        readonly property string address: modelData.address
                        readonly property real sx: frame.width / root.monW
                        readonly property real sy: frame.height / root.monH
                        readonly property real ox: root.monitor ? root.monitor.x : 0
                        readonly property real oy: root.monitor ? root.monitor.y : 0
                        visible: !!ipc.at
                        x: ipc.at ? (ipc.at[0] - ox) * sx : 0
                        y: ipc.at ? (ipc.at[1] - oy) * sy : 0
                        width: ipc.size ? Math.max(4, ipc.size[0] * sx) : 0
                        height: ipc.size ? Math.max(4, ipc.size[1] * sy) : 0
                        radius: 2
                        color: modelData.activated ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.16)
                        border.color: Qt.rgba(1, 1, 1, 0.4)
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
                                const e = DesktopEntries.heuristicLookup(win.ipc.class || "");
                                return e ? e.icon : (win.ipc.class || "");
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
                            onClicked: Hypr.focusWindow(win.address)
                        }
                    }
                }
            }

            Tooltip {
                anchorItem: ws
                text: `Workspace ${ws.modelData.name}`
                subtext: ws.modelData.toplevels.values.map(t => t.title).join("\n")
                hovered: ws.containsMouse
            }
        }
    }
}
