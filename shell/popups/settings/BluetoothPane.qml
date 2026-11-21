import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../../widgets"
import "../../services"
import "../.."

// Settings > Bluetooth, like macOS's: Bluetooth on/off, this computer's
// name and visibility, your devices (connect, disconnect, forget) and
// nearby devices to pair. All through BlueZ (Quickshell.Bluetooth); PIN and
// passkey prompts come from services/BtAgent + popups/BtPairDialog.
ColumnLayout {
    id: pane
    spacing: 14

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var mine: devices.filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    // Nearby: only ones with a real name (BlueZ lists bare addresses too).
    readonly property var nearby: devices.filter(d => !d.paired && !d.bonded && d.name && d.name !== d.address.replace(/:/g, "-"))
        .sort((a, b) => (b.pairing - a.pairing) || a.name.localeCompare(b.name))
    property string confirmForget: ""

    // Looking for nearby devices while this page is open, like macOS.
    readonly property bool scan: on && pane.visible
    onScanChanged: if (adapter) adapter.discovering = scan
    Component.onDestruction: if (adapter && adapter.discovering) adapter.discovering = false

    function stateText(d) {
        if (d.pairing) return "Pairing…";
        switch (d.state) {
        case BluetoothDeviceState.Connecting: return "Connecting…";
        case BluetoothDeviceState.Disconnecting: return "Disconnecting…";
        case BluetoothDeviceState.Connected: return "Connected";
        default: return "Not connected";
        }
    }
    function deviceIcon(d) { return d.icon || "preferences-system-bluetooth"; }

    Label {
        Layout.fillWidth: true
        visible: !pane.adapter
        text: "No Bluetooth adapter found. If this computer has Bluetooth, check that it isn't switched off in the firmware settings or with a key on the keyboard."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    SettingsGroup {
        visible: !!pane.adapter
        SettingsRow {
            label: "Bluetooth"
            note: pane.on ? "On. This computer shows up to nearby devices as “" + (pane.adapter ? pane.adapter.name : "") + "” while this page is open." : "Off: no Bluetooth headphones, keyboards or mice."
            Toggle {
                checked: pane.on
                onToggled: c => { if (pane.adapter) pane.adapter.enabled = c; }
            }
        }
    }

    Label { visible: pane.on; text: "My devices"; font.weight: Font.DemiBold }
    SettingsGroup {
        visible: pane.on
        Label {
            visible: pane.mine.length === 0
            height: 40
            text: "No devices yet. Put your headphones, keyboard or mouse into pairing mode and pick it under Nearby devices."
            color: Theme.fgDim
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            width: parent ? parent.width : 0
        }
        Repeater {
            model: pane.mine
            Column {
                id: md
                required property var modelData
                required property int index
                readonly property var dev: modelData
                width: parent ? parent.width : 0
                SettingsDivider { visible: md.index > 0 }
                SettingsRow {
                    label: md.dev.name
                    note: [pane.stateText(md.dev), md.dev.batteryAvailable ? "Battery " + Math.round(md.dev.battery * 100) + "%" : ""].filter(s => s).join(" · ")
                    RowLayout {
                        spacing: 6
                        Icon { implicitSize: 22; name: pane.deviceIcon(md.dev); fallback: "preferences-system-bluetooth" }
                        PushButton {
                            text: md.dev.connected ? "Disconnect" : "Connect"
                            primary: !md.dev.connected
                            enabled: md.dev.state === BluetoothDeviceState.Connected || md.dev.state === BluetoothDeviceState.Disconnected
                            tooltip: md.dev.connected ? "Stop using it with this computer (it stays paired)" : "Use it with this computer now"
                            onClicked: md.dev.connected ? md.dev.disconnect() : md.dev.connect()
                        }
                        PushButton {
                            text: pane.confirmForget === md.dev.address ? "Really forget?" : "Forget…"
                            destructive: true
                            tooltip: "Remove the pairing. To use it again you'll pair it again. Asks first."
                            onClicked: {
                                if (pane.confirmForget === md.dev.address) { md.dev.forget(); pane.confirmForget = ""; }
                                else pane.confirmForget = md.dev.address;
                            }
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        visible: pane.on
        Label { text: "Nearby devices"; font.weight: Font.DemiBold }
        Label { text: pane.adapter && pane.adapter.discovering ? "searching…" : ""; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize }
    }
    SettingsGroup {
        visible: pane.on
        Label {
            visible: pane.nearby.length === 0
            height: 40
            text: "Looking for devices. Put the one you want into pairing mode (often: hold its power or Bluetooth button until a light blinks)."
            color: Theme.fgDim
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            width: parent ? parent.width : 0
        }
        Repeater {
            model: pane.nearby
            Column {
                id: nd
                required property var modelData
                required property int index
                readonly property var dev: modelData
                width: parent ? parent.width : 0
                // Trust and connect as soon as pairing succeeds.
                Connections {
                    target: nd.dev
                    function onPairedChanged() { if (nd.dev.paired) { nd.dev.trusted = true; nd.dev.connect(); } }
                }
                SettingsDivider { visible: nd.index > 0 }
                SettingsRow {
                    label: nd.dev.name
                    note: nd.dev.pairing ? "Pairing… (follow any prompt on the device)" : ""
                    RowLayout {
                        spacing: 6
                        Icon { implicitSize: 22; name: pane.deviceIcon(nd.dev); fallback: "preferences-system-bluetooth" }
                        PushButton {
                            text: nd.dev.pairing ? "Cancel" : "Connect"
                            primary: !nd.dev.pairing
                            tooltip: nd.dev.pairing ? "Stop pairing" : "Pair it with this computer and connect"
                            onClicked: nd.dev.pairing ? nd.dev.cancelPair() : nd.dev.pair()
                        }
                    }
                }
            }
        }
    }
}
