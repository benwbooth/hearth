import QtQuick
import QtQuick.Layouts
import Quickshell
import "../widgets"
import "../services"
import ".."

// About This Computer (menu bar logo menu; services/About.qml), like
// macOS's About This Mac: a small window with the computer's name, its
// processor, graphics, memory, display, startup disk and system versions,
// and "More Info…", a larger window with everything KDE's Info Center
// showed: storage per drive, graphics drivers, displays, USB and PCI
// devices, keyboards and mice, audio, network, firmware and batteries.
Scope {
    id: root
    property bool open: false
    property bool moreOpen: false
    property string section: "overview"

    Connections {
        target: About
        function onOpenRequested() { root.open = true; About.refresh(false); }
        function onMoreRequested() { root.moreOpen = true; About.refresh(true); }
    }
    readonly property var i: About.info

    function uptime(s) {
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        const parts = [];
        if (d) parts.push(d + (d === 1 ? " day" : " days"));
        if (h) parts.push(h + (h === 1 ? " hour" : " hours"));
        if (m || !parts.length) parts.push(m + (m === 1 ? " minute" : " minutes"));
        return parts.join(", ");
    }
    function displayText(d) {
        return (d.inches ? d.inches + "-inch " : "") + (d.make + " " + d.model).trim() + " (" + d.width + " × " + d.height + ", " + d.refresh + " Hz"
            + (d.scale && d.scale !== 1 ? ", " + Math.round(d.scale * 100) + "%" : "") + ")";
    }
    readonly property var summaryRows: !i ? [] : [
        ["Processor", i.cpu.model + " (" + i.cpu.cores + " cores, " + i.cpu.threads + " threads" + (i.cpu.maxGHz ? ", up to " + i.cpu.maxGHz + " GHz" : "") + ")"],
        ["Graphics", i.gpus.filter(g => !g.integrated).map(g => g.name + (g.vramText ? " " + g.vramText : "")).join(", ") || (i.gpus[0] ? i.gpus[0].name : "")],
        ["Memory", i.memory.installedText],
        ["Display", i.displays.map(d => root.displayText(d)).join("\n")],
        ["Startup disk", i.storage.length ? i.storage[0].label + " (" + i.storage[0].freeText + " free of " + i.storage[0].sizeText + ")" : ""],
        ["System", i.os.pretty + (i.os.kernel ? ", Linux " + i.os.kernel : "")],
        ["Desktop", "hearth " + i.os.hearth + (i.os.arbor ? ", arbor " + i.os.arbor : "")]
    ].filter(r => r[1])

    // --- the small window ---
    LazyLoader {
        active: root.open
        FloatingWindow {
            title: "About This Computer"
            visible: true
            implicitWidth: 460
            implicitHeight: 560
            minimumSize: Qt.size(420, 500)
            color: Theme.bg
            onVisibleChanged: if (!visible) root.open = false

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                anchors.topMargin: 28.001
                spacing: 10

                Logo {
                    Layout.alignment: Qt.AlignHCenter
                    name: Settings.menubar.logo && Settings.menubar.logo !== "none" ? Settings.menubar.logo : "nixos"
                    size: 96
                    color: Theme.fg
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.i ? root.i.machine.hostname : "This Computer"
                    font.pointSize: Theme.fontSize + 10
                    font.weight: Font.DemiBold
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.i ? root.i.machine.model : ""
                    color: Theme.fgSecondary
                }
                Item { Layout.preferredHeight: 8 }
                Repeater {
                    model: root.summaryRows
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 12
                        Label {
                            Layout.preferredWidth: 110
                            Layout.alignment: Qt.AlignTop
                            horizontalAlignment: Text.AlignRight
                            text: modelData[0]
                            font.weight: Font.DemiBold
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData[1]
                            color: Theme.fgDim
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                        }
                    }
                }
                Label {
                    visible: !root.i
                    Layout.alignment: Qt.AlignHCenter
                    text: "Reading…"
                    color: Theme.fgSecondary
                }
                Item { Layout.fillHeight: true }
                PushButton {
                    Layout.alignment: Qt.AlignHCenter
                    text: "More Info…"
                    tooltip: "Storage, graphics drivers, displays, USB and PCI devices, audio, network, firmware, batteries"
                    onClicked: { root.moreOpen = true; About.refresh(true); }
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.i ? "Up " + root.uptime(root.i.os.uptime) : ""
                    color: Theme.fgSecondary
                    font.pointSize: Theme.smallFontSize
                }
            }
        }
    }

    // --- More Info… ---
    readonly property var sections: [
        { id: "overview", label: "Overview", icon: "computer" },
        { id: "storage", label: "Storage", icon: "drive-harddisk" },
        { id: "graphics", label: "Graphics & Displays", icon: "video-display" },
        { id: "memory", label: "Memory", icon: "media-flash" },
        { id: "usb", label: "USB", icon: "drive-removable-media-usb" },
        { id: "pci", label: "PCI", icon: "preferences-devices-cpu" },
        { id: "input", label: "Keyboards & Mice", icon: "input-keyboard" },
        { id: "audio", label: "Sound", icon: "audio-card" },
        { id: "network", label: "Network", icon: "network-wired" },
        { id: "firmware", label: "Firmware", icon: "cpu" },
        { id: "energy", label: "Batteries & Power", icon: "battery" }
    ]
    // [{ title, rows: [[key, value]] }] for the chosen section.
    readonly property var detail: {
        const i = root.i;
        if (!i || !i.pci) return [];
        const gb = b => (b / 1e9).toFixed(b >= 1e11 ? 0 : 1) + " GB";
        switch (root.section) {
        case "overview": return [{ title: "", rows: root.summaryRows.concat([["Uptime", root.uptime(i.os.uptime)], ["NixOS", i.os.nixos], ["Host name", i.machine.hostname]]) }];
        case "storage": return i.storage.map(s => ({ title: s.label + " — " + s.mount, bar: s.used / s.size,
            rows: [["Capacity", s.sizeText], ["Used", gb(s.used)], ["Free", s.freeText], ["Format", s.fstype], ["Device", s.device]] }));
        case "graphics": return i.gpus.map(g => {
            const v = (i.graphics || []).find(x => g.name.indexOf(x.deviceName) >= 0 || x.deviceName.indexOf(g.name.split(" ").slice(-1)[0]) >= 0);
            return { title: g.name, rows: [["Memory", g.vramText || "shared"], ["Type", g.integrated ? "Integrated" : "Graphics card"], ["Slot", g.slot]]
                .concat(v ? [["Driver", v.driverName + " " + (v.driverInfo || "")], ["Vulkan", v.apiVersion]] : []) };
        }).concat(i.displays.map(d => ({ title: (d.make + " " + d.model).trim() || d.name,
            rows: [["Connector", d.name], ["Resolution", d.width + " × " + d.height], ["Refresh rate", d.refresh + " Hz"], ["Scale", d.scale ? Math.round(d.scale * 100) + "%" : ""], ["Size", d.inches ? d.inches + " inches" : ""]] })));
        case "memory": return [{ title: "", rows: [["Installed", i.memory.installedText], ["Usable", gb(i.memory.total)], ["Available now", gb(i.memory.available)], ["Swap", i.memory.swap ? gb(i.memory.swap) : "none"]] }];
        case "usb": return [{ title: i.usb.length + " devices", rows: i.usb.map(u => [u.id, u.name]) }];
        case "pci": return [{ title: i.pci.length + " devices", rows: i.pci.map(p => [p.slot, p.class + ": " + p.vendor + " " + p.device]) }];
        case "input": return [{ title: "", rows: i.inputs.map(d => [d.kind, d.name]) }];
        case "audio": return [{ title: "Outputs", rows: i.audio.outputs.map(a => [(a.default ? "✓ " : "") + (a.volume !== null ? a.volume + "%" : ""), a.name]) },
                              { title: "Inputs", rows: i.audio.inputs.map(a => [(a.default ? "✓ " : "") + (a.volume !== null ? a.volume + "%" : ""), a.name]) }];
        case "network": return i.network.map(n => ({ title: n.name + (n.connection ? " — " + n.connection : ""),
            rows: [["Type", n.type], ["State", n.state], ["Addresses", n.addresses.join(", ")], ["Hardware address", n.mac]] }));
        case "firmware": return [{ title: "", rows: [["Board", i.firmware.board], ["Firmware", i.firmware.biosVendor], ["Version", i.firmware.biosVersion], ["Date", i.firmware.biosDate],
            ["Boot mode", i.firmware.boot], ["Secure Boot", i.firmware.secureBoot === null ? "" : i.firmware.secureBoot ? "on" : "off"]] }];
        case "energy": return i.energy.length ? i.energy.map(e => ({ title: e.model || e.name, rows: e.kind === "Battery"
            ? [["Charge", e.capacity ? e.capacity + "%" : ""], ["Status", e.status], ["Health", e.health ? e.health + "%" : ""], ["Cycles", e.cycles]]
            : [["Power adapter", e.online ? "connected" : "not connected"]] }))
            : [{ title: "", rows: [["Power", "No batteries: this computer runs on mains power."]] }];
        }
        return [];
    }

    LazyLoader {
        active: root.moreOpen
        FloatingWindow {
            title: "System Information"
            visible: true
            implicitWidth: 900
            implicitHeight: 620
            minimumSize: Qt.size(700, 460)
            color: Theme.bg
            onVisibleChanged: if (!visible) root.moreOpen = false

            Item {
                anchors.fill: parent
                transform: Translate { x: 0.001; y: 0.001 }

                Rectangle {
                    id: side
                    width: 220
                    height: parent.height
                    color: Theme.bgAlt
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
                    Column {
                        x: 10; y: 14
                        width: parent.width - 20
                        spacing: 2
                        Repeater {
                            model: root.sections
                            MouseArea {
                                id: nav
                                required property var modelData
                                width: parent.width
                                height: 32
                                hoverEnabled: true
                                onClicked: root.section = modelData.id
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radius
                                    color: root.section === nav.modelData.id ? Theme.accent : nav.containsMouse ? Theme.hover : "transparent"
                                }
                                Row {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    Icon { implicitSize: 18; name: nav.modelData.icon; anchors.verticalCenter: parent.verticalCenter }
                                    Label { text: nav.modelData.label; color: root.section === nav.modelData.id ? Theme.accentText : Theme.fg; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                        }
                    }
                }

                ScrollAssist { flickable: aboutFlick }
                Flickable {
                    id: aboutFlick
                    anchors.left: side.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    contentHeight: col.implicitHeight + 40
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: col
                        x: 24; y: 20
                        width: parent.width - 48
                        spacing: 14
                        Label {
                            text: (root.sections.find(s => s.id === root.section) || {}).label || ""
                            font.pointSize: Theme.fontSize + 6
                            font.weight: Font.Bold
                        }
                        Label { visible: !About.full; text: "Reading…"; color: Theme.fgSecondary }
                        Repeater {
                            model: root.detail
                            ColumnLayout {
                                id: grp
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 6
                                Label { visible: grp.modelData.title !== ""; text: grp.modelData.title; font.weight: Font.DemiBold }
                                // Storage: used/free bar.
                                Rectangle {
                                    visible: grp.modelData.bar !== undefined
                                    Layout.fillWidth: true
                                    height: 10
                                    radius: 5
                                    color: Theme.hover
                                    Rectangle {
                                        width: parent.width * Math.min(1, grp.modelData.bar || 0)
                                        height: parent.height
                                        radius: 5
                                        color: (grp.modelData.bar || 0) > 0.9 ? Theme.bad : (grp.modelData.bar || 0) > 0.75 ? Theme.warn : Theme.accent
                                    }
                                }
                                SettingsGroup {
                                    Repeater {
                                        model: grp.modelData.rows.filter(r => r[1] !== "" && r[1] !== undefined && r[1] !== null)
                                        Item {
                                            required property var modelData
                                            width: parent ? parent.width : 0
                                            height: Math.max(30, val.implicitHeight + 10)
                                            Label {
                                                id: key
                                                width: 170
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: parent.modelData[0]
                                                color: Theme.fgSecondary
                                            }
                                            Label {
                                                id: val
                                                anchors.left: key.right
                                                anchors.leftMargin: 10
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: String(parent.modelData[1])
                                                wrapMode: Text.Wrap
                                                elide: Text.ElideNone
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
