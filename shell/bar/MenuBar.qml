import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// The macOS-style menu bar (layout "mac"): system menu, the focused app's
// name and menus on the left; tray, indicators and clock on the right.
// Liquid glass, transparent or solid (Settings > Menu Bar > Style); the
// compositor blurs behind it (namespace hearth-menubar, layer rule
// hearth-glass in hypr/hyprland.lua, arbor/hearth-layer-rules.kdl).
// With "automatically hide the menu bar" it slides up and comes back when
// the pointer touches the top edge.
PanelWindow {
    id: bar
    required property ShellScreen modelData
    screen: modelData

    // Read by BarButton / BarPopup / Tooltip in this window.
    readonly property string edge: "top"
    readonly property int barHeight: Theme.menuBarHeight
    readonly property int barIconSize: Theme.menuBarIconSize
    readonly property real barFontSize: Theme.menuBarFontSize
    // Popups clear the bar themselves when it reserves no space (auto-hide).
    readonly property int popupGap: autohide ? barHeight : 0

    readonly property bool autohide: Settings.menubar.autohide
    readonly property bool popupOpen: !!ShellState.activePopup && ShellState.activePopup.barWindow === bar
    readonly property bool revealed: !autohide || hover.hovered || popupOpen

    anchors { left: true; right: true; top: true }
    implicitHeight: barHeight
    exclusiveZone: autohide ? 0 : barHeight
    color: "transparent"
    WlrLayershell.namespace: "hearth-menubar"
    WlrLayershell.layer: WlrLayer.Top
    // Hidden: only a 2 px strip along the top edge takes the pointer.
    mask: Region { item: bar.revealed ? content : strip }

    Item {
        id: strip
        width: parent.width
        height: 2
    }
    HoverHandler { id: hover }

    Item {
        id: content
        width: parent.width
        height: bar.barHeight
        y: bar.revealed ? 0 : -height
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        // The bar's surface, by Settings > Menu Bar > Style:
        //  glass: liquid glass. A light tint over the compositor's blur
        //    (layer rule hearth-glass), a soft sheen from the top, a
        //    specular rim along the top edge (brightest at the left), a
        //    faint inner shadow and light rim at the bottom.
        //  transparent: macOS 26. Nothing but a faint shade from the top
        //    edge (too faint to be blurred); the items float, lifted off the
        //    wallpaper by their text halo.
        //  solid: an opaque strip.
        readonly property string style: Theme.menuBarStyle
        readonly property real spec: Theme.specular
        Rectangle {
            anchors.fill: parent
            visible: content.style !== "transparent"
            color: Theme.menuBarTint
        }
        Rectangle {
            anchors.fill: parent
            visible: content.style === "transparent"
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.22 : 0.0) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
            }
        }
        Item {
            anchors.fill: parent
            visible: content.style === "glass"
            // Sheen: light caught in the top of the glass.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.12 : 0.30) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.025 : 0.08) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
            // Specular rim along the top, fading to the right.
            Rectangle {
                width: parent.width
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, content.spec * 1.6) }
                    GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, content.spec * 0.8) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, content.spec * 0.45) }
                }
            }
            Rectangle {
                y: 1
                width: parent.width
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, content.spec * 0.45) }
                    GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, content.spec * 0.12) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, content.spec * 0.06) }
                }
            }
            // Inner shadow and the light refracted along the bottom edge.
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                width: parent.width
                height: 6
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.16 : 0.06) }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, content.spec * 0.3)
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            visible: content.style !== "transparent"
            color: content.style === "solid" ? Theme.border : Theme.glassEdge
        }

        RowLayout {
            id: left
            height: parent.height
            x: 6
            spacing: 0
            transform: Translate { x: 0.001; y: 0.001 }
            SystemMenu {}
            GlobalMenu {}
        }

        RowLayout {
            id: right
            anchors.right: parent.right
            anchors.rightMargin: 6
            height: parent.height
            spacing: 0
            transform: Translate { x: 0.001; y: 0.001 }

            SysMonitor { visible: Settings.menubar.showSysMonitor }
            DevApps { iconSize: Theme.menuBarIconSize; implicitWidth: 30 }
            Tray {}
            HelpMenu {}
            Clock {}
        }
    }
}
