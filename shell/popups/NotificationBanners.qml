import QtQuick
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// Notification banners (services/Notifications.qml), macOS style: at the
// top right of the focused screen, under the menu bar (bottom right above
// the classic panel), newest on top. Each slides in from the right edge,
// stays while the pointer is on it, and fades out after Settings >
// Notifications > "Show banners for" (urgent ones stay until cleared).
// Click: the app's default action (or its window). Drag one to the right
// to put it away; ✕ clears it. Banners that go away stay in Notification
// Center.
//
// One fixed-size layer surface; only the banners take the pointer.
PanelWindow {
    id: win
    readonly property string edge: Settings.mac ? "top" : "bottom"
    readonly property bool fromTop: edge === "top"
    readonly property real shadowPad: Math.ceil(Theme.menuShadowBlur + Theme.menuShadowY)
    readonly property real gap: Math.round(10 * Theme.pt)
    // The auto-hiding menu bar reserves no space: stay under it anyway.
    readonly property real barGap: fromTop && Settings.menubar.autohide ? Theme.menuBarHeight : 0

    screen: Compositor.focusedScreen || Quickshell.screens[0] || null
    anchors.top: fromTop
    anchors.bottom: !fromTop
    anchors.right: true
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    margins.top: barGap
    // Top, not Overlay: a fullscreen window (a video, a game) is drawn above the
    // top layer, so banners never cover it; they wait in Notification Center.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "hearth-notifications"
    WlrLayershell.keyboardFocus: Notifications.replying > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    implicitWidth: Theme.notificationWidth + shadowPad + Math.round(16 * Theme.pt)
    implicitHeight: screen ? Math.round(screen.height * 0.85) : 1200
    visible: Notifications.wanted && (model.count > 0 || hold.running)
    mask: Region { item: hitArea }
    // Where the banners are (with room for the ✕ over their corners).
    Item {
        id: hitArea
        readonly property real h: Math.min(list.height, list.contentHeight + 16)
        x: list.x - 12
        width: list.width + 12
        y: win.fromTop ? list.y : list.y + list.height - h
        height: model.count > 0 ? h : 0
    }

    // Stays mapped until the last banner's fade has finished.
    Timer { id: hold; interval: Theme.bannerOutMs + 80 }

    // Banners by notification id, synced from Notifications.banners so a
    // banner's delegate (its timer, its animation) survives other changes.
    ListModel { id: model }
    function sync() {
        const ids = Notifications.banners.map(n => n.id);
        for (let i = model.count - 1; i >= 0; i--)
            if (ids.indexOf(model.get(i).nid) < 0) { model.remove(i); hold.restart(); }
        for (let j = 0; j < ids.length; j++) {
            let at = -1;
            for (let i = 0; i < model.count; i++) if (model.get(i).nid === ids[j]) { at = i; break; }
            if (at < 0) model.insert(j, { nid: ids[j] });
            else if (at !== j) model.move(at, j, 1);
        }
    }
    Connections {
        target: Notifications
        function onBannersChanged() { win.sync(); }
    }
    Component.onCompleted: sync()

    ListView {
        id: list
        x: win.shadowPad
        y: win.fromTop ? win.gap : 0
        width: Theme.notificationWidth
        height: parent.height - (win.fromTop ? win.gap : win.gap + win.shadowPad)
        verticalLayoutDirection: win.fromTop ? ListView.TopToBottom : ListView.BottomToTop
        spacing: Math.round(8 * Theme.pt)
        interactive: false
        model: model
        // The ✕ sits over the top-left corner.
        topMargin: 8
        bottomMargin: 8
        leftMargin: 0

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: Theme.notificationWidth + win.gap + win.shadowPad; to: 0; duration: Theme.bannerInMs; easing.type: Easing.OutCubic }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.bannerInMs * 0.6 }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.bannerOutMs; easing.type: Easing.InOutQuad }
                NumberAnimation { property: "x"; to: Math.round(24 * Theme.pt); duration: Theme.bannerOutMs; easing.type: Easing.InCubic }
            }
        }
        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: Theme.bannerInMs; easing.type: Easing.OutCubic }
            NumberAnimation { property: "opacity"; to: 1; duration: 120 }
        }
        move: Transition {
            NumberAnimation { properties: "y"; duration: Theme.bannerInMs; easing.type: Easing.OutCubic }
        }

        delegate: NotificationCard {
            id: banner
            required property int nid
            n: Notifications.byId(nid)
            inBanner: true
            width: Theme.notificationWidth
            height: fullHeight
            closeTip: "Clear this notification (it won't stay in Notification Center)"

            onClicked: if (Math.abs(dragX.x) < 4) Notifications.activate(n)
            onCloseClicked: Notifications.dismiss(n)

            // Stays while the pointer is on it or a reply is being typed.
            readonly property int timeout: n ? Notifications.bannerTimeout(n) : 0
            Timer {
                id: life
                interval: banner.timeout
                running: banner.timeout > 0 && !banner.hovered && !banner.replying
                onTriggered: Notifications.hideBanner(banner.n)
            }
            Connections {
                target: Notifications
                function onBannerShown(n) { if (n === banner.n) life.restart(); }
            }

            // Swipe right to put it away (into Notification Center).
            transform: Translate { id: dragX; x: 0 }
            DragHandler {
                id: drag
                target: null
                xAxis.enabled: true
                yAxis.enabled: false
                onTranslationChanged: dragX.x = Math.max(0, translation.x)
                onActiveChanged: {
                    if (active) return;
                    if (dragX.x > Theme.notificationWidth * 0.25) Notifications.hideBanner(banner.n);
                    else backAnim.start();
                }
            }
            NumberAnimation { id: backAnim; target: dragX; property: "x"; to: 0; duration: 200; easing.type: Easing.OutCubic }
        }
    }
}
