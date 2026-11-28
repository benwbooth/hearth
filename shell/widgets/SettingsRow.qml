import QtQuick
import "../services"
import ".."

// A Settings row: a label, a one-line plain-language note under it, and a
// control on the right. Hovering the label shows `tip` (extra detail the
// note doesn't fit) as a tooltip.
Item {
    id: r
    property string label
    property string note: ""
    property string tip: ""
    default property alias control: holder.data
    width: parent ? parent.width : 400
    implicitHeight: Math.max(44, texts.implicitHeight + 16)
    opacity: enabled ? 1 : 0.5

    // Picked in Settings search: scroll into view and flash.
    readonly property bool found: label !== "" && ShellState.settingsHighlight === label
    onFoundChanged: if (found) Qt.callLater(reveal)
    Component.onCompleted: if (found) Qt.callLater(reveal)
    function reveal() {
        for (let it = r.parent; it; it = it.parent) {
            if (it.contentItem !== undefined && typeof it.contentY === "number" && typeof it.contentHeight === "number") {
                const y = r.mapToItem(it.contentItem, 0, 0).y;
                it.contentY = Math.max(0, Math.min(it.contentHeight - it.height, y - it.height / 3));
                break;
            }
        }
        flash.restart();
    }
    Rectangle {
        id: flashRect
        anchors.fill: parent
        anchors.margins: -4
        radius: Theme.radius
        color: Theme.accent
        opacity: 0
        SequentialAnimation {
            id: flash
            NumberAnimation { target: flashRect; property: "opacity"; to: 0.28; duration: 180 }
            PauseAnimation { duration: 900 }
            NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 600 }
            ScriptAction { script: if (ShellState.settingsHighlight === r.label) ShellState.settingsHighlight = "" }
        }
    }

    HoverHandler { id: hov }
    Tooltip {
        anchorItem: texts
        text: r.tip
        hovered: hov.hovered
    }

    Column {
        id: texts
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - holder.width - 16
        Label { text: r.label; width: parent.width }
        Label {
            visible: r.note !== ""
            text: r.note
            width: parent.width
            color: Theme.fgDim
            font.pointSize: Theme.smallFontSize
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
    }
    Item {
        id: holder
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
