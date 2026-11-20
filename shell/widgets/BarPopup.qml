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
    // No frame of its own: the content draws its own glass (cascading menus).
    property bool bare: false
    // "center": centred on the anchor; "start": left edge at the anchor's
    // (menu bar menus, which grow to the right as submenus open).
    property string align: "center"
    property bool open: false
    // Child popups (cascading submenus) that clicks may land in.
    property var extraWindows: []
    // OnDemand: the popup takes the keyboard when clicked into (search
    // fields, passwords). Exclusive sends all typing straight to it.
    // Exclusive by default, like a macOS menu: Escape closes it.
    property int keyboardFocus: WlrKeyboardFocus.Exclusive

    // A layer-shell panel rather than an xdg popup: popups only get the
    // keyboard through an input grab, which a key bind or `hearth-ipc` can't
    // start. Anchored to the bottom edge it sits just above the bar (the
    // bar's exclusive zone pushes it up), horizontally under its button.
    readonly property var barWindow: anchorItem.QsWindow.window
    readonly property string edge: barWindow && barWindow.edge ? barWindow.edge : "bottom"
    readonly property bool fromTop: edge === "top"
    readonly property bool sideways: edge === "left" || edge === "right"
    // Extra gap from the screen edge, for bars that don't reserve space
    // (the auto-hiding dock / menu bar).
    readonly property int edgeGap: barWindow && barWindow.popupGap !== undefined ? barWindow.popupGap : 0
    screen: barWindow ? barWindow.screen : null
    anchors.top: edge !== "bottom"
    anchors.bottom: edge === "bottom"
    anchors.left: edge !== "right"
    anchors.right: edge === "right"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    margins.top: {
        if (!sideways) return 4 + edgeGap;
        void popup.open;
        if (!barWindow || !screen) return 4;
        const p = anchorItem.mapToItem(null, 0, anchorItem.height / 2);
        const h = popup.implicitHeight;
        return Math.max(4, Math.min(screen.height - h - 4, Math.round(p.y - h / 2)));
    }
    margins.bottom: 4 + edgeGap
    margins.right: 4 + edgeGap
    margins.left: {
        if (edge === "left") return 4 + edgeGap;
        void popup.open;
        if (!barWindow || !screen) return 4;
        const w = popup.implicitWidth;
        if (popup.align === "start") {
            const q = anchorItem.mapToItem(null, 0, 0);
            return Math.max(4, Math.min(screen.width - w - 4, Math.round(q.x)));
        }
        const p = anchorItem.mapToItem(null, anchorItem.width / 2, 0);
        return Math.max(4, Math.min(screen.width - w - 4, Math.round(p.x - w / 2)));
    }
    // Above the click catcher below (non-Hyprland).
    WlrLayershell.layer: Compositor.isHyprland ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.namespace: "hearth-popup"
    // Mapped without keyboard interactivity, which is turned on a moment
    // later: Hyprland gives a keyboard-interactive layer the pointer as it
    // maps (an enter at the cursor's position, outside the popup), after
    // which Qt never shows hover in it until the pointer leaves again.
    WlrLayershell.keyboardFocus: open && keyboardReady ? popup.keyboardFocus : WlrKeyboardFocus.None
    property bool keyboardReady: false
    onVisibleChanged: { keyboardReady = false; if (visible) keyboardTimer.restart(); }
    Timer {
        id: keyboardTimer
        interval: 120
        onTriggered: popup.keyboardReady = popup.visible
    }
    // Stays mapped while it fades out.
    visible: open || fadeOut.running
    color: "transparent"
    implicitWidth: Math.max(8, frame.implicitWidth)
    implicitHeight: Math.max(8, frame.implicitHeight)

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
        windows: (popup.barWindow ? [popup, popup.barWindow] : [popup]).concat(popup.extraWindows)
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

    // Escape closes it (a focused key handler: Shortcut needs an "active"
    // window, which a layer surface never is).
    Item {
        focus: popup.open
        Keys.onEscapePressed: popup.close()
    }

    function toggle() { open = !open; }
    function close() { open = false; }

    GlassFrame {
        id: frame
        anchors.fill: parent
        // Fade and grow in from the bar's side; fade out on close.
        opacity: popup.open ? 1 : 0
        scale: popup.open ? 1 : 0.96
        transformOrigin: popup.fromTop ? Item.Top : popup.edge === "left" ? Item.Left
                       : popup.edge === "right" ? Item.Right : Item.Bottom
        Behavior on opacity { NumberAnimation { id: fadeOut; duration: popup.open ? 140 : 110; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        implicitWidth: body.implicitWidth + popup.padding * 2
        implicitHeight: body.implicitHeight + popup.padding * 2
        tint: popup.bare ? "transparent" : Theme.glassMenu
        border.width: popup.bare ? 0 : 1
        rimVisible: !popup.bare
        // GlassFrame carries the 0.001 px nudge: popups draw in their own
        // surface, outside the bar's.

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
