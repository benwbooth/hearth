import QtQuick
import Quickshell
import "../widgets"
import "../services"
import ".."

// The menu bar's leftmost button (macOS's Apple menu): about, settings,
// the launcher, and the session actions from services/Session.qml.
BarButton {
    id: root
    // The logo (Settings > Menu Bar): NixOS snowflake (default), a penguin,
    // or "none" for a plain menu glyph.
    readonly property string logo: Settings.menubar.logo || "nixos"
    icon: logo === "none" ? "application-menu" : ""
    tooltip: "System menu: settings, sleep, restart, shut down, lock and log out"
    active: menu.open
    implicitWidth: Math.round(32 * Theme.pt)
    menuPopup: menu
    onClicked: if (!menuPress) menu.toggle()

    Logo {
        // BarButton's default property puts children on its icon, which is
        // hidden here.
        parent: root
        anchors.centerIn: parent
        visible: root.logo !== "none"
        name: root.logo
        size: root.hostHeight > 34 ? 22 : Math.round(14 * Theme.pt)
    }

    BarPopup {
        id: menu
        menuBarMenu: true
        align: "start"
        anchorItem: root
        padding: Theme.menuPadding
        Column {
            width: Math.round(220 * Theme.pt)
            MenuItem {
                text: "About This Computer"
                onTriggered: { menu.close(); Quickshell.execDetached(["kinfocenter"]); }
            }
            MenuSeparator {}
            MenuItem {
                text: "hearth Settings…"
                onTriggered: { menu.close(); Settings.openRequested(""); }
            }
            MenuItem {
                text: "System Settings…"
                onTriggered: { menu.close(); Quickshell.execDetached(["systemsettings"]); }
            }
            MenuItem {
                text: "Search Apps…"
                onTriggered: { menu.close(); Quickshell.execDetached(["vicinae", "toggle"]); }
            }
            MenuSeparator {}
            MenuItem { text: "Sleep"; onTriggered: { menu.close(); Session.run("suspend"); } }
            MenuItem { text: "Restart…"; onTriggered: { menu.close(); Session.run("reboot"); } }
            MenuItem { text: "Shut Down…"; onTriggered: { menu.close(); Session.run("poweroff"); } }
            MenuSeparator {}
            MenuItem { text: "Lock Screen"; onTriggered: { menu.close(); Session.run("lock"); } }
            MenuItem { text: "Log Out…"; onTriggered: { menu.close(); Session.run("logout"); } }
        }
    }
}
