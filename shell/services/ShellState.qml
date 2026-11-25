pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shell-wide UI state, also reachable from Hyprland binds through
// `hearth-ipc call <target> <function>`.
Singleton {
    id: root
    // The open BarPopup, so opening one closes the others.
    property var activePopup: null
    // Tooltips (widgets/Tooltip.qml): the one on screen, and until when the
    // next one shows at once (moving along the bar, like macOS).
    property var tooltip: null
    property real tooltipWarmUntil: 0
    // Dock window previews (bar/TaskButton.qml): one is open, or was a
    // moment ago, so the next app's opens at once.
    property int dockPreviews: 0
    property var dockPreview: null
    property real dockPreviewWarmUntil: 0
    // A press on a bar/dock button: close the open popup unless it belongs
    // to that button (whose own click toggles it). The popups' focus grab
    // lets clicks through to their bar, so without this a menu stayed open
    // while you clicked other dock icons.
    function pressedIn(item) {
        const p = activePopup;
        if (!p || !p.open || p.anchorItem === item) return;
        // A button inside the open popup itself (Bluetooth's Connect,
        // Drives' Eject): pressing it must not close that popup, or the
        // click never lands.
        const w = item && item.QsWindow ? item.QsWindow.window : null;
        if (w && w === p) return;
        p.close();
    }
    // Open a menu bar indicator's menu by its ipcName (Control Center's ›).
    signal openIndicator(string name)
    // Ask the overview to open (dock menu "Show All Windows").
    signal overviewRequested()

    // Per-screen bar pieces (IPC targets) act only on the
    // focused monitor, so a second screen (e.g. hypr-rdp's virtual one)
    // doesn't register duplicate targets.
    function isActiveScreen(screen) {
        const m = Compositor.focusedOutput;
        if (!m || !screen) return true;
        return m === screen.name;
    }

    // The launcher is Vicinae; kept so `hearth-ipc call launcher toggle`
    // still works.
    IpcHandler {
        target: "launcher"
        function toggle(): void { Quickshell.execDetached(["vicinae", "toggle"]); }
        function open(): void { Quickshell.execDetached(["vicinae", "open"]); }
        function close(): void { Quickshell.execDetached(["vicinae", "close"]); }
    }
}
