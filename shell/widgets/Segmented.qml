import QtQuick
import ".."

// A segmented control: `options` is [{ value, label }].
Rectangle {
    id: root
    property var options: []
    property var value
    signal picked(var value)
    implicitWidth: row.implicitWidth + 4
    implicitHeight: 26
    radius: Theme.radius
    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

    Row {
        id: row
        x: 2
        y: 2
        Repeater {
            model: root.options
            MouseArea {
                id: seg
                required property var modelData
                readonly property bool on: root.value === modelData.value
                width: Math.max(70, label.implicitWidth + 24)
                height: root.height - 4
                onClicked: root.picked(modelData.value)
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius - 1
                    color: seg.on ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : "#ffffff") : "transparent"
                }
                Label {
                    id: label
                    anchors.centerIn: parent
                    text: seg.modelData.label
                    font.weight: seg.on ? Font.DemiBold : Font.Normal
                }
            }
        }
    }
}
