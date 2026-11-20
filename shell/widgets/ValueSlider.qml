import QtQuick
import ".."

// A horizontal slider with a value label. `moved(value)` fires while
// dragging (rounded to `step`).
Item {
    id: root
    property real from: 0
    property real to: 100
    property real value: 0
    property real step: 1
    property string suffix: ""
    property int decimals: 0
    signal moved(real value)
    implicitWidth: 280
    implicitHeight: 24
    opacity: enabled ? 1 : 0.4

    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    Item {
        id: track
        anchors.left: parent.left
        anchors.right: valueLabel.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 20
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.15)
            Rectangle { width: parent.width * root.frac; height: parent.height; radius: 2; color: Theme.accent }
        }
        Rectangle {
            width: 18
            height: 18
            radius: 9
            y: 1
            x: root.frac * (parent.width - width)
            color: "#ffffff"
            border.color: Theme.dark ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(0, 0, 0, 0.2)
        }
        MouseArea {
            anchors.fill: parent
            function set(mx) {
                const f = Math.max(0, Math.min(1, (mx - 9) / (width - 18)));
                let v = root.from + f * (root.to - root.from);
                v = Math.round(v / root.step) * root.step;
                root.moved(Number(v.toFixed(4)));
            }
            onPressed: mouse => set(mouse.x)
            onPositionChanged: mouse => { if (pressed) set(mouse.x); }
        }
    }
    Label {
        id: valueLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 64
        horizontalAlignment: Text.AlignRight
        text: root.value.toFixed(root.decimals) + root.suffix
        color: Theme.fgDim
    }
}
