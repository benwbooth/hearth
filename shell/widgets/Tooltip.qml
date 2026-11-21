import QtQuick
import Quickshell
import ".."

// Hover tooltip shown next to `anchorItem` after a short delay.
PopupWindow {
    id: tip
    required property Item anchorItem
    property string text: ""
    property string subtext: ""
    property bool hovered: false

    // Away from the bar's screen edge: below the item in a top bar, beside
    // it in a side dock, above it otherwise.
    readonly property string edge: anchorItem.QsWindow.window && anchorItem.QsWindow.window.edge
        ? anchorItem.QsWindow.window.edge : "bottom"
    anchor.item: anchorItem
    anchor.edges: edge === "top" ? Edges.Bottom : edge === "left" ? Edges.Right : edge === "right" ? Edges.Left : Edges.Top
    anchor.gravity: anchor.edges
    anchor.adjustment: PopupAdjustment.Slide
    anchor.margins.top: edge === "top" ? 4 : edge === "bottom" ? -4 : 0
    anchor.margins.left: edge === "left" ? 4 : edge === "right" ? -4 : 0
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

    GlassFrame {
        id: frame
        anchors.fill: parent
        opacity: tip.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        radius: Theme.radius
        implicitWidth: col.implicitWidth + 16
        implicitHeight: col.implicitHeight + 10

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
