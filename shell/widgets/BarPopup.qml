import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../services"
import ".."

// A panel popup that opens next to `anchorItem`: below it when its window is
// a top bar (`edge: "top"` on the bar window), above it otherwise (bottom
// panel, dock), and closes when you click anywhere else.
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
    // fields, passwords). Exclusive sends all typing straight to it.
    property int keyboardFocus: WlrKeyboardFocus.OnDemand

    // A layer-shell panel rather than an xdg popup: popups only get the
    // keyboard through an input grab, which a key bind or `hearth-ipc` can't
    // start. Anchored to the bottom edge it sits just above the bar (the
    // bar's exclusive zone pushes it up), horizontally under its button.
    readonly property var barWindow: anchorItem.QsWindow.window
    readonly property bool fromTop: !!barWindow && barWindow.edge === "top"
    // Extra gap from the screen edge, for bars that don't reserve space
    // (the auto-hiding dock).
    readonly property int edgeGap: barWindow && barWindow.popupGap !== undefined ? barWindow.popupGap : 0
    screen: barWindow ? barWindow.screen : null
    anchors.top: fromTop
    anchors.bottom: !fromTop
    anchors.left: true
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    margins.top: 4 + edgeGap
    margins.bottom: 4 + edgeGap
    margins.left: {
        void popup.open;
        if (!barWindow || !screen) return 4;
        const p = anchorItem.mapToItem(null, anchorItem.width / 2, 0);
        const w = popup.implicitWidth;
        return Math.max(4, Math.min(screen.width - w - 4, Math.round(p.x - w / 2)));
    }
    // Above the click catcher below (non-Hyprland).
    WlrLayershell.layer: Compositor.isHyprland ? WlrLayer.Top : WlrLayer.Overlay
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
        active: Compositor.isHyprland && popup.visible
        windows: popup.barWindow ? [popup, popup.barWindow] : [popup]
        onCleared: popup.close()
    }

    // Elsewhere (niri/arbor have no focus grab): a transparent surface over
    // everything but the bars, under the popup, closes it on a click.
    PanelWindow {
        visible: popup.visible && !Compositor.isHyprland
        screen: popup.screen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "hearth-popup-catcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: popup.close()
        }
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
