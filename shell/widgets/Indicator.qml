import QtQuick
import Quickshell
import Quickshell.Io
import "../services"
import ".."

// A tray indicator: a BarButton that opens `popupContent` on left click.
// Right/middle clicks and the wheel are passed on via signals.
BarButton {
    id: root
    property Component popupContent: null
    property alias popup: pop
    property bool shown: true
    // When set, `hearth-ipc call indicator-<ipcName> toggle` opens the popup
    // (for Hyprland binds and for headless testing).
    property string ipcName: ""
    readonly property bool ipcHere: ShellState.isActiveScreen(root.QsWindow.window ? root.QsWindow.window.screen : null)
    signal rightClicked()
    signal middleClicked()
    signal scrolled(int delta)

    // Settings > Menu Bar can hide an indicator by its ipcName (the menu
    // bar item id, services/BarItems.qml); "only in the ⌃ menu" or a full
    // bar moves it into the overflow dropdown (BarButton.overflowed).
    readonly property bool present: shown && (ipcName === "" || BarItems.show(ipcName) !== "hidden")
    overflowKey: ipcName
    visible: present && !overflowed
    // Chosen from the overflow dropdown: the popup, under the chevron.
    function overflowActivate() { if (popupContent) pop.open = true; }
    active: pop.open
    menuPopup: root.popupContent ? pop : null

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton && root.popupContent) { if (!root.menuPress) pop.toggle(); }
        else if (mouse.button === Qt.RightButton) root.rightClicked();
        else if (mouse.button === Qt.MiddleButton) root.middleClicked();
    }
    onWheel: w => root.scrolled(w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x)

    Connections {
        target: ShellState
        function onOpenIndicator(name) {
            if (name === root.ipcName && root.ipcHere && root.popupContent && root.present) pop.open = true;
        }
    }

    IpcHandler {
        target: root.ipcName && root.ipcHere ? "indicator-" + root.ipcName : ""
        enabled: target !== ""
        function toggle(): void { if (root.popupContent) pop.toggle(); }
        function open(): void { if (root.popupContent) pop.open = true; }
        function close(): void { pop.close(); }
    }

    BarPopup {
        id: pop
        anchorItem: root.popupAnchor
        // Kept while the popup fades out (visible outlasts open).
        Loader {
            active: pop.visible
            sourceComponent: root.popupContent
        }
    }
}
