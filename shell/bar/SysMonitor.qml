import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../widgets"
import ".."

// treetop's panel widget, KStats-style: CPU, memory, the main GPU and its
// VRAM as small history graphs with the value inside, network rates, and
// CPU/GPU temperatures. Ported from ~/src/treetop/plasmoid; the numbers come
// straight from /proc and sysfs (amdgpu/hwmon) instead of ksystemstats.
// Clicking shows/hides the treetop window; hovering an item asks treetop
// (over D-Bus) which programs are using it.
MouseArea {
    id: root

    // ---- settings (Ben's Plasma config: hiddenGpus=1,2,3, labels=stacked,
    // showDisk=false; the rest are the plasmoid's defaults) ---------------
    readonly property int updateRate: 1000
    readonly property int historyLength: 60   // samples (one a second): a minute across the graph
    readonly property var hiddenGpus: ["1", "2", "3"]   // display positions, "0" = GPU1
    readonly property bool hideIdleGpus: true
    readonly property bool showVram: true
    readonly property bool showDisk: true          // space used on the system drive
    readonly property bool showNetwork: true
    readonly property bool showTemps: true
    readonly property real graphWidth: 0.9
    // Item height: the bar's thickness less a margin (the thin mac menu bar
    // sets `barHeight` on its window, like BarButton reads).
    readonly property var hostWindow: root.QsWindow.window
    readonly property int hostHeight: hostWindow && hostWindow.barHeight ? hostWindow.barHeight : Theme.barHeight
    readonly property bool onTop: !!hostWindow && hostWindow.edge === "top"
    readonly property real h: hostHeight - (hostHeight < 36 ? 4 : 8)

    // In the macOS menu bar the graphs blend in like the status icons
    // around them: monochrome (menu bar text colour), unframed, on a faint
    // rounded well; the classic panel keeps treetop's colours.
    readonly property bool blend: onTop
    readonly property color mono: Theme.barFg
    readonly property var palette: blend ? ({ cpu: mono, mem: mono, gpu: mono, vram: mono, disk: mono, net: mono, temp: mono, warn: "#ff6b5e" }) : treetopPalette
    // Same palette as the treetop app and its tray bars.
    // The tooltip's colours: the bar's monochrome (Theme.barFg, white over a
    // dark wallpaper) is invisible on the tooltip's glass, which follows the
    // light/dark theme instead; there it's the tooltip's own text colour.
    readonly property var tipPalette: blend ? ({ cpu: Theme.fg, mem: Theme.fg, gpu: Theme.fg, vram: Theme.fg, disk: Theme.fg, net: Theme.fg, temp: Theme.fg, warn: palette.warn }) : treetopPalette
    readonly property var treetopPalette: ({ cpu: "#43c96b", mem: "#d6b23e", gpu: "#c06fd8", vram: "#d070a8", disk: "#4fb3d9", net: "#4f8fe0", temp: "#e0894f", warn: "#e05a4f" })

    implicitWidth: strip.implicitWidth + 8
    implicitHeight: hostHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: toggleTreetop()

    // ---- open treetop ----------------------------------------------------
    // Show/hide treetop over D-Bus (works however it was started); if it
    // isn't running, start it (through devloop when that manages it).
    function toggleTreetop() {
        Quickshell.execDetached(["sh", "-c",
            "busctl --user call com.benwbooth.treetop /treetop com.benwbooth.treetop Toggle >/dev/null 2>&1"
            + " || \"$HOME/.local/bin/devloop\" start treetop >/dev/null 2>&1"
            + " || exec setsid treetop >/dev/null 2>&1"]);
    }

    // ---- hardware discovery ------------------------------------------------
    // GPUs (cards with amdgpu's busy/VRAM files), their edge temperature,
    // whether they drive a connected display and their name; the CPU's hwmon
    // temperature; the physical network interfaces. Re-read now and then
    // for monitor hotplugs.
    property var gpus: []          // [{card, dev, temp, display, vramTotal, name}], treetop's order
    property string cpuTempPath: ""
    property var netIfaces: []

    Process {
        id: discover
        running: true
        command: ["sh", "-c", `
for c in /sys/class/drm/card[0-9]*; do
  case \${c##*/} in *-*) continue;; esac
  d=$(readlink -f $c/device)
  [ -r $d/gpu_busy_percent ] || continue
  h=$(ls -d $d/hwmon/hwmon* 2>/dev/null | head -n1)
  t=""
  for l in $h/temp*_label; do [ -r "$l" ] && [ "$(cat $l)" = edge ] && t=\${l%_label}_input; done
  [ -z "$t" ] && [ -n "$h" ] && t=$h/temp1_input
  conn=0; grep -qx connected $c-*/status 2>/dev/null && conn=1
  name=""
  if command -v lspci >/dev/null; then
    name=$(lspci -vmm -s \${d##*/} 2>/dev/null | awk -F'\\t' '/^Device:/{d=$2} /^SDevice:/{s=$2} END{printf "%s", d; if (s!="") printf " (%s)", s}')
  fi
  printf 'gpu\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "\${c##*/card}" "$d" "$t" "$conn" "$(cat $d/mem_info_vram_total 2>/dev/null || echo 0)" "$name"
done
for h in /sys/class/hwmon/hwmon*; do
  case $(cat $h/name) in k10temp|coretemp|zenpower|cpu_thermal) printf 'cpu\\t%s\\n' $h/temp1_input; break;; esac
done
for n in /sys/class/net/*; do
  case $(readlink -f $n) in */virtual/*) continue;; esac
  printf 'net\\t%s\\n' \${n##*/}
done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const gpus = [], ifaces = [];
                let cpu = "";
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f[0] === "gpu") gpus.push({ card: Number(f[1]), dev: f[2], temp: f[3], display: f[4] === "1", vramTotal: Number(f[5]) || 0, name: f[6] || "" });
                    else if (f[0] === "cpu") cpu = f[1];
                    else if (f[0] === "net") ifaces.push(f[1]);
                }
                // Like the treetop app: the one driving the display first,
                // then by VRAM, so "GPU1" is the same card everywhere.
                gpus.sort((a, b) => (b.display - a.display) || (b.vramTotal - a.vramTotal));
                if (JSON.stringify(gpus) !== JSON.stringify(root.gpus)) root.gpus = gpus;
                root.cpuTempPath = cpu;
                if (JSON.stringify(ifaces) !== JSON.stringify(root.netIfaces)) root.netIfaces = ifaces;
            }
        }
    }
    Timer {
        interval: 30000; running: true; repeat: true
        onTriggered: discover.running = true
    }

    // ---- sampling ----------------------------------------------------------
    component SysFile: FileView {
        blockLoading: true
        printErrors: false
        function read() { reload(); return text(); }
    }
    SysFile { id: statFile; path: "/proc/stat" }
    SysFile { id: memFile; path: "/proc/meminfo" }
    SysFile { id: netFile; path: "/proc/net/dev" }
    SysFile { id: cpuTempFile; path: root.cpuTempPath }

    Instantiator {
        id: gpuFiles
        model: root.gpus
        delegate: QtObject {
            required property var modelData
            property SysFile busy: SysFile { path: modelData.dev + "/gpu_busy_percent" }
            property SysFile vram: SysFile { path: modelData.dev + "/mem_info_vram_used" }
            property SysFile temp: SysFile { path: modelData.temp }
            // Latest sample and histories (0..1).
            property real usage: 0
            property real vramUsed: 0
            property real tempC: 0
            property var hist: []
            property var vhist: []
        }
    }

    property real cpuUsage: 0      // %
    property real cpuTempC: 0
    property real memPercent: 0
    property real memUsed: 0       // bytes
    property real memTotal: 0
    property real netDown: 0       // bytes/s
    property real netUp: 0
    property var hCpu: []
    property var hMem: []
    // Disk space of the system drive (/), from df every 10 s (a Process, so
    // the shell never waits on a slow or sleeping disk).
    property real diskPercent: 0
    property real diskUsed: 0      // bytes
    property real diskSize: 0
    property var hDisk: []
    // Every mounted volume ({mount, used, size}), one per device (/home on
    // the root partition is the same space as /), for the Disk tooltip.
    property var diskVolumes: []
    property real peakNet: 1
    property int tick: 0
    property var lastCpu: null
    property int cpuCount: 0       // logical CPUs, for a program's share of the whole machine
    property var lastNet: null

    function push(a, v) { const b = a.slice(a.length >= historyLength ? 1 : 0); b.push(Math.max(0, v || 0)); return b; }

    function sample() {
        // CPU: busy share of the jiffies since the last sample.
        const stat = statFile.read();
        if (!cpuCount) cpuCount = (stat.match(/^cpu\d+ /gm) || []).length;
        const cl = stat.split("\n", 1)[0].trim().split(/\s+/).slice(1).map(Number);
        if (cl.length >= 4) {
            const idle = cl[3] + (cl[4] || 0);
            const total = cl.reduce((s, x, i) => i < 8 ? s + x : s, 0);
            if (lastCpu && total > lastCpu.total)
                cpuUsage = Math.max(0, Math.min(100, 100 * (1 - (idle - lastCpu.idle) / (total - lastCpu.total))));
            lastCpu = { idle: idle, total: total };
        }
        // Memory: used = total - available, like ksystemstats.
        const mi = {};
        for (const line of memFile.read().split("\n")) {
            const m = line.match(/^(\w+):\s+(\d+)/);
            if (m) mi[m[1]] = Number(m[2]) * 1024;
        }
        if (mi.MemTotal) {
            memTotal = mi.MemTotal;
            memUsed = mi.MemTotal - (mi.MemAvailable !== undefined ? mi.MemAvailable : mi.MemFree);
            memPercent = 100 * memUsed / memTotal;
        }
        // Network: physical interfaces' byte counters.
        let rx = 0, tx = 0;
        for (const line of netFile.read().split("\n")) {
            const m = line.match(/^\s*([^:\s]+):\s*(.*)$/);
            if (!m || netIfaces.indexOf(m[1]) < 0) continue;
            const f = m[2].trim().split(/\s+/).map(Number);
            rx += f[0]; tx += f[8];
        }
        const now = Date.now();
        if (lastNet && now > lastNet.t && rx >= lastNet.rx && tx >= lastNet.tx) {
            const dt = (now - lastNet.t) / 1000;
            netDown = (rx - lastNet.rx) / dt;
            netUp = (tx - lastNet.tx) / dt;
        }
        lastNet = { t: now, rx: rx, tx: tx };
        cpuTempC = cpuTempPath ? (Number(cpuTempFile.read()) || 0) / 1000 : 0;

        hCpu = push(hCpu, cpuUsage / 100);
        hMem = push(hMem, memPercent / 100);
        if (diskSize > 0) hDisk = push(hDisk, diskPercent / 100);
        peakNet = Math.max(131072, netDown + netUp, peakNet * 0.98);
        for (let i = 0; i < gpuFiles.count; i++) {
            const g = gpuFiles.objectAt(i);
            if (!g) continue;
            g.usage = Number(g.busy.read()) || 0;
            g.vramUsed = Number(g.vram.read()) || 0;
            g.tempC = (Number(g.temp.read()) || 0) / 1000;
            g.hist = push(g.hist, g.usage / 100);
            g.vhist = push(g.vhist, g.vramUsed / Math.max(1, g.modelData.vramTotal));
        }
        tick++;
    }
    Timer {
        interval: root.updateRate; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.sample()
    }
    Process {
        id: diskProbe
        // Real filesystems only (no tmpfs, overlays, snaps); "/" first.
        command: ["df", "-B1", "--output=source,used,size,target",
            "-x", "tmpfs", "-x", "devtmpfs", "-x", "overlay", "-x", "squashfs",
            "-x", "efivarfs", "-x", "ramfs", "-x", "autofs"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const vols = [];
                for (const line of text.trim().split("\n").slice(1)) {
                    const f = line.trim().split(/\s+/);
                    if (f.length < 4) continue;
                    const used = Number(f[1]), size = Number(f[2]);
                    const mount = f.slice(3).join(" ");
                    if (!(size > 0)) continue;
                    if (mount === "/") {
                        root.diskUsed = used;
                        root.diskSize = size;
                        root.diskPercent = 100 * used / size;
                    }
                    // One row per device: its shortest mount point.
                    const prev = seen[f[0]];
                    if (prev && prev.mount.length <= mount.length) continue;
                    if (prev) vols.splice(vols.indexOf(prev), 1);
                    const v = { mount: mount, used: used, size: size };
                    seen[f[0]] = v;
                    vols.push(v);
                }
                vols.sort((a, b) => (b.mount === "/") - (a.mount === "/") || a.mount.localeCompare(b.mount));
                root.diskVolumes = vols;
            }
        }
    }
    Timer {
        interval: 10000; running: root.showDisk; repeat: true; triggeredOnStart: true
        onTriggered: if (!diskProbe.running) diskProbe.running = true
    }

    // Idle for the last ~30 samples and not driving a display: folded away.
    function gpuIdle(k) {
        const g = gpuFiles.objectAt(k);
        if (!hideIdleGpus || !g || g.modelData.display) return false;
        if (g.hist.length < 20) return false;
        return Math.max(...g.hist) < 0.03 && g.vramUsed / Math.max(1, g.modelData.vramTotal) < 0.1;
    }
    // Shown GPUs, as positions in `gpus` (hiddenGpus holds positions too).
    readonly property var gpuIndexes: {
        tick;
        const out = [];
        for (let k = 0; k < gpus.length; k++)
            if (hiddenGpus.indexOf(String(k)) < 0 && !gpuIdle(k)) out.push(k);
        return out;
    }
    readonly property real gpuTempC: {
        tick;
        const k = gpuIndexes.length ? gpuIndexes[0] : (gpus.length ? 0 : -1);
        const g = k >= 0 ? gpuFiles.objectAt(k) : null;
        return g ? g.tempC : 0;
    }

    // ---- formatting --------------------------------------------------------
    function fmtRate(bytes) {
        bytes = Number(bytes) || 0;
        const u = ["B", "K", "M", "G"];
        let i = 0;
        while (bytes >= 1024 && i < 3) { bytes /= 1024; i++; }
        return (bytes < 10 && i > 0 ? bytes.toFixed(1) : bytes.toFixed(0)) + u[i];
    }
    function fmtBytes(bytes) {
        bytes = Number(bytes) || 0;
        const u = ["B", "KiB", "MiB", "GiB", "TiB"];
        let i = 0;
        while (bytes >= 1024 && i < 4) { bytes /= 1024; i++; }
        return bytes.toFixed(i > 0 ? 1 : 0) + " " + u[i];
    }
    readonly property font monoFont: Qt.font({ family: "monospace", pixelSize: Math.round(root.h * 0.3) })
    readonly property font monoBold: Qt.font({ family: "monospace", pixelSize: Math.round(root.h * 0.3), bold: true })
    // Menu bar (blend): two lines like iStat Menus: a small caps label over
    // the value, in the bar's font with even-width digits so values don't
    // jiggle. Sized from the bar: 8 + 11 px on the 27 px menu bar.
    readonly property font capFont: Qt.font({ family: Theme.fontFamily, pixelSize: Math.max(7, Math.round(root.h * 0.34)), weight: Font.DemiBold, letterSpacing: 0.3, features: { "tnum": 1 } })
    readonly property font valFont: Qt.font({ family: Theme.fontFamily, pixelSize: Math.max(9, Math.round(root.h * 0.48)), weight: Font.Medium, features: { "tnum": 1 } })
    function tempColor(t) { return t >= 80 ? "#e05a4f" : (t >= 60 ? "#e3c25a" : blend ? Theme.barFg : "#43c96b"); }
    function pct(v) { return (Number(v) || 0).toFixed(0) + "%"; }

    // ---- KStats-style pieces ---------------------------------------------
    // A label written top to bottom with each letter upright, on rows that
    // land on whole device pixels so fractional scaling can't round them
    // unevenly. Rows are sized for four letters so every label matches.
    component StackedLabel: Item {
        id: sl
        property string text
        property real h: 22
        property color color
        readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
        readonly property real row: Math.max(1, Math.floor(h * 0.92 / 4 * dpr)) / dpr
        implicitWidth: Math.ceil(fm.advanceWidth("W") + 1)
        implicitHeight: row * text.length

        FontMetrics { id: fm; font: probe.font }
        Label { id: probe; visible: false; font: Qt.font({ family: Theme.fontFamily, pixelSize: Math.max(5, Math.floor(sl.row * 0.8 * sl.dpr) / sl.dpr), bold: true }) }

        Repeater {
            model: sl.text.length
            Label {
                required property int index
                x: 0
                y: Math.round(index * sl.row * sl.dpr) / sl.dpr
                width: sl.implicitWidth
                height: sl.row
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideNone
                text: sl.text.charAt(index)
                color: sl.color
                opacity: root.blend ? 0.7 : 1
                font: probe.font
            }
        }
    }

    // One panel item: coloured stacked label and a small framed history
    // graph with the value in its lower-left corner.
    component KStat: RowLayout {
        id: stat
        property string label
        property string kind
        property color color: "#43c96b"
        property string value
        property var history: []       // 0..1
        property real h: 22
        spacing: Math.round(h * 0.06)

        HoverHandler { onHoveredChanged: root.setHover(stat.kind, hovered) }

        StackedLabel {
            visible: !root.blend
            Layout.alignment: Qt.AlignVCenter
            text: stat.label
            h: stat.h
            color: stat.color
        }
        // Menu bar: label over value, then the graph on its own.
        Column {
            visible: root.blend
            Layout.alignment: Qt.AlignVCenter
            spacing: -1
            Label { text: stat.label; font: root.capFont; color: Theme.barFgDim; height: Math.ceil(root.capFont.pixelSize * 1.1) }
            Label { text: stat.value; font: root.valFont; color: Theme.barFg; height: Math.ceil(root.valFont.pixelSize * 1.15)
                    // Widest value, so the graph beside it never moves.
                    width: Math.max(implicitWidth, widest.implicitWidth)
                    Label { id: widest; visible: false; text: "100%"; font: root.valFont } }
        }
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.blend ? Math.round(stat.h * 2.2) : Math.max(valueProbe.implicitWidth + 4, Math.round(stat.h * 1.56 * root.graphWidth))
            Layout.preferredHeight: root.blend ? Math.round(stat.h * 0.62) : Math.round(stat.h * 0.8)
            color: root.blend ? Qt.rgba(stat.color.r, stat.color.g, stat.color.b, 0.10) : "transparent"
            border.color: root.blend ? "transparent" : Qt.rgba(stat.color.r, stat.color.g, stat.color.b, 0.55)
            border.width: root.blend ? 0 : 1
            radius: root.blend ? 3 : 1
            // Only measures the value's width; the canvas paints it.
            Label {
                id: valueProbe
                visible: false
                text: stat.value
                font: Qt.font({ family: "monospace", pixelSize: Math.round(stat.h * 0.3), bold: true })
            }
            Canvas {
                id: graph
                anchors.fill: parent
                anchors.margins: 1
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, hh = height;
                    const v = stat.history;
                    if (v && v.length >= 2) {
                        const n = v.length;
                        const y = i => hh - Math.min(1, Math.max(0, v[i])) * hh;
                        ctx.beginPath();
                        ctx.moveTo(0, hh);
                        for (let i = 0; i < n; i++) ctx.lineTo(i / (n - 1) * w, y(i));
                        ctx.lineTo(w, hh);
                        ctx.closePath();
                        ctx.fillStyle = Qt.rgba(stat.color.r, stat.color.g, stat.color.b, root.blend ? 0.32 : 0.6);
                        ctx.fill();
                        ctx.beginPath();
                        for (let i = 0; i < n; i++) {
                            if (i === 0) ctx.moveTo(0, y(i)); else ctx.lineTo(i / (n - 1) * w, y(i));
                        }
                        ctx.strokeStyle = root.blend ? Qt.rgba(stat.color.r, stat.color.g, stat.color.b, 0.85) : Qt.lighter(stat.color, 1.25);
                        ctx.lineWidth = root.blend ? 1.2 : 1.5;
                        ctx.stroke();
                    }
                    if (root.blend) return;    // the value sits beside the graph
                    // Light digits with a dark halo, lower left (over the
                    // oldest history, leaving the current end in view).
                    ctx.font = "bold " + Math.round(stat.h * 0.3) + "px monospace";
                    ctx.textAlign = "left";
                    ctx.textBaseline = "bottom";
                    const bg = root.blend ? (Theme.barDark ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)) : Theme.bg;
                    ctx.lineJoin = "round";
                    ctx.lineWidth = root.blend ? 2.5 : 3;
                    ctx.strokeStyle = root.blend ? Qt.rgba(bg.r * 0.5, bg.g * 0.5, bg.b * 0.5, 0.55)
                                                 : Qt.rgba(bg.r * 0.6, bg.g * 0.6, bg.b * 0.6, 0.92);
                    ctx.strokeText(stat.value, 1, hh + 1);
                    ctx.fillStyle = root.blend ? Theme.barFg : Qt.lighter(Theme.fg, 1.1);
                    ctx.fillText(stat.value, 1, hh + 1);
                }
            }
        }
        onHistoryChanged: graph.requestPaint()
        onValueChanged: graph.requestPaint()
    }

    // ---- the strip ---------------------------------------------------------
    RowLayout {
        id: strip
        anchors.centerIn: parent
        spacing: Math.round(root.h * 0.16)

        KStat {
            h: root.h; label: "CPU"; kind: "cpu"; color: root.palette.cpu
            value: root.pct(root.cpuUsage)
            history: root.hCpu
        }
        KStat {
            h: root.h; label: "MEM"; kind: "mem"; color: root.palette.mem
            value: root.pct(root.memPercent)
            history: root.hMem
        }
        Repeater {
            model: root.gpuIndexes
            RowLayout {
                id: gpuItem
                required property int modelData
                readonly property var g: { root.tick; return gpuFiles.objectAt(modelData); }
                readonly property string n: root.gpuIndexes.length > 1 ? String(modelData + 1) : ""
                spacing: Math.round(root.h * 0.16)
                KStat {
                    h: root.h; label: "GPU" + gpuItem.n; kind: "gpu"; color: root.palette.gpu
                    value: gpuItem.g ? root.pct(gpuItem.g.usage) : "–"
                    history: gpuItem.g ? gpuItem.g.hist : []
                }
                // GPU memory: history of VRAM use, share used inside.
                KStat {
                    visible: root.showVram
                    h: root.h; label: "VRAM" + gpuItem.n; kind: "vram"; color: root.palette.vram
                    value: gpuItem.g ? root.pct(100 * gpuItem.g.vramUsed / Math.max(1, gpuItem.g.modelData.vramTotal)) : "–"
                    history: gpuItem.g ? gpuItem.g.vhist : []
                }
            }
        }
        // After the GPUs and their VRAM, as in the treetop app.
        KStat {
            visible: root.showDisk && root.diskSize > 0
            h: root.h; label: "DISK"; kind: "disk"; color: root.palette.disk
            value: root.pct(root.diskPercent)
            history: root.hDisk
        }
        // Network: stacked label and two stacked rates, like KStats.
        RowLayout {
            visible: root.showNetwork
            spacing: Math.round(root.h * 0.08)
            HoverHandler { onHoveredChanged: root.setHover("net", hovered) }
            StackedLabel {
                visible: !root.blend
                Layout.alignment: Qt.AlignVCenter
                text: "NET"
                h: root.h
                color: root.palette.net
            }
            Column {
                Layout.alignment: Qt.AlignVCenter
                spacing: root.blend ? -1 : -2
                Label { text: "↑ " + root.fmtRate(root.netUp); font: root.blend ? root.capFont : root.monoFont; color: root.blend ? Theme.barFg : Theme.fg
                        width: root.blend ? Math.max(implicitWidth, netW.implicitWidth) : implicitWidth
                        Label { id: netW; visible: false; text: "↑ 888.8M"; font: root.capFont } }
                Label { text: "↓ " + root.fmtRate(root.netDown); font: root.blend ? root.capFont : root.monoFont; color: root.blend ? Theme.barFg : Theme.fg }
            }
        }
        // Temperatures: CPU over GPU, each coloured by heat.
        RowLayout {
            visible: root.showTemps && (root.cpuTempC > 0 || root.gpuTempC > 0)
            spacing: Math.round(root.h * 0.08)
            HoverHandler { onHoveredChanged: root.setHover("temp", hovered) }
            StackedLabel {
                visible: !root.blend
                Layout.alignment: Qt.AlignVCenter
                text: "TEMP"
                h: root.h
                color: root.palette.temp
            }
            Repeater {
                model: root.blend ? [["CPU", root.cpuTempC], ["GPU", root.gpuTempC]].filter(t => t[1] > 0) : []
                Column {
                    required property var modelData
                    Layout.alignment: Qt.AlignVCenter
                    spacing: -1
                    Label { text: modelData[0]; font: root.capFont; color: Theme.barFgDim; height: Math.ceil(root.capFont.pixelSize * 1.1) }
                    Label { text: modelData[1].toFixed(0) + "°"; font: root.valFont; color: root.tempColor(modelData[1]); height: Math.ceil(root.valFont.pixelSize * 1.15) }
                }
            }
            Column {
                visible: !root.blend
                Layout.alignment: Qt.AlignVCenter
                spacing: -2
                Label {
                    visible: root.cpuTempC > 0
                    text: "CPU " + root.cpuTempC.toFixed(0) + "°"
                    color: root.tempColor(root.cpuTempC)
                    font: root.monoBold
                }
                Label {
                    visible: root.gpuTempC > 0
                    text: "GPU " + root.gpuTempC.toFixed(0) + "°"
                    color: root.tempColor(root.gpuTempC)
                    font: root.monoBold
                }
            }
        }
    }

    // ---- tooltips: summary, or "who's using it" ----------------------------
    // Hovering an item asks the treetop app (over D-Bus) for the top
    // programs using that resource, refreshed while the pointer stays.
    property string hoverKind: ""
    property var topData: null
    // An item's hover ends only when another item takes it or the pointer
    // leaves the whole monitor (a gap between items keeps the last one).
    function setHover(kind, on) {
        if (on) hoverKind = kind;
        else if (hoverKind === kind && !containsMouse) hoverKind = "";
    }
    onContainsMouseChanged: if (!containsMouse) hoverKind = ""
    Process {
        id: topProbe
        command: ["busctl", "--user", "--json=short", "call", "com.benwbooth.treetop", "/treetop", "com.benwbooth.treetop", "Top"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.topData = JSON.parse(JSON.parse(text).data[0]); }
                catch (e) { root.topData = null; }
            }
        }
    }
    Timer {
        interval: 1500; repeat: true; triggeredOnStart: true
        running: root.hoverKind !== ""
        onTriggered: topProbe.running = true
    }

    function fmtTop(kind, v) {
        if (kind === "cpu" || kind === "gpu") return v.toFixed(v < 10 ? 1 : 0) + "%";
        if (kind === "mem" || kind === "vram") return fmtRate(v);
        return fmtRate(v) + "/s";
    }
    readonly property var kindTitle: ({ cpu: "CPU", mem: "Memory", gpu: "GPU", vram: "VRAM", disk: "Disk space by volume", net: "Network", temp: "Temperatures & fans" })
    readonly property var kindColor: ({ cpu: tipPalette.cpu, mem: tipPalette.mem, gpu: tipPalette.gpu, vram: tipPalette.vram, disk: tipPalette.disk, net: tipPalette.net })
    function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function c(color, t) { return "<font color='" + color + "'>" + t + "</font>"; }
    function row(label, color, value, detail) {
        return "<tr><td>" + c(color, "<b>" + label + "</b>") + "</td><td align='right'>&nbsp;<b>" + value + "</b></td><td>&nbsp;&nbsp;"
            + c(Theme.fgDim, detail || "") + "</td></tr>";
    }
    // Every temperature and fan, grouped by device (from the treetop app).
    function sensorsText() {
        const list = topData && topData.sensors ? topData.sensors : null;
        if (!list || !list.length) {
            let t = "<table cellspacing='1'>";
            if (cpuTempC > 0) t += "<tr><td><b>CPU</b></td><td align='right'>&nbsp;&nbsp;" + c(tempColor(cpuTempC), "<b>" + cpuTempC.toFixed(0) + "°C</b>") + "</td></tr>";
            if (gpuTempC > 0) t += "<tr><td><b>GPU</b></td><td align='right'>&nbsp;&nbsp;" + c(tempColor(gpuTempC), "<b>" + gpuTempC.toFixed(0) + "°C</b>") + "</td></tr>";
            return t + "</table><br>" + c(Theme.fgDim, "Open treetop for every sensor and fan.");
        }
        let t = "<table cellspacing='1'>";
        let last = "";
        for (const x of list) {
            const v = x.kind === "fan"
                ? c(tipPalette.net, "<b>" + x.value.toFixed(0) + " rpm</b>")
                : c(tempColor(x.value), "<b>" + x.value.toFixed(0) + "°C</b>");
            t += "<tr><td>" + (x.dev !== last ? "<b>" + esc(x.dev) + "</b>" : "") + "</td><td>&nbsp;&nbsp;"
                + c(Theme.fgDim, esc(x.label)) + "</td><td align='right'>&nbsp;&nbsp;" + v + "</td></tr>";
            last = x.dev;
        }
        return t + "</table>";
    }
    // When the GPU is busier than its programs add up to, say so, and name
    // the programs holding ROCm compute queues (work fdinfo can't see).
    function gpuUnattributedText() {
        const un = topData.gpuUnattributed || 0;
        if (un < 20) return "";
        let t = c(tipPalette.warn, "<b>" + un.toFixed(0) + "%</b> busy isn't from any program listed.");
        const holders = topData.gpuCompute || [];
        if (holders.length) {
            t += "<br>" + c(Theme.fgDim, "Holding ROCm compute queues (not measured per program):") + "<table cellspacing='1'>";
            for (const x of holders)
                t += "<tr><td align='right'>" + c(tipPalette.vram, "<b>" + fmtRate(x.v) + "</b>") + "</td><td>&nbsp;&nbsp;" + esc(x.name)
                    + "</td><td>&nbsp;" + c(Theme.fgDim, x.n > 1 ? "×" + x.n : "") + "</td></tr>";
            t += "</table>";
        } else {
            t += "<br>" + c(Theme.fgDim, "Other users' work (turn on root in treetop) or a stuck GPU job.");
        }
        return t;
    }
    function topText(kind) {
        void tick;
        if (kind === "temp") return sensorsText();
        const head = kindRows(kind) ? "<table cellspacing='1'>" + kindRows(kind) + "</table>" : "";
        // Disk space: which programs fill a disk isn't something to list.
        if (kind === "disk") return volumesText();
        return head + (head ? "<br>" : "") + topList(kind);
    }
    // A text bar for a share (0..1): whole blocks, an eighth block for the
    // remainder, and a dim track (the tooltip's font is monospace).
    function bar(frac, color) {
        const w = 10;
        const f = Math.max(0, Math.min(1, frac || 0)) * w;
        let full = Math.floor(f);
        const part = Math.round((f - full) * 8);
        let s = "█".repeat(full);
        if (part === 8) { s += "█"; full++; }
        else if (part > 0 && full < w) s += "▏▎▍▌▋▊▉"[part - 1];
        const used = full + (part > 0 && part < 8 && full < w ? 1 : 0);
        return c(color, s) + c(Theme.fgDim, "░".repeat(Math.max(0, w - used)));
    }
    // Disk space per volume: used share, used of size, and what's free.
    function volumesText() {
        if (!diskVolumes.length) return c(Theme.fgDim, "No disks found.");
        let t = "<table cellspacing='1'>";
        for (const v of diskVolumes)
            t += "<tr><td>" + c(tipPalette.disk, "<b>" + esc(v.mount) + "</b>") + "</td><td>&nbsp;&nbsp;" + bar(v.used / v.size, tipPalette.disk) + "</td><td align='right'>&nbsp;<b>"
                + pct(100 * v.used / v.size) + "</b></td><td>&nbsp;&nbsp;" + c(Theme.fgDim, fmtBytes(v.used) + " of " + fmtBytes(v.size)
                + " · " + fmtBytes(v.size - v.used) + " free") + "</td></tr>";
        return t + "</table>";
    }
    function topList(kind) {
        if (!topData || !topData[kind]) return c(Theme.fgDim, "Open treetop to see which programs are using this.");
        const list = topData[kind];
        const extra = kind === "gpu" ? gpuUnattributedText() : "";
        if (!list.length) return extra || c(Theme.fgDim, "Nothing is using it right now.");
        // Memory and VRAM: each program's share of the total next to the
        // amount (CPU and GPU are percentages already).
        const total = kind === "mem" ? memTotal
            : kind === "vram" ? gpus.reduce((a, g) => a + (g.vramTotal || 0), 0) : 0;
        // The bar: share of the total; CPU of the whole machine (a program's
        // % is per core), GPU of its busy time. Rates (disk, net) get none.
        const share = x => total > 0 ? x.v / total
            : kind === "cpu" ? x.v / (100 * Math.max(1, cpuCount))
            : kind === "gpu" ? x.v / 100 : -1;
        let t = "<table cellspacing='1'>";
        for (const x of list)
            t += "<tr>" + (share(x) >= 0 ? "<td>" + bar(share(x), kindColor[kind]) + "&nbsp;</td>" : "")
                + "<td align='right'>" + c(kindColor[kind], "<b>" + fmtTop(kind, x.v) + "</b>") + "</td>"
                + (total > 0 ? "<td align='right'>&nbsp;" + c(kindColor[kind], (x.v / total * 100).toFixed(x.v / total < 0.1 ? 1 : 0) + "%") + "</td>" : "")
                + "<td>&nbsp;&nbsp;" + esc(x.name)
                + "</td><td>&nbsp;" + c(Theme.fgDim, x.n > 1 ? "×" + x.n : "") + "</td></tr>";
        t += "</table>";
        if (kind === "net" || kind === "disk")
            t += c(Theme.fgDim, "<br>Other users' processes need root access in treetop.");
        return t + (extra ? "<br>" + extra : "");
    }
    // Short GPU name: "Navi 31 [Radeon RX 7900 XT/...] (TUF Gaming Radeon RX
    // 7900 XTX OC)" -> "Radeon RX 7900 XTX"; "Raphael [Radeon 610M]" -> "Radeon 610M".
    function shortGpuName(n) {
        n = String(n || "");
        const paren = n.match(/\(([^)]*)\)\s*$/);
        if (paren) {
            const m = paren[1].match(/(Radeon|GeForce|Arc|Quadro|RTX|GTX|Intel)[^)]*/);
            if (m) return m[0].replace(/\s+(OC|Gaming|Edition)\b.*$/, "").trim();
        }
        const br = n.match(/\[([^\]]*)\]/);
        if (br) return br[1].split("/")[0].trim();
        return n.length > 28 ? n.slice(0, 27) + "…" : n;
    }
    // The rows for one kind of item ("cpu", "mem", "gpu", "vram", "disk",
    // "net"), with its percentage: the overall tooltip lists them all, an
    // item's own tooltip starts with its row.
    function kindRows(kind) {
        let t = "";
        if (kind === "cpu") t += row("CPU", tipPalette.cpu, pct(cpuUsage), cpuTempC > 0 ? cpuTempC.toFixed(0) + "°C" : "");
        if (kind === "mem") t += row("Memory", tipPalette.mem, pct(memPercent), fmtBytes(memUsed) + " of " + fmtBytes(memTotal));
        if (kind === "gpu" || kind === "vram") {
            for (const k of gpuIndexes) {
                const g = gpuFiles.objectAt(k);
                if (!g) continue;
                const n = gpuIndexes.length > 1 ? "GPU" + (k + 1) : "GPU";
                const name = shortGpuName(g.modelData.name);
                if (kind === "gpu") t += row(n, tipPalette.gpu, pct(g.usage), esc(name) + (g.tempC > 0 ? (name ? " · " : "") + g.tempC.toFixed(0) + "°C" : ""));
                else t += row("VRAM", tipPalette.vram, pct(100 * g.vramUsed / Math.max(1, g.modelData.vramTotal)), fmtBytes(g.vramUsed) + " of " + fmtBytes(g.modelData.vramTotal));
            }
        }
        if (kind === "disk" && diskSize > 0)
            t += row("Disk", tipPalette.disk, pct(diskPercent), fmtBytes(diskUsed) + " of " + fmtBytes(diskSize) + " · " + fmtBytes(diskSize - diskUsed) + " free");
        if (kind === "net") t += row("Network", tipPalette.net, "↓" + fmtRate(netDown), "↑" + fmtRate(netUp) + "/s");
        return t;
    }
    readonly property string summaryText: {
        tick;
        let t = "<table cellspacing='1'>";
        for (const k of ["cpu", "mem", "gpu", "vram", "disk", "net"]) {
            if (k === "vram" && !showVram) continue;
            if (k === "disk" && !showDisk) continue;
            t += kindRows(k);
        }
        return t + "</table><br>" + c(Theme.fgDim, "Click to open treetop · hover an item for its top users");
    }

    PopupWindow {
        id: tip
        anchor.item: root
        // Away from the bar: below it in the top menu bar.
        anchor.edges: root.onTop ? Edges.Bottom : Edges.Top
        anchor.gravity: anchor.edges
        anchor.adjustment: PopupAdjustment.Slide
        // The surface has room for the glass's shadow around the pane.
        readonly property real pad: tipFrame.shadowPad
        // The surface (shadow padding included) stays clear of the bar:
        // overlapping it put the pointer over the tooltip as soon as it
        // showed, the bar lost the hover, and the tooltip fell back to the
        // overall summary or hid (arbor doesn't let pointer input through
        // an empty input region).
        anchor.margins.top: root.onTop ? 4 : -4
        color: "transparent"
        visible: false
        implicitWidth: tipFrame.implicitWidth + 2 * pad
        implicitHeight: tipFrame.implicitHeight + 2 * pad
        mask: Region {}

        readonly property bool want: root.containsMouse && !root.pressed
        onWantChanged: {
            if (want) tipTimer.restart();
            else { tipTimer.stop(); visible = false; }
        }
        Timer {
            id: tipTimer
            interval: Theme.tooltipDelayMs
            onTriggered: tip.visible = tip.want
        }

        GlassFrame {
            id: tipFrame
            x: tip.pad
            y: tip.pad
            width: implicitWidth
            height: implicitHeight
            tint: root.onTop ? Theme.glassMenu : Theme.bgRaised
            radius: Theme.menuRadius
            implicitWidth: tipCol.implicitWidth + 20
            implicitHeight: tipCol.implicitHeight + 16

            Column {
                id: tipCol
                x: 10
                y: 8
                spacing: 4
                Label {
                    text: !root.hoverKind ? "System monitor (treetop)"
                        : root.hoverKind === "temp" ? root.kindTitle.temp
                        : root.hoverKind === "disk" ? root.kindTitle.disk
                        : root.kindTitle[root.hoverKind] + " — top programs"
                    font.weight: Font.DemiBold
                    font.pointSize: Theme.fontSize + 1
                }
                Label {
                    textFormat: Text.RichText
                    elide: Text.ElideNone
                    text: tip.visible ? (root.hoverKind ? root.topText(root.hoverKind) : root.summaryText) : ""
                    font.family: "monospace"
                    font.pointSize: Theme.fontSize * 0.95
                }
            }
        }
    }
}
