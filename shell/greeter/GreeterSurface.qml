import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import "../lock"
import "../widgets"
import "../services"
import ".."

// One screen of the login screen, macOS style and built like the lock
// screen (lock/LockSurface.qml): the wallpaper, the date and a big thin
// clock; at the bottom your picture and name with the glass password field
// (several people: a row of pictures to pick from first), the session
// picker, and Sleep / Restart / Shut Down; keyboard layout and
// accessibility (screen zoom) at the top right. Screens other than the
// main one show the wallpaper and the clock.
Item {
    id: root
    required property var screen
    property bool isMain: true
    readonly property real k: Math.max(0.75, Math.min(1.6, height / 1400))
    readonly property bool picking: Greeter.loaded && Greeter.user === null && Greeter.users.length > 1
    transform: Translate { x: 0.001; y: 0.001 }
    onPickingChanged: if (picking && isMain) userRow.forceActiveFocus()

    // ------------------------------------------------------- wallpaper

    readonly property bool settled: field.text.length > 0 || Greeter.checking
    property real speed: settled || Greeter.launching ? 0 : 1
    Behavior on speed { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } }
    property real blurAmt: settled ? 0.55 : 0
    Behavior on blurAmt { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    property real zoom: settled ? 1.035 : 1
    Behavior on zoom { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

    Item {
        id: backdrop
        anchors.fill: parent
        clip: true
        GreeterWallpaper {
            id: wall
            anchors.fill: parent
            scale: root.zoom
            fallback: Quickshell.env("HEARTH_GREETER_WALLPAPER") || ""
            dir: Quickshell.env("HEARTH_WALLPAPER_SYSTEM_DIR") || "/var/lib/hearth/wallpaper"
            speed: root.speed
            px: Qt.size(Math.round(root.width * (root.screen ? root.screen.devicePixelRatio || 1 : 1)),
                        Math.round(root.height * (root.screen ? root.screen.devicePixelRatio || 1 : 1)))
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
        autoPaddingEnabled: false
        blurEnabled: true
        blur: root.blurAmt
        blurMax: 64
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.22) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.65; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.32) }
        }
    }
    // Black until the wallpaper is ready, and again while the session starts.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: Greeter.launching ? 1 : (wall.ready || readyFallback.done ? 0 : 1)
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        z: 5
    }
    Timer { id: readyFallback; property bool done: false; interval: 800; running: true; onTriggered: done = true }

    MouseArea {
        anchors.fill: parent
        onPressed: { sessionMenu.open = false; a11yMenu.open = false; if (root.isMain) field.forceActiveFocus(); }
    }

    // ---------------------------------------------------------------- UI

    Item {
        id: ui
        anchors.fill: parent
        opacity: 0
        Component.onCompleted: appear.start()
        NumberAnimation { id: appear; target: ui; property: "opacity"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
        Connections {
            target: Greeter
            function onLaunchAnimationRequested() { vanish.start(); }
            function onTestShotRequested(path) { if (root.isMain) root.grabToImage(r => r.saveToFile(path)); }
        }
        ParallelAnimation {
            id: vanish
            NumberAnimation { target: ui; property: "opacity"; to: 0; duration: 300; easing.type: Easing.InCubic }
            NumberAnimation { target: ui; property: "scale"; to: 1.06; duration: 380; easing.type: Easing.InCubic }
        }

        // ---- date and clock
        Column {
            id: clockCol
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height * 0.075
            spacing: -4 * root.k
            SystemClock { id: clock; precision: SystemClock.Minutes }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(clock.date, "dddd, MMMM d")
                color: Qt.rgba(1, 1, 1, 0.92)
                font.family: Theme.displayFontFamily
                font.pointSize: 0.75 * Math.round(26 * root.k)
                font.weight: Font.DemiBold
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.12)
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Settings.menubar.clock24h ? Qt.formatTime(clock.date, "HH:mm")
                      : ((clock.date.getHours() % 12) || 12) + ":" + Qt.formatTime(clock.date, "mm")
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

        // ---- top right: keyboard layout, accessibility (main screen)
        Row {
            id: status
            visible: root.isMain
            anchors { top: parent.top; right: parent.right; topMargin: 14 * root.k; rightMargin: 22 * root.k }
            spacing: 12 * root.k
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
                    Compositor.arborAction("SwitchLayout", { layout: "Next" });
                    Qt.callLater(Keyboard.refreshLive);
                }
            }
            LockButton {
                id: a11yButton
                k: root.k
                flat: true
                icon: "preferences-desktop-accessibility-symbolic"
                tip: "Accessibility: make the screen bigger"
                onClicked: { sessionMenu.open = false; a11yMenu.open = !a11yMenu.open; }
            }
        }
        GreeterMenu {
            id: a11yMenu
            backdrop: backdrop
            k: root.k
            z: 10
            anchors.top: status.bottom
            anchors.topMargin: 8 * root.k
            anchors.right: status.right
            title: "Accessibility"
            items: [
                { text: "Zoom In", detail: "Also Super+Alt+=  (move the pointer to look around)" },
                { text: "Zoom Out", detail: "Super+Alt+−" },
                { text: "Actual Size", detail: "Super+Alt+0" }
            ]
            onPicked: i => Compositor.arborAction(["ZoomIn", "ZoomOut", "ZoomReset"][i], {})
        }

        // ---- several people: pick one (main screen)
        Row {
            id: userRow
            visible: root.isMain && opacity > 0.01
            opacity: root.picking ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: powerRow.top
            anchors.bottomMargin: 70 * root.k
            spacing: 36 * root.k
            focus: root.picking
            property int hover: 0
            Keys.onLeftPressed: hover = Math.max(0, hover - 1)
            Keys.onRightPressed: hover = Math.min(Greeter.users.length - 1, hover + 1)
            Keys.onReturnPressed: Greeter.selectUser(hover)
            Keys.onEnterPressed: Greeter.selectUser(hover)
            Repeater {
                model: Greeter.users
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    width: Math.max(tileCol.implicitWidth, Math.round(110 * root.k))
                    height: tileCol.implicitHeight
                    scale: tileMa.pressed ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Column {
                        id: tileCol
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10 * root.k
                        Avatar {
                            anchors.horizontalCenter: parent.horizontalCenter
                            user: tile.modelData
                            size: Math.round(96 * root.k)
                            ring: tileMa.containsMouse || userRow.hover === tile.index
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Greeter.displayName(tile.modelData)
                            color: "white"
                            font.pointSize: 0.75 * Math.round(15 * root.k)
                            font.weight: Font.DemiBold
                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.2)
                        }
                    }
                    MouseArea {
                        id: tileMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: userRow.hover = tile.index
                        onClicked: Greeter.selectUser(tile.index)
                    }
                }
            }
        }

        // ---- the chosen person: picture, name, password (main screen)
        Column {
            id: userCol
            visible: root.isMain && opacity > 0.01
            opacity: Greeter.user !== null ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: powerRow.top
            anchors.bottomMargin: 34 * root.k
            spacing: 10 * root.k

            Avatar {
                anchors.horizontalCenter: parent.horizontalCenter
                user: Greeter.user
                size: Math.round(76 * root.k)
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Greeter.displayName(Greeter.user)
                color: "white"
                font.pointSize: 0.75 * Math.round(17 * root.k)
                font.weight: Font.DemiBold
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.15)
            }

            LockGlass {
                id: fieldGlass
                anchors.horizontalCenter: parent.horizontalCenter
                backdrop: backdrop
                width: Math.round(260 * root.k)
                height: Math.round(36 * root.k)
                tint: Qt.rgba(1, 1, 1, 0.16)
                property real shake: 0
                transform: Translate { x: fieldGlass.shake }

                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: fieldGlass; property: "shake"; to: -14; duration: 50; easing.type: Easing.OutQuad }
                    NumberAnimation { target: fieldGlass; property: "shake"; to: 12; duration: 70; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: fieldGlass; property: "shake"; to: -9; duration: 70; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: fieldGlass; property: "shake"; to: 6; duration: 60; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: fieldGlass; property: "shake"; to: -3; duration: 50; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: fieldGlass; property: "shake"; to: 0; duration: 50; easing.type: Easing.OutQuad }
                }
                Connections {
                    target: Greeter
                    function onWrongPassword() { field.text = ""; shakeAnim.restart(); field.forceActiveFocus(); }
                    function onUserIndexChanged() { field.text = ""; if (Greeter.user) field.forceActiveFocus(); }
                }

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 16 * root.k
                    anchors.verticalCenter: parent.verticalCenter
                    visible: field.text.length === 0
                    text: "Enter Password"
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pointSize: 0.75 * Math.round(14 * root.k)
                }
                TextInput {
                    id: field
                    anchors.left: parent.left
                    anchors.leftMargin: 16 * root.k
                    anchors.right: trail.left
                    anchors.rightMargin: 6 * root.k
                    anchors.verticalCenter: parent.verticalCenter
                    focus: root.isMain && Greeter.user !== null
                    enabled: !Greeter.checking && !Greeter.launching
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    passwordMaskDelay: 0
                    renderType: Text.NativeRendering
                    color: "white"
                    opacity: Greeter.checking ? 0.5 : 1
                    selectionColor: Theme.accent
                    font.family: Theme.fontFamily
                    font.pointSize: 0.75 * Math.round(12 * root.k)
                    font.letterSpacing: 2 * root.k
                    clip: true
                    onAccepted: Greeter.submit(text)
                    onTextChanged: if (text.length > 0 && !Greeter.checking) Greeter.message = ""
                    Keys.onEscapePressed: {
                        if (text.length > 0) text = "";
                        else Greeter.backToUsers();
                    }
                }
                Row {
                    id: trail
                    anchors.right: parent.right
                    anchors.rightMargin: 5 * root.k
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6 * root.k
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Greeter.capsLock
                        text: "⇪"
                        color: Qt.rgba(1, 1, 1, 0.8)
                        font.pointSize: 0.75 * Math.round(16 * root.k)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(26 * root.k); height: width; radius: width / 2
                        color: Qt.rgba(1, 1, 1, field.text.length > 0 ? 0.28 : 0.10)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Label {
                            anchors.centerIn: parent
                            visible: !Greeter.checking
                            text: "→"
                            color: Qt.rgba(1, 1, 1, field.text.length > 0 ? 1 : 0.45)
                            font.pointSize: 0.75 * Math.round(15 * root.k)
                            font.weight: Font.DemiBold
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            visible: Greeter.checking
                            width: parent.width * 0.55; height: width; radius: width / 2
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.9)
                            border.width: 2
                            Rectangle {
                                width: 5 * root.k; height: width; radius: width / 2
                                color: Theme.accent
                                x: parent.width / 2 - width / 2; y: -width / 2 + 1
                            }
                            RotationAnimation on rotation { running: Greeter.checking; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Greeter.submit(field.text)
                        }
                    }
                }
            }

            // Message (wrong password, Caps Lock) under the field, in a
            // fixed-height slot so nothing above it moves.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: fieldGlass.width     // never 0: Column skips empty items
                height: Math.round(22 * root.k)
                Label {
                    id: msg
                    anchors.centerIn: parent
                    text: Greeter.message !== "" ? Greeter.message : Greeter.capsLock ? "Caps Lock is on" : ""
                    color: Greeter.message !== "" ? "#ffd1d1" : Qt.rgba(1, 1, 1, 0.75)
                    font.pointSize: 0.75 * Math.round(12.5 * root.k)
                    font.weight: Font.Medium
                    style: Text.Raised
                    styleColor: Qt.rgba(0, 0, 0, 0.3)
                    width: Math.min(implicitWidth, root.width * 0.6)
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // Session picker and "other users".
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10 * root.k
                LockButton {
                    id: sessionButton
                    visible: Greeter.sessions.length > 0
                    k: root.k
                    flat: true
                    icon: "preferences-system-windows-symbolic"
                    text: (Greeter.session ? Greeter.session.name : "") + (Greeter.sessions.length > 1 ? "  ▾" : "")
                    tip: Greeter.sessions.length > 1 ? "Which desktop to start. Click to choose another." : "The desktop that starts when you log in"
                    onClicked: { a11yMenu.open = false; if (Greeter.sessions.length > 1) sessionMenu.open = !sessionMenu.open; }
                }
                LockButton {
                    visible: Greeter.users.length > 1
                    k: root.k
                    flat: true
                    icon: "go-previous-symbolic"
                    text: "Other Users"
                    tip: "Log in as someone else (Esc)"
                    onClicked: Greeter.backToUsers()
                }
            }
        }
        GreeterMenu {
            id: sessionMenu
            backdrop: backdrop
            k: root.k
            z: 10
            title: "Desktop session"
            readonly property point at: { void open; return sessionButton.mapToItem(ui, sessionButton.width / 2, 0); }
            x: at.x - width / 2
            y: at.y - height - 8 * root.k
            items: Greeter.sessions.map(s => ({ text: s.name, detail: s.comment, checked: s.id === Greeter.sessionId }))
            onPicked: i => Greeter.sessionId = Greeter.sessions[i].id
        }

        // ---- Sleep / Restart / Shut Down (main screen)
        Item {
            id: powerRow
            visible: root.isMain
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 30 * root.k
            width: Math.max(buttons.implicitWidth, confirm.width)
            height: Math.max(buttons.implicitHeight, confirm.height)
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
                    onClicked: Greeter.power("suspend")
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
                            onClicked: { const a = powerRow.asking; powerRow.asking = ""; Greeter.power(a); }
                        }
                    }
                }
            }
            Timer { interval: 15000; running: powerRow.asking !== ""; onTriggered: powerRow.asking = "" }
        }

        // First run / nothing to show.
        Label {
            visible: root.isMain && Greeter.loaded && Greeter.users.length === 0
            anchors.centerIn: parent
            text: "No one can log in here yet. Add a user in the system configuration."
            color: "white"
            font.pointSize: 0.75 * Math.round(15 * root.k)
        }
    }
}
