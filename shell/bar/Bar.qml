import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import ".."

// The bottom panel, laid out like the Plasma panel it replaces:
// launcher, tasks, devapps centered on the screen; system monitor, pager | tray,
// clock, show desktop on the right
PanelWindow {
    id: bar
    required property ShellScreen modelData
    screen: modelData
    readonly property string edge: "bottom"

    anchors {
        left: true
        right: true
        bottom: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.bg
    WlrLayershell.namespace: "hearth-bar"
    WlrLayershell.layer: WlrLayer.Top

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: Theme.border
    }

    // Launcher, tasks and dev apps are centered on the screen (not on the
    // space left of the tray); they slide left only if they'd run into it.
    RowLayout {
        id: center
        height: parent.height
        spacing: 2
        x: Math.max(0, Math.min(Math.round((bar.width - width) / 2),
                                right.x - width - 8))
        // At 130% a coordinate ending in .5 rounds glyphs one by one; keep
        // everything a hair off the half pixel.
        transform: Translate { x: 0.001; y: 0.001 }

        Launcher {}
        Tasks {}
        DevApps {}
    }

    RowLayout {
        id: right
        anchors.right: parent.right
        height: parent.height
        spacing: 2
        transform: Translate { x: 0.001; y: 0.001 }

        SysMonitor {}
        Workspaces { screen: bar.modelData }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: Theme.barHeight - 16
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            color: Theme.border
        }
        Tray {}
        PanelIndicators {}
        Clock {}
        ShowDesktop {}
    }
}
