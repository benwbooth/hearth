import QtQuick
import Quickshell
import ".."

// Hover tooltip shown above `anchorItem` after a short delay.
PopupWindow {
    id: tip
    required property Item anchorItem
    property string text: ""
    property string subtext: ""
    property bool hovered: false

    anchor.item: anchorItem
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.adjustment: PopupAdjustment.Slide
    anchor.margins.top: -4
    color: "transparent"
    visible: false
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    onHoveredChanged: {
        if (hovered && text) showTimer.restart();
        else { showTimer.stop(); visible = false; }
    }
    onTextChanged: if (!text) visible = false

    Timer {
        id: showTimer
        interval: 550
        onTriggered: tip.visible = tip.hovered && tip.text !== ""
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        color: Theme.bgRaised
        border.color: Theme.border
        radius: Theme.radius
        implicitWidth: Math.min(col.implicitWidth, 480) + 16
        implicitHeight: col.implicitHeight + 10
        transform: Translate { x: 0.001; y: 0.001 }

        Column {
            id: col
            x: 8
            y: 5
            width: parent.width - 16
            spacing: 2
            Label {
                width: parent.width
                text: tip.text
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Label {
                width: parent.width
                visible: tip.subtext !== ""
                text: tip.subtext
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                textFormat: Text.PlainText
            }
        }
    }
}
