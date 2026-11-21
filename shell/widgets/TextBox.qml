import QtQuick
import ".."

// A one-line text field with native text and a placeholder.
Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: ""
    property alias input: input
    signal accepted()
    implicitWidth: 240
    implicitHeight: 28
    radius: Theme.radius
    color: Theme.bgRaised
    border.color: input.activeFocus ? Theme.accent : Theme.border
    opacity: enabled ? 1 : 0.4
    TextInput {
        id: input
        x: 8
        width: parent.width - 16
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pointSize: Theme.fontSize
        renderType: Text.NativeRendering
        selectByMouse: true
        clip: true
        onAccepted: root.accepted()
        Label {
            visible: input.text === "" && !input.activeFocus
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: root.placeholder
            color: Theme.fgDim
        }
    }
}
