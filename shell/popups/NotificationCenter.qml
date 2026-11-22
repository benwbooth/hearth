import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// Notification Center (services/Notifications.qml), macOS 26 style: a
// column of glass cards along the right edge of the screen, under the
// menu bar, sliding in from the right; no panel behind it. A slim glass
// header holds Do Not Disturb and Clear All. Each app's notifications
// stack (widgets/NotificationStack.qml): click a stack to fan it out.
// Opened from the bell in the menu bar, a hot corner, or
// `hearth-ipc call notifications toggle`; a click anywhere else or Esc
// closes it.
Scope {
    id: root
    readonly property bool open: Notifications.centerOpen
    readonly property real shadowPad: Math.ceil(Theme.menuShadowBlur + Theme.menuShadowY)
    readonly property real gap: Math.round(10 * Theme.pt)

    PanelWindow {
        id: win
        readonly property string edge: "top"
        readonly property real barGap: Settings.mac && Settings.menubar.autohide ? Theme.menuBarHeight : 0
        screen: Compositor.focusedScreen || Quickshell.screens[0] || null
        anchors { top: true; bottom: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        margins.top: barGap
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-notifications"
        // On demand: it takes the keyboard only when clicked into (a reply,
        // Esc); never exclusive, which kept typing from every window.
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: Theme.notificationWidth + root.shadowPad + Math.round(16 * Theme.pt)
        visible: Notifications.wanted && (root.open || slide.running || pane.opacity > 0.01)
        mask: Region { item: hitArea }

        Item {
            id: hitArea
            x: pane.x + root.shadowPad - 12
            y: 0
            width: Theme.notificationWidth + 12
            height: Math.min(win.height, header.height + root.gap + list.contentHeight + 2 * root.gap + 8)
        }

        Item {
            id: keys
            focus: root.open
            Keys.onEscapePressed: Notifications.closeCenter()
        }

        // Slides in from the right edge, fades out.
        Item {
            id: pane
            width: parent.width
            height: parent.height
            x: root.open ? 0 : Math.round(Theme.notificationWidth * 0.4)
            opacity: root.open ? 1 : 0
            Behavior on x { NumberAnimation { id: slide; duration: root.open ? Theme.bannerInMs : Theme.bannerOutMs; easing.type: root.open ? Easing.OutCubic : Easing.InCubic } }
            Behavior on opacity { NumberAnimation { duration: root.open ? Theme.bannerInMs * 0.6 : Theme.bannerOutMs } }
            transform: Translate { x: 0.001; y: 0.001 }

            // Slim header: title, Do Not Disturb, Clear All.
            GlassFrame {
                id: header
                x: root.shadowPad
                y: root.gap
                width: Theme.notificationWidth
                height: Math.round(36 * Theme.pt)
                radius: height / 2
                tint: Theme.glassNotification
            realGlassTint: Theme.notificationRealTint
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Math.round(14 * Theme.pt)
                    anchors.rightMargin: Math.round(6 * Theme.pt)
                    spacing: Math.round(6 * Theme.pt)
                    Label {
                        Layout.fillWidth: true
                        text: "Notifications"
                        font.pointSize: Theme.macPt(13)
                        font.weight: Font.DemiBold
                        font.letterSpacing: Theme.menuTracking
                    }
                    GlassPill {
                        icon: Notifications.dnd ? "notifications-disabled-symbolic" : "notifications-symbolic"
                        text: Notifications.dnd ? "Do Not Disturb" : ""
                        checked: Notifications.dnd
                        tooltip: Notifications.dnd
                            ? "Do Not Disturb is on: no banners, notifications still collect here. Click to turn it off."
                            : "Do Not Disturb: no banners, notifications still collect here"
                        onClicked: Notifications.toggleDnd()
                    }
                    GlassPill {
                        visible: Notifications.count > 0
                        text: "Clear All"
                        tooltip: "Clear every notification"
                        onClicked: Notifications.clearAll()
                    }
                }
            }

            Flickable {
                id: list
                x: 0
                y: header.y + header.height + root.gap
                width: parent.width
                height: parent.height - y
                contentWidth: width
                contentHeight: col.implicitHeight + 2 * root.gap
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: col
                    x: root.shadowPad
                    y: 8
                    width: Theme.notificationWidth
                    spacing: Math.round(12 * Theme.pt)

                    // Nothing here.
                    GlassFrame {
                        visible: Notifications.count === 0
                        width: parent.width
                        height: Math.round(56 * Theme.pt)
                        radius: Theme.notificationRadius
                        tint: Theme.glassNotification
            realGlassTint: Theme.notificationRealTint
                        Label {
                            anchors.centerIn: parent
                            text: "No Notifications"
                            color: Theme.fgSecondary
                            font.pointSize: Theme.macPt(13)
                        }
                    }

                    Repeater {
                        model: Notifications.groups
                        NotificationStack {
                            required property var modelData
                            group: modelData
                            height: implicitHeight
                        }
                    }
                }
            }
        }
    }

    // A click anywhere else closes it.
    PanelWindow {
        visible: root.open && Notifications.wanted
        screen: win.screen
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
            onPressed: Notifications.closeCenter()
        }
    }
}
