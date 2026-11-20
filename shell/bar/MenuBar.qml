import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// The macOS-style menu bar (layout "mac"): system menu, the focused app's
// name and menus on the left; tray, indicators and clock on the right.
// Translucent glass, blurred by the compositor (namespace hearth-menubar).
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

        // Liquid glass: a tint over the compositor's blur, a soft specular
        // sheen from the top, a bright inner line along the top edge and a
        // dark hairline underneath.
        Rectangle {
            anchors.fill: parent
            color: Theme.glassBar
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.10 : 0.35) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.02 : 0.08) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, Theme.dark ? 0.14 : 0.6)
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.glassEdge
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

            DevApps { iconSize: Theme.menuBarIconSize; implicitWidth: 30 }
            Tray {}
            Clock {}
        }
    }
}
