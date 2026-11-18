import QtQuick
import Quickshell
import ".."

// A panel popup that opens above `anchorItem` (the bar is at the bottom of
// the screen) and closes when you click anywhere else.
//
// Put a single layout inside it; the popup sizes itself to that child's
// implicit size.
PopupWindow {
    id: popup
    required property Item anchorItem
    default property alias content: body.data
    property int padding: 12
    property bool open: false

    anchor.item: anchorItem
    anchor.edges: Edges.Top
    anchor.gravity: Edges.Top
    anchor.adjustment: PopupAdjustment.Slide
    anchor.margins.top: -4
    grabFocus: true
    visible: open
    color: "transparent"
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    onVisibleChanged: if (!visible) open = false

    function toggle() { open = !open; }
    function close() { open = false; }

    Rectangle {
        id: frame
        anchors.fill: parent
        color: Theme.bgAlt
        border.color: Theme.border
        border.width: 1
        radius: Theme.popupRadius
        implicitWidth: body.implicitWidth + popup.padding * 2
        implicitHeight: body.implicitHeight + popup.padding * 2
        // Popups draw in their own surface, outside the bar's nudge, so they
        // get their own: keeps text off exact half device pixels at 130%.
        transform: Translate { x: 0.001; y: 0.001 }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: popup.padding
            implicitWidth: children.length > 0 ? children[0].implicitWidth : 0
            implicitHeight: children.length > 0 ? children[0].implicitHeight : 0
        }

        Keys.onEscapePressed: popup.close()
    }
}
