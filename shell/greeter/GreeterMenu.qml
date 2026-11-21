import QtQuick
import "../lock"
import "../widgets"
import ".."

// A small glass menu drawn on the login screen's own surface (a layer
// surface can't open pop-up windows): the session picker and the
// accessibility menu. `items`: [{ text, detail, checked, enabled }];
// picking one emits `picked(index)` and closes.
LockGlass {
    id: root
    property real k: 1
    property var items: []
    property string title: ""
    property bool open: false
    signal picked(int index)

    radius: 14 * k
    tint: Qt.rgba(0.12, 0.12, 0.14, 0.72)
    width: Math.max(Math.round(270 * k), col.implicitWidth + 12 * k)
    height: col.implicitHeight + 12 * k
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.96
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: open ? Theme.menuInMs : Theme.menuOutMs; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Theme.menuInMs; easing.type: Easing.OutCubic } }

    Column {
        id: col
        x: 6 * root.k
        y: 6 * root.k
        width: root.width - 12 * root.k
        Label {
            visible: root.title !== ""
            width: parent.width
            leftPadding: 10 * root.k
            height: 24 * root.k
            text: root.title
            color: Qt.rgba(1, 1, 1, 0.55)
            font.pointSize: 0.75 * Math.round(11.5 * root.k)
            font.weight: Font.DemiBold
        }
        Repeater {
            model: root.items
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool enabled: modelData.enabled !== false
                width: col.width
                height: (modelData.detail ? 40 : 28) * root.k
                radius: 8 * root.k
                color: ma.containsMouse && enabled ? Theme.accent : "transparent"
                Label {
                    id: check
                    x: 8 * root.k
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.checked ? "✓" : ""
                    width: 14 * root.k
                    color: "white"
                    font.pointSize: 0.75 * Math.round(13 * root.k)
                }
                Column {
                    anchors.left: check.right
                    anchors.leftMargin: 6 * root.k
                    anchors.right: parent.right
                    anchors.rightMargin: 10 * root.k
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        width: parent.width
                        text: row.modelData.text
                        color: row.enabled ? "white" : Qt.rgba(1, 1, 1, 0.4)
                        font.pointSize: 0.75 * Math.round(13.5 * root.k)
                    }
                    Label {
                        visible: !!row.modelData.detail
                        width: parent.width
                        text: row.modelData.detail || ""
                        color: Qt.rgba(1, 1, 1, ma.containsMouse ? 0.85 : 0.6)
                        font.pointSize: 0.75 * Math.round(11.5 * root.k)
                    }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: row.enabled
                    onClicked: { root.open = false; root.picked(row.index); }
                }
            }
        }
    }
}
