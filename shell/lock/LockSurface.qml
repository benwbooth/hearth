import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Networking
import "../desktop"
import "../widgets"
import "../services"
import ".."

// One screen of the lock screen, macOS 26 style: the wallpaper (animated
// ones keep playing, then slow to a still once you start typing), the date
// and a big thin clock, now playing, the notification count; at the bottom
// your picture and name, the glass password field that appears on any key
// or click, the fingerprint hint, and Sleep / Restart / Shut Down; status
// glyphs (keyboard layout, network, battery) at the top right. Screens
// other than the main one show the wallpaper and the clock only.
Item {
    id: root
    required property var screen
    readonly property string output: screen ? screen.name : ""
    readonly property bool isMain: output === Lock.mainOutput
                                   || (!Quickshell.screens.some(s => s.name === Lock.mainOutput) && Quickshell.screens[0] === screen)
    readonly property var cfg: Settings.lockScreen
    readonly property var view: Wallpaper.views[output] || null
    readonly property real k: Math.max(0.75, Math.min(1.6, height / 1400))    // size scale for small/large screens
    focus: true
    transform: Translate { x: 0.001; y: 0.001 }

    // ---------------------------------------------------------- the wallpaper

    // Settled: the field is up (typing): animation slows to a still, the
    // picture blurs a little and zooms in, like macOS.
    readonly property bool settled: Lock.fieldShown && !Lock.unlocking
    property real speed: settled ? 0 : 1
    Behavior on speed { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } }
    property real blurAmt: settled ? 0.55 : 0
    Behavior on blurAmt { NumberAnimation { duration: Lock.unlocking ? 380 : 600; easing.type: Easing.OutCubic } }
    property real zoom: settled ? 1.035 : 1
    Behavior on zoom { NumberAnimation { duration: Lock.unlocking ? 380 : 700; easing.type: Easing.OutCubic } }

    // The zoom sits inside `backdrop`, so the blur and the glass patches
    // (which read backdrop) see it.
    Item {
        id: backdrop
        anchors.fill: parent
        clip: true
        WallpaperView {
            id: wall
            anchors.fill: parent
            scale: root.zoom
            view: root.view
            px: Qt.size(Math.round(root.width * (root.screen ? root.screen.devicePixelRatio || 1 : 1)),
                        Math.round(root.height * (root.screen ? root.screen.devicePixelRatio || 1 : 1)))
            speed: root.speed
            paused: !root.cfg.animated || !Lock.locked
                    || (!!Wallpaper.cfg.pauseBattery && Wallpaper.onBattery)
        }
    }
    ShaderEffectSource {
        id: backdropTex
        anchors.fill: parent
        sourceItem: backdrop
        hideSource: root.blurAmt > 0.001
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        visible: root.blurAmt > 0.001
        source: backdropTex
        autoPaddingEnabled: false     // clamp at the screen edges instead of fading to clear
        blurEnabled: true
        blur: root.blurAmt
        blurMax: 64
    }
    // Shade for the clock at the top and the user at the bottom.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.22) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.30) }
        }
        opacity: ui.opacity
    }

    // Fades the whole screen in from black once the wallpaper is ready.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: wall.ready || readyFallback.done ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    }
    Timer { id: readyFallback; property bool done: false; interval: 700; running: true; onTriggered: done = true }

    // ------------------------------------------------------------- input

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) Lock.submit();
        else if (event.key === Qt.Key_Backspace) Lock.backspace(ctrl);
        else if (event.key === Qt.Key_Escape) Lock.clearField();
        else if (ctrl && event.key === Qt.Key_U) Lock.backspace(true);
        else if (event.text && !ctrl && !(event.modifiers & Qt.AltModifier) && event.text.charCodeAt(0) >= 32
                 && event.text.charCodeAt(0) !== 127) {
            Lock.mainOutput = root.output;
            Lock.typeText(event.text);
        } else {
            Lock.activity();
            Lock.showField();
        }
        event.accepted = true;
    }
    Component.onCompleted: forceActiveFocus()

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        // The pointer entering the new surface isn't activity: only real
        // movement (or the grace period would end at once).
        property point first: Qt.point(-1, -1)
        property double since: Date.now()
        onPositionChanged: mouse => {
            if (Date.now() - since < 600) { first = Qt.point(mouse.x, mouse.y); return; }
            if (first.x < 0) { first = Qt.point(mouse.x, mouse.y); return; }
            if (Math.abs(mouse.x - first.x) + Math.abs(mouse.y - first.y) > 12) {
                first = Qt.point(mouse.x, mouse.y);
                Lock.activity();
            }
        }
        onPressed: {
            Lock.mainOutput = root.output;
            root.forceActiveFocus();
            Lock.activity();
            Lock.showField();
        }
        onWheel: Lock.activity()
    }

    // ---------------------------------------------------------------- UI

    Item {
        id: ui
        anchors.fill: parent
        opacity: 0
        scale: 1
        Component.onCompleted: appear.start()
        ParallelAnimation {
            id: appear
            NumberAnimation { target: ui; property: "opacity"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
            NumberAnimation { target: clockCol; property: "shift"; from: -28 * root.k; to: 0; duration: 700; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            id: vanish
            NumberAnimation { target: ui; property: "opacity"; to: 0; duration: 300; easing.type: Easing.InCubic }
            NumberAnimation { target: ui; property: "scale"; to: 1.08; duration: 380; easing.type: Easing.InCubic }
            onFinished: if (root.isMain) Lock.finishUnlock()
        }
        Connections {
            target: Lock
            function onUnlockAnimationRequested() { vanish.start(); }
            // Test sessions: a picture of this screen (arbor takes no
            // screenshots while locked).
            function onTestShotRequested(path) {
                if (root.isMain) root.grabToImage(r => r.saveToFile(path));
            }
        }

        // ---- date and clock
        Column {
            id: clockCol
            property real shift: 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height * 0.075 + shift
            spacing: -4 * root.k

            property date now: new Date()
            Timer {
                interval: 1000
                running: Lock.locked
                repeat: true
                triggeredOnStart: true
                onTriggered: clockCol.now = new Date()
            }
            readonly property bool h24: root.cfg.clock === "24" || (root.cfg.clock !== "12" && !!Settings.menubar.clock24h)

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.cfg.dateFormat !== "none"
                text: Qt.formatDate(clockCol.now, root.cfg.dateFormat === "short" ? "ddd MMM d" : "dddd, MMMM d")
                color: Qt.rgba(1, 1, 1, 0.92)
                font.family: Theme.displayFontFamily
                font.pointSize: 0.75 * Math.round(26 * root.k)
                font.weight: Font.DemiBold
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.12)
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    const d = clockCol.now;
                    if (clockCol.h24) return Qt.formatTime(d, "HH:mm");
                    let h = d.getHours() % 12;
                    if (h === 0) h = 12;
                    return h + ":" + Qt.formatTime(d, "mm");
                }
                color: Qt.rgba(1, 1, 1, 0.94)
                font.family: Theme.displayFontFamily
                readonly property int px: Math.round(Math.min(root.height * 0.14, 210 * root.k))
                font.pointSize: 0.75 * Math.max(1, px)
                font.weight: Font.Thin
                font.features: { "tnum": 1 }
                font.letterSpacing: -0.02 * px
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.10)
            }
        }

        // ---- now playing and notifications (main screen)
        Column {
            id: widgets
            visible: root.isMain
            anchors.horizontalCenter: parent.horizontalCenter
            y: clockCol.y + clockCol.height + 26 * root.k
            spacing: 12 * root.k
            LockMedia {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !!root.cfg.showMedia && player !== null
                backdrop: backdrop
                k: root.k
            }
            LockGlass {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !!root.cfg.showNotifications && Lock.notificationCount > 0
                backdrop: backdrop
                width: notifRow.implicitWidth + 28 * root.k
                height: 34 * root.k
                Row {
                    id: notifRow
                    anchors.centerIn: parent
                    spacing: 8 * root.k
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "notifications-symbolic"
                        implicitSize: Math.round(16 * root.k)
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Lock.notificationCount === 1 ? "1 notification" : Lock.notificationCount + " notifications"
                        color: "white"
                        font.pointSize: 0.75 * Math.round(14 * root.k)
                        font.weight: Font.Medium
                    }
                }
            }
        }

        // ---- status glyphs, top right (main screen)
        Row {
            visible: root.isMain
            anchors { top: parent.top; right: parent.right; topMargin: 14 * root.k; rightMargin: 22 * root.k }
            spacing: 16 * root.k
            readonly property var bat: UPower.displayDevice
            LockButton {
                visible: Keyboard.liveNames.length > 1
                k: root.k
                flat: true
                text: {
                    const l = Keyboard.liveLayouts[Keyboard.currentIndex];
                    return l ? String(l.layout || "").toUpperCase() : (Keyboard.liveNames[Keyboard.currentIndex] || "").slice(0, 2).toUpperCase();
                }
                tip: "Keyboard layout: " + (Keyboard.liveNames[Keyboard.currentIndex] || "") + ". Click to switch."
                onClicked: {
                    Lock.activity();
                    Compositor.arborAction("SwitchLayout", { layout: "Next" });
                    Keyboard.refreshLive();
                }
            }
            LockButton {
                readonly property var devs: Networking.devices.values
                readonly property var wired: devs.find(d => d.type === DeviceType.Wired && d.connected) ?? null
                readonly property var wifi: devs.find(d => d.type === DeviceType.Wifi && d.connected) ?? null
                visible: Networking.backend !== NetworkBackendType.None
                k: root.k
                flat: true
                icon: wired ? "network-wired-activated-symbolic" : wifi ? "network-wireless-connected-100-symbolic" : "network-offline-symbolic"
                tip: wired ? "Connected by cable" : wifi ? "Connected to Wi-Fi" : "Not connected"
            }
            LockButton {
                readonly property var d: parent.bat
                visible: !!d && d.isLaptopBattery && d.isPresent
                k: root.k
                flat: true
                readonly property int pct: d ? Math.round(d.percentage * 100) : 0
                readonly property bool charging: d && (d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged)
                icon: "battery-" + String(Math.min(100, Math.round(pct / 10) * 10)).padStart(3, "0") + (charging ? "-charging" : "") + "-symbolic"
                text: pct + "%"
                tip: charging ? "Battery charging, " + pct + "%" : "Battery " + pct + "%"
            }
        }

        // ---- the user, the field, the hints (main screen)
        Column {
            id: userCol
            visible: root.isMain
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: powerRow.top
            anchors.bottomMargin: 34 * root.k
            spacing: 10 * root.k

            ClippingRectangle {
                id: avatarBox
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(76 * root.k)
                height: width
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.22)
                border.color: Qt.rgba(1, 1, 1, 0.35)
                border.width: 1
                Image {
                    anchors.fill: parent
                    visible: Lock.avatar !== "" && status === Image.Ready
                    source: Lock.avatar ? "file://" + Lock.avatar : ""
                    sourceSize: Qt.size(parent.width * 2, parent.height * 2)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
                Label {
                    anchors.centerIn: parent
                    visible: Lock.avatar === ""
                    text: Lock.initials
                    color: "white"
                    font.family: Theme.displayFontFamily
                    font.pointSize: 0.75 * Math.round(parent.width * 0.38)
                    font.weight: Font.Medium
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lock.displayName
                color: "white"
                font.pointSize: 0.75 * Math.round(17 * root.k)
                font.weight: Font.DemiBold
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.15)
            }

            // Field and hint share one slot: the hint shows until the field appears.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: field.width
                height: field.height

                Label {
                    anchors.centerIn: parent
                    opacity: Lock.fieldShown ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    text: Lock.graceActive ? "Move the mouse or press a key to unlock"
                          : Lock.fpState === "retry" ? Lock.fpMessage
                          : Lock.fpState === "waiting" ? "Touch the fingerprint reader or enter your password"
                          : "Enter your password"
                    color: Qt.rgba(1, 1, 1, 0.85)
                    font.pointSize: 0.75 * Math.round(13 * root.k)
                    font.weight: Font.Medium
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.3)
                }

                LockGlass {
                    id: field
                    backdrop: backdrop
                    width: Math.round(260 * root.k)
                    height: Math.round(36 * root.k)
                    property real shake: 0
                    x: shake
                    opacity: Lock.fieldShown ? 1 : 0
                    scale: Lock.fieldShown ? 1 : 0.92
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                    tint: Qt.rgba(1, 1, 1, 0.16)

                    SequentialAnimation {
                        id: shakeAnim
                        loops: 1
                        NumberAnimation { target: field; property: "shake"; to: -14; duration: 50; easing.type: Easing.OutQuad }
                        NumberAnimation { target: field; property: "shake"; to: 12; duration: 70; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: field; property: "shake"; to: -9; duration: 70; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: field; property: "shake"; to: 6; duration: 60; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: field; property: "shake"; to: -3; duration: 50; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: field; property: "shake"; to: 0; duration: 50; easing.type: Easing.OutQuad }
                    }
                    Connections {
                        target: Lock
                        function onWrongPassword() { shakeAnim.restart(); }
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 16 * root.k
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Lock.typed === 0
                        text: "Enter Password"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.pointSize: 0.75 * Math.round(14 * root.k)
                    }
                    // Dots, one per character (the newest stay in view).
                    Label {
                        id: dots
                        anchors.left: parent.left
                        anchors.leftMargin: 16 * root.k
                        anchors.right: trail.left
                        anchors.rightMargin: 6 * root.k
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Lock.typed > 0
                        text: "●".repeat(Lock.typed)
                        elide: Text.ElideLeft
                        color: "white"
                        opacity: Lock.checking ? 0.5 : 1
                        font.pointSize: 0.75 * Math.round(10 * root.k)
                        font.letterSpacing: 3 * root.k
                    }
                    Row {
                        id: trail
                        anchors.right: parent.right
                        anchors.rightMargin: 5 * root.k
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6 * root.k
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Lock.capsLock
                            text: "⇪"
                            color: Qt.rgba(1, 1, 1, 0.8)
                            font.pointSize: 0.75 * Math.round(16 * root.k)
                        }
                        // Submit arrow (a spinner while PAM checks).
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(26 * root.k); height: width; radius: width / 2
                            color: Qt.rgba(1, 1, 1, Lock.typed > 0 ? 0.28 : 0.10)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Label {
                                anchors.centerIn: parent
                                visible: !Lock.checking
                                text: "→"
                                color: Qt.rgba(1, 1, 1, Lock.typed > 0 ? 1 : 0.45)
                                font.pointSize: 0.75 * Math.round(15 * root.k)
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                visible: Lock.checking
                                width: parent.width * 0.55; height: width; radius: width / 2
                                color: "transparent"
                                border.color: Qt.rgba(1, 1, 1, 0.9)
                                border.width: 2
                                Rectangle {
                                    width: 5 * root.k; height: width; radius: width / 2
                                    color: Theme.accent
                                    x: parent.width / 2 - width / 2; y: -width / 2 + 1
                                }
                                RotationAnimation on rotation { running: Lock.checking; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Lock.submit()
                            }
                        }
                    }
                }
            }

            // Fingerprint glyph + messages under the field.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(hintCol.implicitWidth, 10)
                height: Math.round(54 * root.k)
                Column {
                    id: hintCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6 * root.k
                    Item {
                        id: fpGlyph
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Listening: a pulsing ring. Asleep (a minute without
                        // input, services/Lock.qml): the same glyph, still and
                        // dimmer, and a click wakes the reader.
                        readonly property bool asleep: Lock.fpState === "sleeping"
                        visible: (Lock.fieldShown && (Lock.fpState === "waiting" || Lock.fpState === "retry")) || asleep
                        opacity: asleep ? (wakeArea.containsMouse ? 0.95 : 0.6) : 1
                        width: Math.round(26 * root.k); height: width
                        property real shake: 0
                        MouseArea {
                            id: wakeArea
                            anchors.fill: parent
                            anchors.margins: -6 * root.k
                            enabled: fpGlyph.asleep
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Lock.wakeFingerprint()
                        }
                        Rectangle {
                            id: pulse
                            anchors.centerIn: parent
                            width: parent.width; height: width; radius: width / 2
                            color: "transparent"
                            border.color: Lock.fpState === "retry" ? Theme.bad : Qt.rgba(1, 1, 1, 0.7)
                            // Asleep: a still ring around the glyph.
                            Binding on scale { when: fpGlyph.asleep; value: 1 }
                            Binding on opacity { when: fpGlyph.asleep; value: 0.8 }
                            border.width: 1.5
                            SequentialAnimation on scale {
                                running: fpGlyph.visible && !fpGlyph.asleep
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 1.7; duration: 1600; easing.type: Easing.OutCubic }
                                PauseAnimation { duration: 400 }
                            }
                            SequentialAnimation on opacity {
                                running: fpGlyph.visible && !fpGlyph.asleep
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.8; to: 0; duration: 1600; easing.type: Easing.OutCubic }
                                PauseAnimation { duration: 400 }
                            }
                        }
                        Icon {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: fpGlyph.shake
                            name: "fingerprint-symbolic"
                            fallback: "fingerprint"
                            implicitSize: Math.round(20 * root.k)
                        }
                        SequentialAnimation {
                            id: fpShake
                            NumberAnimation { target: fpGlyph; property: "shake"; to: -5; duration: 50 }
                            NumberAnimation { target: fpGlyph; property: "shake"; to: 5; duration: 70 }
                            NumberAnimation { target: fpGlyph; property: "shake"; to: -3; duration: 60 }
                            NumberAnimation { target: fpGlyph; property: "shake"; to: 0; duration: 50 }
                        }
                        Connections {
                            target: Lock
                            function onFpStateChanged() { if (Lock.fpState === "retry") fpShake.restart(); }
                        }
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: text !== "" && (Lock.fieldShown || Lock.fpState === "sleeping")
                        text: Lock.message !== "" ? Lock.message
                              : Lock.capsLock ? "Caps Lock is on"
                              : Lock.fpState === "retry" ? Lock.fpMessage
                              : Lock.fpState === "waiting" ? "Touch the fingerprint reader"
                              : Lock.fpState === "sleeping" ? "Click the fingerprint to use it"
                              : ""
                        color: Lock.message !== "" ? "#ffd1d1" : Qt.rgba(1, 1, 1, 0.75)
                        font.pointSize: 0.75 * Math.round(12.5 * root.k)
                        font.weight: Font.Medium
                    }
                }
            }
        }

        // ---- Sleep / Restart / Shut Down (main screen)
        Item {
            id: powerRow
            visible: root.isMain && !!root.cfg.showPower
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 30 * root.k
            width: Math.max(buttons.implicitWidth, confirm.width)
            height: visible ? Math.max(buttons.implicitHeight, confirm.height) : 0
            property string asking: ""     // "reboot" | "poweroff"

            Row {
                id: buttons
                anchors.centerIn: parent
                spacing: 34 * root.k
                opacity: powerRow.asking === "" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                LockButton {
                    k: root.k; round: true; backdrop: backdrop
                    icon: "system-suspend-symbolic"; caption: "Sleep"
                    tip: "Put the computer to sleep"
                    onClicked: Session.run("suspend")
                }
                LockButton {
                    k: root.k; round: true; backdrop: backdrop
                    icon: "system-reboot-symbolic"; caption: "Restart"
                    tip: "Restart the computer"
                    onClicked: powerRow.asking = "reboot"
                }
                LockButton {
                    k: root.k; round: true; backdrop: backdrop
                    icon: "system-shutdown-symbolic"; caption: "Shut Down"
                    tip: "Turn the computer off"
                    onClicked: powerRow.asking = "poweroff"
                }
            }
            LockGlass {
                id: confirm
                anchors.centerIn: parent
                backdrop: backdrop
                radius: 18 * root.k
                width: confirmCol.implicitWidth + 40 * root.k
                height: confirmCol.implicitHeight + 28 * root.k
                opacity: powerRow.asking !== "" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Column {
                    id: confirmCol
                    anchors.centerIn: parent
                    spacing: 12 * root.k
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: powerRow.asking === "reboot" ? "Restart the computer now?" : "Shut down the computer now?"
                        color: "white"
                        font.pointSize: 0.75 * Math.round(14 * root.k)
                        font.weight: Font.DemiBold
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Apps that are open will be closed, unsaved work is lost."
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font.pointSize: 0.75 * Math.round(12 * root.k)
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10 * root.k
                        LockButton {
                            k: root.k; pill: true
                            text: "Cancel"
                            onClicked: powerRow.asking = ""
                        }
                        LockButton {
                            k: root.k; pill: true; accent: true
                            text: powerRow.asking === "reboot" ? "Restart" : "Shut Down"
                            onClicked: { const a = powerRow.asking; powerRow.asking = ""; Session.run(a); }
                        }
                    }
                }
            }
            Timer { interval: 15000; running: powerRow.asking !== ""; onTriggered: powerRow.asking = "" }
        }
    }
}
