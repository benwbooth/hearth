import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import ".."

// The bottom panel, laid out like the Plasma panel it replaces:
// [spacer] launcher, tasks, devapps [spacer] system monitor, pager | tray, clock, show desktop
PanelWindow {
    id: bar
    required property ShellScreen modelData
    screen: modelData

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

    RowLayout {
        anchors.fill: parent
        spacing: 2
        // At 130% a coordinate ending in .5 rounds glyphs one by one; keep
        // everything a hair off the half pixel.
        transform: Translate { x: 0.001; y: 0.001 }

        Item { Layout.fillWidth: true }
        Launcher {}
        Tasks {}
        DevApps {}
        Item { Layout.fillWidth: true }
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
        Clock {}
        ShowDesktop {}
    }
}
