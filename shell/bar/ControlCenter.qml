import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../widgets"
import "../services"
import ".."

// Control Center (macOS 26): the two-switch icon left of the clock opens a
// glass panel of modules: Wi-Fi, Bluetooth and Night Shift toggles, Focus
// (Do Not Disturb), Dark Mode, Display and Sound sliders and Now Playing.
// Each toggle's ">" opens that item's full menu (the menu bar indicator).
// `hearth-ipc call indicator-controlcenter toggle`.
Indicator {
    id: root
    ipcName: "controlcenter"
    implicitWidth: Theme.menuBarItemWidth
    tooltip: "Control Center: Wi-Fi, Bluetooth, Focus, Dark Mode, display brightness and sound"

    // SF Symbol "switch.2": two switches, knobs at opposite ends.
    Item {
        parent: root
        anchors.centerIn: parent
        width: 15
        height: 14
        Repeater {
            model: 2
            Item {
                required property int index
                y: index * 8
                width: 15
                height: 6
                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: "transparent"
                    border.color: Theme.fg
                    border.width: 1.3
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    x: parent.index === 0 ? parent.width - width : 0
                    color: Theme.fg
                }
            }
        }
    }

    // --- state ---
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi && d.connected) ?? null
    readonly property var wifiNet: wifiDev ? (wifiDev.networks.values.find(n => n.connected) ?? null) : null
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btConnected: bt ? bt.devices.values.filter(d => d.connected) : []
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    property bool dnd: false
    Process {
        id: dndProbe
        command: ["swaync-client", "-D"]
        stdout: StdioCollector { onStreamFinished: root.dnd = text.trim() === "true" }
    }
    Connections {
        target: root.popup
        function onOpenChanged() { if (root.popup.open) dndProbe.running = true; }
    }

    function more(name) { root.popup.close(); ShellState.openIndicator(name); }

    popupContent: ColumnLayout {
        id: cc
        readonly property real unit: Math.round(76 * Theme.pt)    // module grid cell
        readonly property real gapW: Math.round(10 * Theme.pt)
        implicitWidth: 2 * unit * 2 + gapW
        width: implicitWidth
        spacing: gapW

        RowLayout {
            spacing: cc.gapW
            // Connectivity: a tall module of round toggles.
            Module {
                Layout.preferredWidth: cc.unit * 2
                Layout.preferredHeight: cc.unit * 2 + cc.gapW
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Math.round(10 * Theme.pt)
                    spacing: 0
                    ToggleRow {
                        icon: Networking.wifiEnabled ? "network-wireless-symbolic" : "network-wireless-offline-symbolic"
                        title: "Wi-Fi"
                        detail: !Networking.wifiEnabled ? "Off" : root.wifiNet ? root.wifiNet.name : "Not Connected"
                        on: Networking.wifiEnabled
                        onToggle: Networking.wifiEnabled = !Networking.wifiEnabled
                        onMore: root.more("network")
                        tip: "Turn Wi-Fi on or off · › for networks"
                    }
                    ToggleRow {
                        icon: "network-bluetooth-symbolic"
                        title: "Bluetooth"
                        detail: !root.bt ? "Unavailable" : !root.bt.enabled ? "Off"
                              : root.btConnected.length ? root.btConnected.map(d => d.name).join(", ") : "On"
                        on: !!root.bt && root.bt.enabled
                        onToggle: if (root.bt) root.bt.enabled = !root.bt.enabled
                        onMore: root.more("bluetooth")
                        tip: "Turn Bluetooth on or off · › for devices"
                    }
                    ToggleRow {
                        icon: "redshift-status-on"
                        title: "Night Shift"
                        detail: Brightness.nightLight ? Brightness.temperature + " K" : "Off"
                        on: Brightness.nightLight
                        onToggle: Brightness.setNightLight(!Brightness.nightLight)
                        onMore: root.more("brightness")
                        tip: "Warmer colours in the evening · › for display settings"
                    }
                }
            }
            ColumnLayout {
                spacing: cc.gapW
                Module {
                    Layout.preferredWidth: cc.unit * 2
                    Layout.preferredHeight: cc.unit
                    ToggleRow {
                        anchors.fill: parent
                        anchors.margins: Math.round(10 * Theme.pt)
                        icon: "notifications-disabled-symbolic"
                        title: "Focus"
                        detail: root.dnd ? "Do Not Disturb" : "Off"
                        on: root.dnd
                        onToggle: { root.dnd = !root.dnd; Swaync.setDnd(root.dnd); }
                        showMore: false
                        tip: "Do Not Disturb: notifications stay quiet"
                    }
                }
                Module {
                    Layout.preferredWidth: cc.unit * 2
                    Layout.preferredHeight: cc.unit
                    ToggleRow {
                        anchors.fill: parent
                        anchors.margins: Math.round(10 * Theme.pt)
                        icon: "weather-clear-night-symbolic"
                        title: "Dark Mode"
                        detail: Settings.appearance.mode === "auto" ? "Automatic" : Theme.dark ? "On" : "Off"
                        on: Theme.dark
                        onToggle: Settings.set("appearance.mode", Theme.dark ? "light" : "dark")
                        showMore: false
                        tip: "Switch between the dark and light look"
                    }
                }
            }
        }

        SliderModule {
            visible: Brightness.available
            title: "Display"
            icon: "brightness-high-symbolic"
            value: Brightness.percent / 100
            onMoved: v => Brightness.setAll(Math.round(v * 100), false)
        }
        SliderModule {
            visible: root.sink !== null
            title: "Sound"
            icon: root.sink && root.sink.audio && (root.sink.audio.muted || root.sink.audio.volume < 0.01) ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
            onMoved: v => { if (root.sink && root.sink.audio) { root.sink.audio.muted = false; root.sink.audio.volume = v; } }
            onMore: root.more("volume")
        }

        // Now Playing.
        Module {
            visible: root.player !== null
            Layout.fillWidth: true
            Layout.preferredHeight: cc.unit
            RowLayout {
                anchors.fill: parent
                anchors.margins: Math.round(10 * Theme.pt)
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: parent.height
                    Layout.preferredHeight: parent.height
                    radius: 8
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: root.player ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 128
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: root.player ? (root.player.trackTitle || root.player.identity) : ""
                        font.pointSize: Theme.menuFontSize
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.player ? (root.player.trackArtist || "") : ""
                        color: Theme.fgSecondary
                        font.pointSize: Theme.menuSmallFontSize
                    }
                }
                RoundButton {
                    icon: root.player && root.player.isPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                    onClicked: if (root.player) root.player.togglePlaying()
                    tip: "Play or pause"
                }
                RoundButton {
                    icon: "media-skip-forward-symbolic"
                    onClicked: if (root.player && root.player.canGoNext) root.player.next()
                    tip: "Next track"
                }
            }
        }
    }

    // A Control Center module: a rounded tile on the glass.
    component Module: Rectangle {
        radius: Math.round(18 * Theme.pt)
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.55)
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
    }

    // A round toggle with its name and state; "›" opens the full menu.
    component ToggleRow: Item {
        id: tr
        property string icon
        property string title
        property string detail
        property string tip
        property bool on: false
        property bool showMore: true
        signal toggle()
        signal more()
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitHeight: Math.round(40 * Theme.pt)
        MouseArea {
            id: circle
            width: Math.round(30 * Theme.pt)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            hoverEnabled: true
            onClicked: tr.toggle()
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: tr.on ? Theme.accent : Theme.dark ? Qt.rgba(1, 1, 1, circle.containsMouse ? 0.22 : 0.14) : Qt.rgba(0, 0, 0, circle.containsMouse ? 0.12 : 0.07)
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            Icon {
                anchors.centerIn: parent
                implicitSize: 16
                name: tr.icon
            }
            Tooltip { anchorItem: circle; text: tr.tip; hovered: circle.containsMouse }
        }
        Column {
            anchors.left: circle.right
            anchors.leftMargin: 8
            anchors.right: moreBtn.left
            anchors.verticalCenter: parent.verticalCenter
            Label { width: parent.width; text: tr.title; font.pointSize: Theme.menuSmallFontSize; font.weight: Font.DemiBold }
            Label { width: parent.width; text: tr.detail; color: Theme.fgSecondary; font.pointSize: Theme.macPt(10) }
        }
        MouseArea {
            id: moreBtn
            visible: tr.showMore
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: tr.showMore ? 18 : 0
            height: 24
            hoverEnabled: true
            onClicked: tr.more()
            Label {
                anchors.centerIn: parent
                text: "›"
                color: moreBtn.containsMouse ? Theme.fg : Theme.fgSecondary
                font.pointSize: Theme.menuFontSize + 2
            }
        }
    }

    // A full-width slider module (Display, Sound), macOS-style thick track.
    component SliderModule: Module {
        id: sm
        property string title
        property string icon
        property real value: 0
        signal moved(real v)
        signal more()
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(62 * Theme.pt)
        Label {
            x: Math.round(12 * Theme.pt)
            y: Math.round(8 * Theme.pt)
            text: sm.title
            font.pointSize: Theme.menuSmallFontSize
            font.weight: Font.DemiBold
        }
        Item {
            id: track
            x: Math.round(12 * Theme.pt)
            width: parent.width - 2 * x
            height: Math.round(22 * Theme.pt)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(10 * Theme.pt)
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
            }
            Rectangle {
                width: Math.max(height, parent.width * Math.max(0, Math.min(1, sm.value)))
                height: parent.height
                radius: height / 2
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.92) : "#ffffff"
                border.color: Theme.dark ? "transparent" : Qt.rgba(0, 0, 0, 0.06)
            }
            Icon {
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 14
                name: sm.icon
                // Dark glyph on the white fill, like macOS.
                layer.enabled: true
                layer.effect: MultiEffect { brightness: -1; saturation: -1 }
                opacity: 0.55
            }
            MouseArea {
                anchors.fill: parent
                function at(x) { return Math.max(0, Math.min(1, x / width)); }
                onPressed: mouse => sm.moved(at(mouse.x))
                onPositionChanged: mouse => { if (pressed) sm.moved(at(mouse.x)); }
                onWheel: w => sm.moved(Math.max(0, Math.min(1, sm.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }
    }

    component RoundButton: MouseArea {
        id: rb
        property string icon
        property string tip
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        hoverEnabled: true
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: rb.containsMouse ? Theme.hover : "transparent"
        }
        Icon { anchors.centerIn: parent; implicitSize: 18; name: rb.icon }
        Tooltip { anchorItem: rb; text: rb.tip; hovered: rb.containsMouse }
    }
}
