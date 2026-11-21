import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../widgets"
import "../services"
import ".."

// Small card about the current wallpaper (services/Wallpaper.qml): source,
// title, credit, open the story in the browser, save a copy to ~/Pictures,
// previous/next picture, Wallpaper settings.
// Opened with `hearth-ipc call wallpaper info`; bottom-right above the bar on
// the focused monitor, closes on Escape or a click elsewhere.
PanelWindow {
    id: win
    property bool open: false

    screen: Compositor.focusedScreen
    anchors { bottom: true; right: true }
    margins { bottom: 8; right: 8 }
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hearth-wallpaper-info"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    visible: open
    implicitWidth: 380
    implicitHeight: frame.implicitHeight

    Connections {
        target: Wallpaper
        function onInfoRequested() { win.open = !win.open; }
    }

    HyprlandFocusGrab {
        active: Compositor.isHyprland && win.visible
        windows: [win]
        onCleared: win.open = false
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        color: Theme.bgAlt
        border.color: Theme.border
        border.width: 1
        radius: Theme.popupRadius
        implicitHeight: col.implicitHeight + 24
        transform: Translate { x: 0.001; y: 0.001 }
        focus: true
        Keys.onEscapePressed: win.open = false

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            Label {
                Layout.fillWidth: true
                text: Wallpaper.sourceName || "Wallpaper"
                color: Theme.fgDim
                font.pointSize: Theme.smallFontSize
            }
            Label {
                Layout.fillWidth: true
                text: Wallpaper.title || "No image yet"
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: Wallpaper.copyright
                color: Theme.fgDim
                wrapMode: Text.Wrap
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: Wallpaper.error
                color: Theme.warn
                wrapMode: Text.Wrap
            }
            Item { implicitHeight: 4 }
            MenuItem {
                Layout.fillWidth: true
                visible: Wallpaper.link !== ""
                icon: "internet-web-browser"
                text: "Open in browser"
                onTriggered: { Wallpaper.openLink(); win.open = false; }
            }
            MenuItem {
                Layout.fillWidth: true
                visible: Wallpaper.file !== ""
                icon: "document-save-as"
                text: "Save image to Pictures"
                onTriggered: { Wallpaper.saveCopy(); win.open = false; }
            }
            MenuItem {
                Layout.fillWidth: true
                readonly property var sp: Wallpaper.primarySpec
                visible: !!sp && (sp.type === "potd" || sp.type === "folder")
                icon: "go-previous"
                text: "Previous picture"
                onTriggered: Wallpaper.previous("")
            }
            MenuItem {
                Layout.fillWidth: true
                readonly property var sp: Wallpaper.primarySpec
                visible: !!sp && (sp.type === "potd" || sp.type === "folder")
                icon: "go-next"
                text: "Next picture"
                onTriggered: Wallpaper.next("")
            }
            MenuItem {
                Layout.fillWidth: true
                icon: "preferences-desktop-wallpaper"
                text: "Wallpaper settings…"
                onTriggered: { Settings.openRequested("wallpaper"); win.open = false; }
            }
        }
    }
}
