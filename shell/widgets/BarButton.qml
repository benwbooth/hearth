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
    Component.onCompleted: { syncTitle(); Qt.callLater(snapIcon); }
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
    // Menu bar icons are drawn pixel-exact: at a size icon themes are drawn
    // for (16/22/24/32 device pixels, the nearest to iconSize) and on the
    // device pixel grid. At a fractional scale (4/3) a 17 px icon was 22.67
    // device pixels between pixels, which blurred every edge.
    // The output's real scale (4/3): with fractional scaling the screen's
    // devicePixelRatio is rounded up (2), the window draws at the true one.
    readonly property real dpr: {
        const sc = hostWindow && hostWindow.screen ? hostWindow.screen : null;
        const o = sc ? Displays.live[sc.name] : null;
        if (o && o.logical && o.logical.scale > 0) return o.logical.scale;
        return sc && sc.devicePixelRatio > 0 ? sc.devicePixelRatio : 1;
    }
    function crispSize(s) {
        if (!menuBarItem) return s;
        const px = s * dpr;
        let best = 22;
        for (const d of [16, 22, 24, 32]) if (Math.abs(d - px) < Math.abs(best - px)) best = d;
        return best / dpr;
    }
    function snapIcon() {
        if (!menuBarItem || !iconItem.visible) return;
        const p = iconItem.mapToItem(null, 0, 0);
        const rx = p.x - iconSnap.x, ry = p.y - iconSnap.y;
        iconSnap.x = Math.round(rx * dpr) / dpr - rx;
        iconSnap.y = Math.round(ry * dpr) / dpr - ry;
    }
    onXChanged: Qt.callLater(snapIcon)
    onYChanged: Qt.callLater(snapIcon)
    onWidthChanged: Qt.callLater(snapIcon)
    onHeightChanged: Qt.callLater(snapIcon)
    onDprChanged: Qt.callLater(snapIcon)
    property color textColor: menuBarItem ? Theme.barFg : Theme.fg
    property bool monochrome: Settings.menubar.monochromeIcons !== false
    // Recolour only the colourless parts (app tray icons; see below).
    property bool adaptive: false
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
            implicitSize: root.crispSize(root.iconSize)
            transform: Translate { id: iconSnap }
            onXChanged: Qt.callLater(root.snapIcon)
            onYChanged: Qt.callLater(root.snapIcon)
            onVisibleChanged: Qt.callLater(root.snapIcon)
            // Menu bar: monochrome like SF Symbols (Settings > Menu Bar >
            // Monochrome icons): every status icon in the text colour.
            // App tray icons (`adaptive`): only their colourless pixels take
            // the text colour (shaders/trayicon.frag), so white "template"
            // icons made for dark panels read on a light bar too.
            layer.enabled: root.menuBarItem && (root.monochrome || root.adaptive)
            layer.effect: root.monochrome ? monoFx : adaptiveFx
            Component { id: monoFx; MultiEffect { brightness: Theme.barDark ? 1 : -1; saturation: -1 } }
            Component {
                id: adaptiveFx
                ShaderEffect {
                    fragmentShader: "../shaders/trayicon.frag.qsb"
                    readonly property color target: Theme.barFg
                }
            }
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
