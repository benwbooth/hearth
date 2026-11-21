import QtQuick
import QtQuick.Effects
import Quickshell
import ".."
import "../services"

// A bar/tray button: icon and/or text, hover highlight and a tooltip.
// Extra children (badges, overlays) go on top of the icon.
// In the macOS menu bar it behaves like a menu bar item: no hover
// highlight, a translucent capsule while its menu is open, and with
// `menuPopup` set the menu opens on press (press-drag-release chooses an
// item, hovering another item while a menu is open switches to it).
MouseArea {
    id: root
    // The popup this button opens (menu bar press/drag/hover handling).
    property var menuPopup: null
    readonly property bool menuBarItem: !!hostWindow && hostWindow.pressTitle !== undefined
    readonly property bool menuPress: !!menuPopup && menuBarItem
    onPressed: mouse => {
        ShellState.pressedIn(root);
        if (menuPress && mouse.button === Qt.LeftButton) hostWindow.pressTitle(root, menuPopup, mouse);
    }
    onPositionChanged: mouse => { if (menuPress && pressed) hostWindow.dragTitle(root, menuPopup, mouse); }
    onReleased: mouse => { if (menuPress && mouse.button === Qt.LeftButton) hostWindow.releaseTitle(root, menuPopup, mouse); }
    onContainsMouseChanged: if (containsMouse && menuBarItem && menuPopup) hostWindow.hoverTitle(menuPopup)
    // The bar finds the title under a drag by asking its registered items.
    property var registeredIn: null
    function syncTitle() {
        const want = menuPress ? hostWindow : null;
        if (registeredIn === want) return;
        if (registeredIn) registeredIn.unregisterTitle(root);
        registeredIn = want;
        if (want) want.registerTitle(root);
    }
    onMenuPressChanged: syncTitle()
    Component.onCompleted: syncTitle()
    Component.onDestruction: if (registeredIn) registeredIn.unregisterTitle(root)
    property string icon: ""
    property string iconFallback: "application-x-executable"
    property string text: ""
    property string tooltip: ""
    property string tooltipSub: ""
    property bool active: false
    // Bar windows may set `barHeight` / `barIconSize` (the thin menu bar).
    readonly property var hostWindow: root.QsWindow.window
    readonly property int hostHeight: hostWindow && hostWindow.barHeight ? hostWindow.barHeight : Theme.barHeight
    property int iconSize: hostWindow && hostWindow.barIconSize ? hostWindow.barIconSize : Theme.iconSize
    property color textColor: Theme.fg
    property bool monochrome: Settings.menubar.monochromeIcons !== false
    default property alias overlay: overlayItem.data

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    implicitHeight: hostHeight
    implicitWidth: menuBarItem && text === "" ? Theme.menuBarItemWidth : Math.max(hostHeight - 12, row.implicitWidth + 12)

    Rectangle {
        visible: !root.menuBarItem
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.radius
        color: root.pressed ? Theme.pressed
             : (root.containsMouse || root.active) ? Theme.hover
             : "transparent"
    }
    // Menu bar: the capsule behind an open item (macOS 26), no hover.
    Rectangle {
        visible: root.menuBarItem
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        radius: height / 2
        color: Theme.menuBarHighlight
        opacity: root.active || (root.pressed && !root.menuPopup) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.active ? 0 : 140; easing.type: Easing.OutCubic } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon {
            id: iconItem
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            name: root.icon
            fallback: root.iconFallback
            implicitSize: root.iconSize
            // Menu bar: monochrome like SF Symbols (Settings > Menu Bar >
            // Monochrome icons): every status icon in the text colour.
            layer.enabled: root.menuBarItem && root.monochrome
            layer.effect: MultiEffect { brightness: Theme.dark ? 1 : -1; saturation: -1 }
            Item {
                id: overlayItem
                anchors.fill: parent
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            color: root.textColor
            font.pointSize: root.hostWindow && root.hostWindow.barFontSize ? root.hostWindow.barFontSize : Theme.fontSize
        }
    }

    Tooltip {
        anchorItem: root
        text: root.tooltip
        subtext: root.tooltipSub
        hovered: root.containsMouse && !root.pressed && !root.active
    }
}
