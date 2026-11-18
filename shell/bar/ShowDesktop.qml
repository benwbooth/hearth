import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// Show desktop: jump to an empty workspace, click again to come back.
BarButton {
    id: root
    property var previous: null
    readonly property bool showing: previous !== null && Hyprland.focusedWorkspace
        && Hyprland.focusedWorkspace.toplevels.values.length === 0
    implicitWidth: 30
    icon: "user-desktop"
    tooltip: showing ? "Back to windows" : "Show desktop"
    active: showing

    onClicked: toggle()

    IpcHandler {
        target: ShellState.isActiveScreen(QsWindow.window ? QsWindow.window.screen : null) ? "desktop" : ""
        function toggle(): void { root.toggle(); }
    }

    function toggle() {
        if (showing) {
            Hypr.focusWorkspace(previous);
            previous = null;
        } else {
            previous = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : null;
            Hypr.focusWorkspace("empty");
        }
    }
}
