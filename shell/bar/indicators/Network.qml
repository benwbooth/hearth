import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../../widgets"
import "../.."

// Network: wired link, Wi-Fi (on/off, networks, connect with a password
// prompt) and VPNs. Devices come from Quickshell.Networking; VPN profiles
// aren't in that module, so they're listed and toggled with nmcli.
Indicator {
    id: root

    readonly property var devices: Networking.devices.values.filter(d => d.nmManaged !== false)
    readonly property var wired: devices.filter(d => d.type === DeviceType.Wired)
    readonly property var wifis: devices.filter(d => d.type === DeviceType.Wifi)
    readonly property var wiredUp: wired.find(d => d.connected) ?? null
    readonly property var wifiUp: wifis.find(d => d.connected) ?? null
    readonly property var wifiNet: wifiUp ? (wifiUp.networks.values.find(n => n.connected) ?? null) : null
    readonly property bool limited: Networking.connectivity === NetworkConnectivity.Limited
                                    || Networking.connectivity === NetworkConnectivity.Portal

    // [{ name, type, active }] from nmcli.
    property var vpns: []
    readonly property var activeVpns: vpns.filter(v => v.active)
    readonly property bool vpnUp: activeVpns.length > 0

    function strengthStep(s) {
        // signalStrength is 0..1.
        const p = Math.round(Math.max(0, Math.min(1, s)) * 5) * 20;
        return p;
    }
    function wifiIcon(s, locked) {
        return "network-wireless-" + strengthStep(s) + (locked ? "-locked" : "");
    }
    function speedText(mbps) {
        if (!mbps) return "";
        return mbps >= 1000 ? (mbps / 1000) + " Gb/s" : mbps + " Mb/s";
    }
    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }
    function needsPsk(n) {
        return n.security === WifiSecurityType.Wpa2Psk || n.security === WifiSecurityType.WpaPsk
            || n.security === WifiSecurityType.Sae || n.security === WifiSecurityType.StaticWep;
    }

    shown: Networking.backend !== NetworkBackendType.None
    icon: {
        if (wiredUp) return vpnUp ? "network-wired-activated-locked"
                         : limited ? "network-wired-activated-limited" : "network-wired-activated";
        if (wifiUp && wifiNet) return wifiIcon(wifiNet.signalStrength, false).replace(/$/, vpnUp ? "-locked" : limited ? "-limited" : "");
        if (wifiUp) return vpnUp ? "network-wireless-100-locked" : "network-wireless-100";
        return "network-offline";
    }
    iconFallback: "network-wired"
    tooltip: wiredUp ? "Ethernet: " + wiredUp.name
           : wifiNet ? "Wi-Fi: " + wifiNet.name
           : "Disconnected"
    tooltipSub: {
        const lines = [];
        if (wiredUp && wiredUp.linkSpeed) lines.push(speedText(wiredUp.linkSpeed));
        if (wifiNet) lines.push("Signal " + Math.round(wifiNet.signalStrength * 100) + "%");
        if (limited) lines.push("Limited connectivity");
        for (const v of activeVpns) lines.push("VPN: " + v.name);
        return lines.join("\n");
    }

    // --- VPNs via nmcli ---------------------------------------------------
    function splitTerse(line) {
        // nmcli -t escapes ':' and '\' inside fields with a backslash.
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }
    function refreshVpns() { if (!vpnList.running) vpnList.running = true; }
    function toggleVpn(v) {
        vpnToggle.command = ["nmcli", "connection", v.active ? "down" : "up", "id", v.name];
        vpnToggle.running = true;
    }

    Process {
        id: vpnList
        command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"]
        running: true
        property var acc: []
        stdout: SplitParser {
            onRead: line => {
                const f = root.splitTerse(line);
                if (f.length >= 3 && (f[1] === "vpn" || f[1] === "wireguard"))
                    vpnList.acc.push({ name: f[0], type: f[1], active: f[2] === "yes" });
            }
        }
        onStarted: acc = []
        onExited: root.vpns = acc
    }
    Process {
        id: vpnToggle
        property string error: ""
        stderr: StdioCollector { onStreamFinished: vpnToggle.error = text.trim() }
        onStarted: error = ""
        onExited: root.refreshVpns()
    }
    // Any NetworkManager change refreshes the VPN list (debounced).
    Process {
        id: monitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: _ => vpnDebounce.restart() }
        onExited: monitorRestart.start()
    }
    Timer { id: monitorRestart; interval: 10000; onTriggered: monitor.running = true }
    Timer { id: vpnDebounce; interval: 400; onTriggered: root.refreshVpns() }

    // --- popup ------------------------------------------------------------
    popupContent: ColumnLayout {
        id: pop
        spacing: 2
        // The network whose password prompt is open.
        property var pskFor: null
        property string failure: ""

        Component.onCompleted: root.refreshVpns()

        // Wired.
        Repeater {
            model: root.wired
            delegate: RowLayout {
                id: wrow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 360
                Layout.bottomMargin: 6
                spacing: 10
                Icon {
                    implicitSize: 22
                    name: wrow.modelData.connected ? "network-wired-activated"
                        : wrow.modelData.hasLink ? "network-wired" : "network-wired-disconnected"
                    fallback: "network-wired"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: "Ethernet  (" + wrow.modelData.name + ")"
                    }
                    Label {
                        Layout.fillWidth: true
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                        text: {
                            const d = wrow.modelData;
                            if (!d.hasLink) return "Cable unplugged";
                            const st = d.connected ? "Connected" : ConnectionState.toString(d.state);
                            return [st, root.speedText(d.linkSpeed), d.address].filter(s => s).join(" · ");
                        }
                    }
                }
            }
        }

        // Wi-Fi.
        Repeater {
            model: root.wifis
            delegate: ColumnLayout {
                id: wcol
                required property var modelData
                readonly property var nets: modelData.networks.values
                    .filter(n => n.name)
                    .sort((a, b) => (b.connected - a.connected) || (b.known - a.known)
                                    || (b.signalStrength - a.signalStrength))
                Layout.fillWidth: true
                Layout.preferredWidth: 360
                spacing: 2

                // Scan while the popup is open.
                Binding {
                    target: wcol.modelData
                    property: "scannerEnabled"
                    value: Networking.wifiEnabled
                    when: Networking.wifiEnabled
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Label {
                        Layout.fillWidth: true
                        text: "Wi-Fi" + (root.wifis.length > 1 ? "  (" + wcol.modelData.name + ")" : "")
                        font.weight: Font.DemiBold
                        color: Theme.fgDim
                    }
                    Switch {
                        checked: Networking.wifiEnabled
                        enabled: Networking.wifiHardwareEnabled
                        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: !Networking.wifiHardwareEnabled
                    text: "Disabled by hardware switch"
                    color: Theme.fgDim
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(netCol.implicitHeight, 360)
                    visible: Networking.wifiEnabled
                    contentHeight: netCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: netCol
                        width: parent.width
                        Repeater {
                            model: wcol.nets
                            delegate: WifiRow { width: netCol.width }
                        }
                        Label {
                            visible: wcol.nets.length === 0
                            text: "Scanning…"
                            color: Theme.fgDim
                            leftPadding: 8
                            height: 28
                        }
                    }
                }
            }
        }

        // VPN.
        Label {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: root.vpns.length > 0
            text: "VPN"
            font.weight: Font.DemiBold
            color: Theme.fgDim
        }
        Repeater {
            model: root.vpns
            delegate: RowLayout {
                id: vrow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 360
                Icon {
                    Layout.leftMargin: 8
                    implicitSize: 16
                    name: "network-vpn"
                    fallback: "network-vpn"
                    opacity: vrow.modelData.active ? 1 : 0.5
                }
                Label {
                    Layout.fillWidth: true
                    text: vrow.modelData.name
                    color: vrow.modelData.active ? Theme.fg : Theme.fgDim
                }
                Label {
                    text: vrow.modelData.type === "wireguard" ? "WireGuard" : ""
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
                Switch {
                    checked: vrow.modelData.active
                    onToggled: root.toggleVpn(vrow.modelData)
                }
            }
        }
        Label {
            Layout.fillWidth: true
            Layout.preferredWidth: 360
            visible: vpnToggle.error !== ""
            text: vpnToggle.error
            color: Theme.bad
            wrapMode: Text.Wrap
            font.pointSize: Theme.smallFontSize
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
            icon: "preferences-system-network"
            text: "Edit connections…"
            onTriggered: {
                Quickshell.execDetached(["kcmshell6", "kcm_networkmanagement"]);
                root.popup.close();
            }
        }

        // One Wi-Fi network: click to connect/disconnect; secured unknown
        // networks open a password field underneath.
        component WifiRow: Column {
            id: wr
            required property var modelData
            readonly property var net: modelData
            readonly property bool prompting: pop.pskFor === net

            Connections {
                target: wr.net
                function onConnectionFailed(reason) {
                    pop.failure = wr.net.name + ": " + ConnectionFailReason.toString(reason);
                    if (reason === ConnectionFailReason.NoSecrets && root.needsPsk(wr.net)) pop.pskFor = wr.net;
                }
                function onConnectedChanged() {
                    if (wr.net.connected) { pop.failure = ""; if (pop.pskFor === wr.net) pop.pskFor = null; }
                }
            }

            MouseArea {
                id: area
                width: parent.width
                height: 34
                hoverEnabled: true
                onClicked: {
                    const n = wr.net;
                    pop.failure = "";
                    if (n.connected) return;
                    if (!n.known && root.needsPsk(n)) { pop.pskFor = wr.prompting ? null : n; return; }
                    n.connect();
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: area.pressed ? Theme.pressed : area.containsMouse || wr.prompting ? Theme.hover : "transparent"
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 6
                    spacing: 8
                    Icon {
                        implicitSize: 18
                        name: root.wifiIcon(wr.net.signalStrength, root.secured(wr.net))
                        fallback: "network-wireless"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            Layout.fillWidth: true
                            text: wr.net.name
                            font.weight: wr.net.connected ? Font.DemiBold : Font.Normal
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            font.pointSize: Theme.smallFontSize
                            color: Theme.fgDim
                            text: wr.net.connected ? "Connected"
                                : wr.net.stateChanging ? ConnectionState.toString(wr.net.state) + "…"
                                : wr.net.known ? "Saved" : ""
                        }
                    }
                    BarButton {
                        visible: wr.net.connected || wr.net.known
                        implicitHeight: 26
                        text: wr.net.connected ? "Disconnect" : "Forget"
                        onClicked: wr.net.connected ? wr.net.disconnect() : wr.net.forget()
                    }
                }
            }

            // Password prompt.
            RowLayout {
                width: parent.width
                visible: wr.prompting
                height: visible ? 36 : 0
                spacing: 6
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 34
                    implicitHeight: 28
                    radius: Theme.radius
                    color: Theme.bg
                    border.color: psk.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: psk
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        renderType: Text.NativeRendering
                        color: Theme.fg
                        selectionColor: Theme.accentDim
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSize
                        echoMode: show.checked ? TextInput.Normal : TextInput.Password
                        clip: true
                        onAccepted: go.clicked(null)
                        Keys.onEscapePressed: pop.pskFor = null
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: psk.text === ""
                            text: "Password"
                            color: Theme.fgDim
                        }
                    }
                    onVisibleChanged: if (visible) { psk.text = ""; psk.forceActiveFocus(); }
                }
                BarButton {
                    id: show
                    property bool checked: false
                    implicitHeight: 28
                    implicitWidth: 30
                    iconSize: 16
                    icon: checked ? "view-hidden" : "view-visible"
                    tooltip: checked ? "Hide password" : "Show password"
                    onClicked: checked = !checked
                }
                BarButton {
                    id: go
                    implicitHeight: 28
                    text: "Connect"
                    enabled: psk.text.length >= 8 || wr.net.security === WifiSecurityType.StaticWep
                    opacity: enabled ? 1 : 0.5
                    onClicked: {
                        if (!enabled) return;
                        wr.net.connectWithPsk(psk.text);
                        pop.pskFor = null;
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.preferredWidth: 360
            visible: pop.failure !== ""
            text: "Connection failed — " + pop.failure
            color: Theme.bad
            wrapMode: Text.Wrap
            font.pointSize: Theme.smallFontSize
        }
    }

    // Small on/off switch.
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
