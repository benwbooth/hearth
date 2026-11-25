import QtQuick
import Quickshell
import "../services"
import ".."

// Hover tooltip (macOS help tag) shown next to `anchorItem` after
// Theme.tooltipDelayMs: a small glass tag with a soft shadow that fades in
// and out. The surface is larger than the tag by the shadow's room.
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
    readonly property real pad: frame.shadowPad
    anchor.margins.top: (edge === "top" ? 4 : edge === "bottom" ? -4 : 0) + (edge === "top" ? -pad : edge === "bottom" ? pad : 0)
    anchor.margins.left: (edge === "left" ? 4 : edge === "right" ? -4 : 0) + (edge === "left" ? -pad : edge === "right" ? pad : 0)
    color: "transparent"
    visible: false
    implicitWidth: frame.implicitWidth + 2 * pad
    implicitHeight: frame.implicitHeight + 2 * pad
    mask: Region {}

    // Shown: fades in; hidden: fades out, then unmaps. Moving on to another
    // item while a tooltip shows (or just did) switches to its tooltip at
    // once, and the old one goes without fading, like macOS.
    property bool shown: false
    property bool instant: false
    onShownChanged: {
        if (shown) {
            // The last one goes at once, shown or still fading out.
            const prev = ShellState.tooltip;
            if (prev && prev !== tip) {
                if (prev.shown) { prev.instant = true; prev.shown = false; }
                else prev.visible = false;
            }
            ShellState.tooltip = tip;
            visible = true;
        } else {
            if (ShellState.tooltip === tip) ShellState.tooltipWarmUntil = Date.now() + 500;
            if (instant) { instant = false; visible = false; }
        }
    }
    onHoveredChanged: {
        if (hovered && text) {
            // Warm (moving along the bar): after 60 ms, not at once, so a
            // hover that flickers off and on while leaving an item (the
            // treetop graphs) never flashes a tooltip for a frame.
            const warm = Date.now() < ShellState.tooltipWarmUntil || (ShellState.tooltip && ShellState.tooltip.shown);
            showTimer.interval = warm ? 60 : Theme.tooltipDelayMs;
            showTimer.restart();
        } else { showTimer.stop(); shown = false; }
    }
    onTextChanged: if (!text) shown = false

    Timer {
        id: showTimer
        onTriggered: tip.shown = tip.hovered && tip.text !== ""
    }

    GlassFrame {
        id: frame
        x: tip.pad
        y: tip.pad
        width: implicitWidth
        height: implicitHeight
        opacity: tip.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: tip.shown ? 110 : (tip.instant ? 0 : 160); easing.type: Easing.OutCubic } }
        onOpacityChanged: if (opacity === 0 && !tip.shown) tip.visible = false
        tint: Theme.glassTip
        radius: Math.round(7 * Theme.pt)
        shadowBlur: 12
        shadowY: 3
        implicitWidth: col.implicitWidth + 18
        implicitHeight: col.implicitHeight + 10

        Column {
            id: col
            x: 9
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
                font.pointSize: Theme.menuSmallFontSize
                font.weight: tip.subtext !== "" ? Font.DemiBold : Font.Normal
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Label {
                width: Math.min(implicitWidth, 464)
                visible: tip.subtext !== ""
                text: tip.subtext.replace(/\n/g, "<br>")
                color: Theme.fgSecondary
                font.pointSize: Theme.menuSmallFontSize
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                textFormat: Text.StyledText
            }
        }
    }
}
