import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../services"
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
    // No xdg_popup grab: it needs a recent input serial, so popups opened from
    // a key bind or `hearth-ipc` would fail. Hyprland's focus grab gives the
    // popup the keyboard and tells us about clicks elsewhere instead. The bar
    // is part of the grab so its buttons can toggle the popup closed.
    grabFocus: false
    visible: open
    color: "transparent"
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    onVisibleChanged: if (!visible) open = false
    onOpenChanged: if (open) ShellState.activePopup = popup
    // One popup at a time.
    Connections {
        target: ShellState
        function onActivePopupChanged() {
            if (ShellState.activePopup !== popup) popup.open = false;
        }
    }

    HyprlandFocusGrab {
        active: popup.visible
        windows: [popup, popup.anchorItem.QsWindow.window]
        onCleared: popup.close()
    }

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
