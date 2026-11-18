import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../services"
import ".."

// A panel popup that opens above `anchorItem` (the bar is at the bottom of
// the screen) and closes when you click anywhere else.
//
// Put a single layout inside it; the popup sizes itself to that child's
// implicit size.
PanelWindow {
    id: popup
    required property Item anchorItem
    default property alias content: body.data
    property int padding: 12
    property bool open: false
    // OnDemand: the popup takes the keyboard when clicked into (search
    // fields, passwords). The launcher uses Exclusive so typing goes
    // straight to its search box.
    property int keyboardFocus: WlrKeyboardFocus.OnDemand

    // A layer-shell panel rather than an xdg popup: popups only get the
    // keyboard through an input grab, which a key bind or `hearth-ipc` can't
    // start. Anchored to the bottom edge it sits just above the bar (the
    // bar's exclusive zone pushes it up), horizontally under its button.
    readonly property var barWindow: anchorItem.QsWindow.window
    screen: barWindow ? barWindow.screen : null
    anchors.bottom: true
    anchors.left: true
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    margins.bottom: 4
    margins.left: {
        void popup.open;
        if (!barWindow || !screen) return 4;
        const p = anchorItem.mapToItem(null, anchorItem.width / 2, 0);
        const w = popup.implicitWidth;
        return Math.max(4, Math.min(screen.width - w - 4, Math.round(p.x - w / 2)));
    }
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "hearth-popup"
    WlrLayershell.keyboardFocus: open ? popup.keyboardFocus : WlrKeyboardFocus.None
    visible: open
    color: "transparent"
    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight

    onOpenChanged: if (open) ShellState.activePopup = popup
    // One popup at a time.
    Connections {
        target: ShellState
        function onActivePopupChanged() {
            if (ShellState.activePopup !== popup) popup.open = false;
        }
    }

    // Close on clicks anywhere else. The bar is part of the grab so its
    // buttons can toggle the popup closed.
    HyprlandFocusGrab {
        active: popup.visible
        windows: popup.barWindow ? [popup, popup.barWindow] : [popup]
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
            implicitWidth: { let w = 0; for (const c of children) if (c.visible) w = Math.max(w, c.implicitWidth); return w; }
            implicitHeight: { let h = 0; for (const c of children) if (c.visible) h = Math.max(h, c.implicitHeight); return h; }
        }

        Keys.onEscapePressed: popup.close()
    }
}
