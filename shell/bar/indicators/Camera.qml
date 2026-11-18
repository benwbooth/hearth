import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../../widgets"
import "../.."

// Shown only while a camera is in use, with the apps using it.
//
// Two sources, merged: PipeWire links from a Video/Source node to an app's
// stream (apps using the camera through the portal/PipeWire), and a /proc
// scan for processes holding /dev/video* open (apps that open V4L2
// directly, which PipeWire can't see). PipeWire's own daemons are left out
// of the latter since they only hold the device on behalf of a stream.
Indicator {
    id: root

    // Apps reading a PipeWire camera node: [{ name, camera }]
    readonly property var camLinks: Pipewire.links.values.filter(l =>
        l.source && l.target && l.source.type === PwNodeType.VideoSource)
    readonly property var pwUsers: {
        const out = [];
        for (const l of root.camLinks) {
            const src = l.source, dst = l.target;
            const p = dst.properties || {};
            const name = p["application.name"] || p["application.process.binary"] || dst.description || dst.name;
            if (!out.some(u => u.name === name)) out.push({ name: name, camera: src.description || src.nickname || src.name });
        }
        return out;
    }
    // Node properties (application.name) are only filled in for bound nodes.
    PwObjectTracker { objects: root.camLinks.map(l => l.target) }
    // Processes with /dev/video* open: [{ pid, name, device }]
    property var v4lUsers: []

    readonly property var users: {
        const out = root.pwUsers.slice();
        for (const u of root.v4lUsers) {
            if (!out.some(o => o.name.toLowerCase() === u.name.toLowerCase()))
                out.push({ name: u.name, camera: u.device });
        }
        return out;
    }
    shown: users.length > 0
    icon: "camera-on"
    iconFallback: "camera-web"
    tooltip: "Camera in use"
    tooltipSub: users.map(u => u.name).join(", ")

    Process {
        id: scan
        command: ["python3", "-c", `
import os, json
skip = {"pipewire", "wireplumber", "pipewire-media-session"}
out = []
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    try:
        fds = os.scandir(f"/proc/{pid}/fd")
    except OSError:
        continue
    dev = None
    with fds:
        for fd in fds:
            try:
                t = os.readlink(fd.path)
            except OSError:
                continue
            if t.startswith("/dev/video"):
                dev = t
                break
    if not dev:
        continue
    try:
        comm = open(f"/proc/{pid}/comm").read().strip()
    except OSError:
        continue
    if comm in skip or comm.startswith(".pipewire"):
        continue
    try:
        dev = open(f"/sys/class/video4linux/{os.path.basename(dev)}/name").read().strip()
    except OSError:
        pass
    out.append({"pid": int(pid), "name": comm, "device": dev})
print(json.dumps(out))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(text);
                    if (JSON.stringify(v) !== JSON.stringify(root.v4lUsers)) root.v4lUsers = v;
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!scan.running) scan.running = true
    }
    popupContent: ColumnLayout {
        spacing: 4
        Label {
            Layout.preferredWidth: 260
            text: "Camera in use"
            font.weight: Font.DemiBold
        }
        Repeater {
            model: root.users
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Icon {
                    implicitSize: 22
                    name: {
                        const e = DesktopEntries.heuristicLookup(parent.modelData.name);
                        return e && e.icon ? e.icon : "camera-web";
                    }
                    fallback: "camera-web"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { Layout.fillWidth: true; text: parent.parent.modelData.name }
                    Label {
                        Layout.fillWidth: true
                        text: parent.parent.modelData.camera || ""
                        visible: text !== ""
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                    }
                }
            }
        }
    }
}
