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
        implicitWidth: col.implicitWidth + 16
        implicitHeight: col.implicitHeight + 10
        transform: Translate { x: 0.001; y: 0.001 }

        Column {
            id: col
            x: 8
            y: 5
            spacing: 2
            // Each label is its natural width up to 464 px, then wraps. Tray
            // apps send HTML tooltips: as RichText their implicit width
            // follows the width they're given, which collapsed the tooltip
            // to a blob; StyledText keeps a natural width (b/i/br/font).
            Label {
                width: Math.min(implicitWidth, 464)
                text: tip.text.replace(/\n/g, "<br>")
                textFormat: Text.StyledText
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Label {
                width: Math.min(implicitWidth, 464)
                visible: tip.subtext !== ""
                text: tip.subtext.replace(/\n/g, "<br>")
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                textFormat: Text.StyledText
            }
        }
    }
}
