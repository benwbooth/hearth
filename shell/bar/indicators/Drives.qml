import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../widgets"
import "../../services"
import "../.."

// Removable drives (USB sticks, SD cards, external disks): shown only while
// one with a filesystem is plugged in. The popup mounts, unmounts, opens
// and safely removes them through udisksctl. The list comes from lsblk and
// is refreshed whenever `udisksctl monitor` reports a change.
Indicator {
    id: root
    icon: menuBarItem ? Symbols.eject : "drive-removable-media"
    shown: devices.length > 0
    tooltip: devices.length === 1 ? devices[0].title : devices.length + " removable drives"
    tooltipSub: devices.map(d => d.filesystems.map(f => f.label + (f.mountpoint ? " — " + f.mountpoint : " (not mounted)")).join("\n")).join("\n")

    // [{ path, title, size, filesystems: [{ path, label, size, fstype, mountpoint, used, total }] }]
    property var devices: []
    property string busyPath: ""
    property string error: ""

    function fmtSize(b) {
        if (!b && b !== 0) return "";
        const u = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
        let i = 0;
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
        return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i];
    }

    function parse(json) {
        const removableTran = ["usb", "mmc", "ieee1394", "memstick"];
        const out = [];
        let data;
        try { data = JSON.parse(json); } catch (e) { return; }
        for (const d of data.blockdevices || []) {
            if (d.type !== "disk") continue;
            if (!(d.hotplug || d.rm || removableTran.indexOf(d.tran) >= 0)) continue;
            const fss = [];
            const walk = n => {
                if (n.fstype && n.fstype !== "swap" && n.fstype !== "crypto_LUKS") {
                    const mps = (n.mountpoints || []).filter(m => m);
                    fss.push({
                        path: n.path,
                        label: n.label || n.name,
                        size: n.size,
                        fstype: n.fstype,
                        mountpoint: mps.length > 0 ? mps[0] : "",
                        used: n.fsused || 0,
                        total: n.fssize || 0
                    });
                }
                for (const c of n.children || []) walk(c);
            };
            walk(d);
            if (fss.length === 0) continue;
            const model = (d.model || "").trim();
            out.push({
                path: d.path,
                title: model || (fss[0].label) || d.name,
                size: d.size,
                tran: d.tran || "",
                filesystems: fss
            });
        }
        root.devices = out;
    }

    function run(path, cmd) {
        if (action.running) return;
        root.busyPath = path;
        root.error = "";
        action.command = cmd;
        action.running = true;
    }
    function mount(fs) { run(fs.path, ["udisksctl", "mount", "--no-user-interaction", "-b", fs.path]); }
    function unmount(fs) { run(fs.path, ["udisksctl", "unmount", "--no-user-interaction", "-b", fs.path]); }
    function open(fs) { Quickshell.execDetached(["xdg-open", fs.mountpoint]); root.popup.close(); }
    // Unmount everything on the disk, then power it off.
    function safelyRemove(dev) {
        const mounted = dev.filesystems.filter(f => f.mountpoint).map(f => f.path);
        const script = 'set -e; disk=$1; shift; for p in "$@"; do udisksctl unmount --no-user-interaction -b "$p"; done; '
                     + 'udisksctl power-off --no-user-interaction -b "$disk"';
        run(dev.path, ["sh", "-c", script, "sh", dev.path].concat(mounted));
    }

    Process {
        id: lsblk
        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,SIZE,FSTYPE,MOUNTPOINTS,HOTPLUG,RM,TRAN,MODEL,TYPE,FSUSED,FSSIZE"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
    function refresh() { if (!lsblk.running) lsblk.running = true; else refreshTimer.restart(); }

    Timer {
        id: refreshTimer
        interval: 400
        onTriggered: root.refresh()
    }

    Process {
        id: monitor
        command: ["udisksctl", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: line => refreshTimer.restart()
        }
        onExited: monitorRestart.start()
    }
    Timer {
        id: monitorRestart
        interval: 5000
        onTriggered: monitor.running = true
    }

    Process {
        id: action
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: (code, status) => {
            if (code !== 0) root.error = actionErr.text.trim() || "Failed (exit " + code + ")";
            root.busyPath = "";
            root.refresh();
        }
    }

    Connections {
        target: root.popup
        function onOpenChanged() { if (root.popup.open) { root.error = ""; root.refresh(); } }
    }

    popupContent: ColumnLayout {
        spacing: 10

        Label {
            text: "Removable drives"
            font.weight: Font.DemiBold
            Layout.minimumWidth: 340
        }

        Repeater {
            model: root.devices
            delegate: ColumnLayout {
                id: dev
                required property var modelData
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Icon {
                        implicitSize: 32
                        name: dev.modelData.tran === "usb" ? "drive-removable-media-usb" : "drive-removable-media"
                        fallback: "drive-removable-media"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            Layout.fillWidth: true
                            text: dev.modelData.title
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.fmtSize(dev.modelData.size) + (dev.modelData.tran ? " · " + dev.modelData.tran.toUpperCase() : "")
                            color: Theme.fgDim
                            font.pointSize: Theme.smallFontSize
                        }
                    }
                    BarButton {
                        implicitHeight: 32
                        icon: "media-eject"
                        tooltip: "Safely remove"
                        enabled: root.busyPath === ""
                        opacity: enabled ? 1 : 0.5
                        onClicked: root.safelyRemove(dev.modelData)
                    }
                }

                Repeater {
                    model: dev.modelData.filesystems
                    delegate: RowLayout {
                        id: fs
                        required property var modelData
                        readonly property bool mounted: modelData.mountpoint !== ""
                        readonly property bool busy: root.busyPath === modelData.path || root.busyPath === dev.modelData.path
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                Layout.fillWidth: true
                                text: fs.modelData.label + "  " + root.fmtSize(fs.modelData.size) + " " + fs.modelData.fstype
                                font.pointSize: Theme.smallFontSize
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 4
                                visible: fs.mounted && fs.modelData.total > 0
                                radius: 2
                                color: Theme.border
                                Rectangle {
                                    width: parent.width * (fs.modelData.used / Math.max(1, fs.modelData.total))
                                    height: parent.height
                                    radius: 2
                                    color: fs.modelData.used / Math.max(1, fs.modelData.total) > 0.9 ? Theme.warn : Theme.accent
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                text: fs.busy ? "Working…"
                                    : fs.mounted ? root.fmtSize(fs.modelData.total - fs.modelData.used) + " free · " + fs.modelData.mountpoint
                                    : "Not mounted"
                                color: Theme.fgDim
                                font.pointSize: Theme.smallFontSize
                            }
                        }
                        BarButton {
                            implicitHeight: 30
                            visible: fs.mounted
                            icon: "document-open-folder"
                            tooltip: "Open in file manager"
                            onClicked: root.open(fs.modelData)
                        }
                        BarButton {
                            implicitHeight: 30
                            text: fs.mounted ? "Unmount" : "Mount"
                            enabled: root.busyPath === ""
                            opacity: enabled ? 1 : 0.5
                            onClicked: fs.mounted ? root.unmount(fs.modelData) : root.mount(fs.modelData)
                        }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            visible: root.error !== ""
            text: root.error
            color: Theme.bad
            wrapMode: Text.Wrap
            font.pointSize: Theme.smallFontSize
        }
    }
}
