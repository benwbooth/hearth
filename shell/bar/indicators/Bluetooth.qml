import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../../widgets"
import "../.."

// Bluetooth: adapter power, paired devices (connect/disconnect, battery) and
// a scan mode for pairing new ones. PIN/passkey prompts come from
// services/BtAgent + popups/BtPairDialog. Hidden without an adapter.
Indicator {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var paired: devices.filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var connected: paired.filter(d => d.connected)
    readonly property var discovered: devices.filter(d => !d.paired && !d.bonded)
        .sort((a, b) => (b.pairing - a.pairing) || a.name.localeCompare(b.name))

    function stateText(d) {
        if (d.pairing) return "Pairing…";
        switch (d.state) {
        case BluetoothDeviceState.Connecting: return "Connecting…";
        case BluetoothDeviceState.Disconnecting: return "Disconnecting…";
        case BluetoothDeviceState.Connected: return "Connected";
        default: return "";
        }
    }
    function batteryText(d) {
        return d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "";
    }

    shown: adapter !== null
    icon: !on ? "network-bluetooth-inactive-symbolic"
        : connected.length > 0 ? "network-bluetooth-activated" : "network-bluetooth"
    iconFallback: "preferences-system-bluetooth"
    tooltip: !on ? "Bluetooth: off"
           : connected.length === 0 ? "Bluetooth: no devices connected"
           : connected.length === 1 ? "Bluetooth: " + connected[0].name
           : "Bluetooth: " + connected.length + " devices connected"
    tooltipSub: connected.map(d => d.name + (d.batteryAvailable ? "  " + batteryText(d) : "")).join("\n")

    popupContent: ColumnLayout {
        id: pop
        spacing: 2
        property bool scanning: false

        // Discovery only while scan mode is on and the popup is open.
        Binding {
            target: root.adapter
            property: "discovering"
            value: true
            when: pop.scanning && root.on
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 360
            Layout.bottomMargin: 4
            Label {
                Layout.fillWidth: true
                text: "Bluetooth" + (root.adapter?.name ? "  (" + root.adapter.name + ")" : "")
                font.weight: Font.DemiBold
                color: Theme.fgDim
            }
            Switch {
                checked: root.on
                enabled: root.adapter?.state !== BluetoothAdapterState.Blocked
                onToggled: root.adapter.enabled = !root.adapter.enabled
            }
        }
        Label {
            Layout.fillWidth: true
            visible: root.adapter?.state === BluetoothAdapterState.Blocked
            text: "Blocked by rfkill"
            color: Theme.warn
        }

        Label {
            Layout.fillWidth: true
            visible: root.on && root.paired.length === 0
            text: "No paired devices"
            color: Theme.fgDim
            leftPadding: 8
        }
        Repeater {
            model: root.on ? root.paired : []
            delegate: DeviceRow {}
        }

        // Scan mode.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: root.on
            Label {
                Layout.fillWidth: true
                text: pop.scanning ? "Available devices" : ""
                font.weight: Font.DemiBold
                color: Theme.fgDim
            }
            BarButton {
                implicitHeight: 28
                iconSize: 16
                icon: pop.scanning ? "process-stop" : "view-refresh"
                text: pop.scanning ? "Stop scanning" : "Scan"
                onClicked: pop.scanning = !pop.scanning
            }
        }
        Label {
            Layout.fillWidth: true
            visible: pop.scanning && root.on && root.discovered.length === 0
            text: "Searching…"
            color: Theme.fgDim
            leftPadding: 8
        }
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(discCol.implicitHeight, 300)
            visible: pop.scanning && root.on && root.discovered.length > 0
            contentHeight: discCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: discCol
                width: parent.width
                Repeater {
                    model: pop.scanning && root.on ? root.discovered : []
                    delegate: DeviceRow { width: discCol.width }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 4
            implicitHeight: 1
            color: Theme.border
        }
        MenuItem {
            Layout.fillWidth: true
            icon: "preferences-system-bluetooth"
            text: "Bluetooth settings…"
            onTriggered: {
                Quickshell.execDetached(["tessera", "--new-window", "--run", "bluetuith"]);
                root.popup.close();
            }
        }
    }

    // A device: icon, name, status/battery, and Connect/Disconnect or Pair.
    component DeviceRow: Item {
        id: dr
        required property var modelData
        readonly property var dev: modelData
        readonly property bool isPaired: dev.paired || dev.bonded
        Layout.fillWidth: true
        Layout.preferredWidth: 360
        implicitWidth: 360
        implicitHeight: 40

        // Trust and connect a device as soon as pairing succeeds.
        Connections {
            target: dr.dev
            function onPairedChanged() {
                if (dr.dev.paired) { dr.dev.trusted = true; dr.dev.connect(); }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: hover.hovered ? Theme.hover : "transparent"
        }
        HoverHandler { id: hover }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 10
            Icon {
                implicitSize: 22
                name: dr.dev.icon
                fallback: "preferences-system-bluetooth"
                opacity: dr.dev.connected || !dr.isPaired ? 1 : 0.6
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: dr.dev.name || dr.dev.address
                    font.weight: dr.dev.connected ? Font.DemiBold : Font.Normal
                    color: dr.dev.connected || !dr.isPaired ? Theme.fg : Theme.fgDim
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: [root.stateText(dr.dev),
                           dr.dev.batteryAvailable ? "Battery " + root.batteryText(dr.dev) : ""]
                          .filter(s => s).join(" · ")
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
            }
            BarButton {
                implicitHeight: 28
                visible: dr.isPaired
                text: dr.dev.connected ? "Disconnect" : "Connect"
                enabled: dr.dev.state === BluetoothDeviceState.Connected
                         || dr.dev.state === BluetoothDeviceState.Disconnected
                opacity: enabled ? 1 : 0.5
                onClicked: dr.dev.connected ? dr.dev.disconnect() : dr.dev.connect()
            }
            BarButton {
                implicitHeight: 28
                visible: !dr.isPaired
                text: dr.dev.pairing ? "Cancel" : "Pair"
                onClicked: dr.dev.pairing ? dr.dev.cancelPair() : dr.dev.pair()
            }
        }
    }

    component Switch: MouseArea {
        id: sw
        property bool checked: false
        signal toggled()
        implicitWidth: 36
        implicitHeight: 20
        opacity: enabled ? 1 : 0.4
        onClicked: sw.toggled()
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: sw.checked ? Theme.accent : Theme.border
            Rectangle {
                x: sw.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                radius: 7
                color: Theme.fg
                Behavior on x { NumberAnimation { duration: 120 } }
            }
        }
    }
}
