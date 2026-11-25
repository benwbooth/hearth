import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// treetop's panel widget, KStats-style: CPU, memory, the main GPU and its
// VRAM as small history graphs with the value inside, network rates, and
// CPU/GPU temperatures. Ported from ~/src/treetop/plasmoid; the numbers come
// straight from /proc and sysfs (amdgpu/hwmon) instead of ksystemstats.
// Clicking shows/hides the treetop window; hovering an item asks treetop
// (over D-Bus) which programs are using it.
MouseArea {
    id: root

    // ---- what it shows ----------------------------------------------------
    // Which graphs, in this order of kinds: "cpu", "mem", "gpu", "vram",
    // "disk", "net", "temp". The classic panel shows them all in one item;
    // the menu bar makes one item per graph (Settings > Menu Bar).
    property var kinds: ["cpu", "mem", "gpu", "vram", "disk", "net", "temp"]
    // Menu bar: "graph" (label, value and history) or "number" (label over
    // value, no graph).
    property string style: "graph"
    // Room around the graphs.
    property real padding: 8
    function has(k) { return kinds.indexOf(k) >= 0; }
    readonly property bool showCpu: has("cpu")
    readonly property bool showMem: has("mem")
    readonly property bool showGpu: has("gpu")
    readonly property bool showVram: has("vram")
    readonly property bool showDisk: has("disk")
    readonly property bool showNetwork: has("net")
    readonly property bool showTemps: has("temp")
    readonly property bool showGraph: !(blend && style === "number")
    readonly property real graphWidth: 0.9

    // The numbers (services/SysStats.qml samples them once for every item).
    readonly property var gpus: SysStats.gpus
    readonly property var gpuFiles: SysStats.gpuFiles
    readonly property int tick: SysStats.tick
    readonly property real cpuUsage: SysStats.cpuUsage
    readonly property real cpuTempC: SysStats.cpuTempC
    readonly property int cpuCount: SysStats.cpuCount
    readonly property real memPercent: SysStats.memPercent
    readonly property real memUsed: SysStats.memUsed
    readonly property real memTotal: SysStats.memTotal
    readonly property real netDown: SysStats.netDown
    readonly property real netUp: SysStats.netUp
    readonly property var hCpu: SysStats.hCpu
    readonly property var hMem: SysStats.hMem
    readonly property real diskPercent: SysStats.diskPercent
    readonly property real diskUsed: SysStats.diskUsed
    readonly property real diskSize: SysStats.diskSize
    readonly property var hDisk: SysStats.hDisk
    readonly property var diskVolumes: SysStats.diskVolumes
    readonly property var gpuIndexes: SysStats.gpuIndexes
    readonly property real gpuTempC: SysStats.gpuTempC
    // One line for the menu bar's overflow dropdown: this item's values.
    readonly property string compactText: {
        tick;
        const t = [];
        if (showCpu) t.push("CPU " + pct(cpuUsage));
        if (showMem) t.push("Mem " + pct(memPercent));
        for (const k of (showGpu || showVram) ? gpuIndexes : []) {
            const g = gpuFiles.objectAt(k);
            if (!g) continue;
            const n = gpuIndexes.length > 1 ? String(k + 1) : "";
            if (showGpu) t.push("GPU" + n + " " + pct(g.usage));
            if (showVram) t.push("VRAM" + n + " " + pct(100 * g.vramUsed / Math.max(1, g.modelData.vramTotal)));
        }
        if (showDisk && diskSize > 0) t.push("Disk " + pct(diskPercent));
        if (showNetwork) t.push("↓" + fmtRate(netDown) + " ↑" + fmtRate(netUp));
        if (showTemps && cpuTempC > 0) t.push("CPU " + cpuTempC.toFixed(0) + "°");
        if (showTemps && gpuTempC > 0) t.push("GPU " + gpuTempC.toFixed(0) + "°");
        return t.join("  ·  ");
    }

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

    implicitWidth: strip.implicitWidth > 0 ? strip.implicitWidth + padding : 0
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
    // In the tooltip: the bar's foreground (black over a bright wallpaper)
    // is unreadable on the tooltip's glass, which follows the theme.
    function tipTempColor(t) { return t >= 80 ? "#e05a4f" : (t >= 60 ? "#e3c25a" : blend ? Theme.fg : "#43c96b"); }
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
            visible: root.showGraph
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
            visible: root.showCpu
            h: root.h; label: "CPU"; kind: "cpu"; color: root.palette.cpu
            value: root.pct(root.cpuUsage)
            history: root.hCpu
        }
        KStat {
            visible: root.showMem
            h: root.h; label: "MEM"; kind: "mem"; color: root.palette.mem
            value: root.pct(root.memPercent)
            history: root.hMem
        }
        Repeater {
            model: root.showGpu || root.showVram ? root.gpuIndexes : []
            RowLayout {
                id: gpuItem
                required property int modelData
                readonly property var g: { root.tick; return gpuFiles.objectAt(modelData); }
                readonly property string n: root.gpuIndexes.length > 1 ? String(modelData + 1) : ""
                spacing: Math.round(root.h * 0.16)
                KStat {
                    visible: root.showGpu
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
            if (cpuTempC > 0) t += "<tr><td><b>CPU</b></td><td align='right'>&nbsp;&nbsp;" + c(tipTempColor(cpuTempC), "<b>" + cpuTempC.toFixed(0) + "°C</b>") + "</td></tr>";
            if (gpuTempC > 0) t += "<tr><td><b>GPU</b></td><td align='right'>&nbsp;&nbsp;" + c(tipTempColor(gpuTempC), "<b>" + gpuTempC.toFixed(0) + "°C</b>") + "</td></tr>";
            return t + "</table><br>" + c(Theme.fgDim, "Open treetop for every sensor and fan.");
        }
        let t = "<table cellspacing='1'>";
        let last = "";
        for (const x of list) {
            const v = x.kind === "fan"
                ? c(tipPalette.net, "<b>" + x.value.toFixed(0) + " rpm</b>")
                : c(tipTempColor(x.value), "<b>" + x.value.toFixed(0) + "°C</b>");
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
    // A hovered item's tooltip: a head (its overall row, or a message),
    // rows drawn over translucent bars, and a foot (notes). Each row is
    // {cells: [{t, color, bold, right}], frac (0..1, or -1 for no bar), bar}.
    function tipModel(kind) {
        void tick;
        if (kind === "temp") return { head: sensorsText(), rows: [], foot: "" };
        // Disk space: which programs fill a disk isn't something to list,
        // so one row per volume instead.
        if (kind === "disk") return volumesModel();
        const head = kindRows(kind) ? "<table cellspacing='1'>" + kindRows(kind) + "</table>" : "";
        const m = topModel(kind);
        return { head: head + (m.head ? (head ? "<br>" : "") + m.head : ""), rows: m.rows, foot: m.foot };
    }
    // Cells padded to their column's width (the font is monospace), so the
    // rows line up although each is its own item.
    function padRows(rows) {
        const w = [];
        for (const r of rows)
            r.cells.forEach((cell, i) => { w[i] = Math.max(w[i] || 0, String(cell.t).length); });
        return rows.map(r => ({
            frac: r.frac,
            bar: r.bar,
            html: r.cells.map((cell, i) => {
                const pad = "&nbsp;".repeat(w[i] - String(cell.t).length);
                let t = esc(cell.t);
                if (cell.bold) t = "<b>" + t + "</b>";
                if (cell.color) t = c(cell.color, t);
                return cell.right ? pad + t : t + pad;
            }).join("&nbsp;&nbsp;")
        }));
    }
    // Disk space per volume: its bar is the used share.
    function volumesModel() {
        if (!diskVolumes.length) return { head: c(Theme.fgDim, "No disks found."), rows: [], foot: "" };
        return {
            head: "",
            rows: padRows(diskVolumes.map(v => ({
                frac: v.used / v.size,
                bar: treetopPalette.disk,
                cells: [
                    { t: v.mount, color: tipPalette.disk, bold: true },
                    { t: pct(100 * v.used / v.size), bold: true, right: true },
                    { t: fmtBytes(v.used) + " of " + fmtBytes(v.size) + " · " + fmtBytes(v.size - v.used) + " free", color: Theme.fgDim }
                ]
            }))),
            foot: ""
        };
    }
    function topModel(kind) {
        if (!topData || !topData[kind]) return { head: c(Theme.fgDim, "Open treetop to see which programs are using this."), rows: [], foot: "" };
        const list = topData[kind];
        const extra = kind === "gpu" ? gpuUnattributedText() : "";
        if (!list.length) return { head: extra || c(Theme.fgDim, "Nothing is using it right now."), rows: [], foot: "" };
        // Memory and VRAM: each program's share of the total next to the
        // amount (CPU and GPU are percentages already).
        const total = kind === "mem" ? memTotal
            : kind === "vram" ? gpus.reduce((a, g) => a + (g.vramTotal || 0), 0) : 0;
        // The bar: share of the total; CPU of the whole machine (a program's
        // % is per core), GPU of its busy time. Rates (disk, net) get none.
        const share = x => total > 0 ? x.v / total
            : kind === "cpu" ? x.v / (100 * Math.max(1, cpuCount))
            : kind === "gpu" ? x.v / 100 : -1;
        const rows = padRows(list.map(x => {
            const cells = [{ t: fmtTop(kind, x.v), color: kindColor[kind], bold: true, right: true }];
            if (total > 0) cells.push({ t: (x.v / total * 100).toFixed(x.v / total < 0.1 ? 1 : 0) + "%", color: kindColor[kind], right: true });
            cells.push({ t: x.name });
            cells.push({ t: x.n > 1 ? "×" + x.n : "", color: Theme.fgDim });
            return { frac: share(x), bar: treetopPalette[kind], cells: cells };
        }));
        let foot = "";
        if (kind === "net" || kind === "disk")
            foot = c(Theme.fgDim, "Other users' processes need root access in treetop.");
        if (extra) foot += (foot ? "<br>" : "") + extra;
        return { head: "", rows: rows, foot: foot };
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
            if (!has(k)) continue;
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

        // What it shows: the hovered item's model, or the overall summary.
        // Built while the delay runs, so it shows at its final size: built
        // only once visible, it showed empty and grew, a flicker.
        readonly property var model: !want && !visible ? ({ head: "", rows: [], foot: "" })
            : root.hoverKind ? root.tipModel(root.hoverKind)
            : ({ head: root.summaryText, rows: [], foot: "" })
        readonly property bool want: root.containsMouse && !root.pressed
        // Fades in and out, as hearth's other tooltips (widgets/Tooltip):
        // shown at once, the glass's blur reached the compositor a frame
        // after the pane, a flicker.
        property bool shown: false
        onShownChanged: if (shown) visible = true
        onWantChanged: {
            if (want) tipTimer.restart();
            else { tipTimer.stop(); shown = false; }
        }
        Timer {
            id: tipTimer
            interval: Theme.tooltipDelayMs
            onTriggered: tip.shown = tip.want
        }

        GlassFrame {
            id: tipFrame
            x: tip.pad
            y: tip.pad
            width: implicitWidth
            height: implicitHeight
            tint: root.onTop ? Theme.glassMenu : Theme.bgRaised
            radius: Theme.menuRadius
            opacity: tip.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: tip.shown ? 110 : 160; easing.type: Easing.OutCubic } }
            onOpacityChanged: if (opacity === 0 && !tip.shown) tip.visible = false
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
                    visible: text !== ""
                    textFormat: Text.RichText
                    elide: Text.ElideNone
                    text: tip.model.head
                    font.family: "monospace"
                    font.pointSize: Theme.fontSize * 0.95
                }
                // One item per row: a faint track, the share as a
                // translucent rounded bar behind the text, then the text.
                Column {
                    visible: tip.model.rows.length > 0
                    spacing: 2
                    Repeater {
                        model: tip.model.rows
                        Item {
                            id: tipRow
                            required property var modelData
                            readonly property bool hasBar: modelData.frac >= 0
                            width: rowText.implicitWidth + 12
                            height: rowText.implicitHeight + 4
                            Rectangle {
                                visible: tipRow.hasBar
                                anchors.fill: parent
                                radius: 4
                                color: Qt.alpha(tipRow.modelData.bar, 0.08)
                            }
                            Rectangle {
                                visible: tipRow.hasBar && tipRow.modelData.frac > 0
                                width: Math.max(height * 0.5, parent.width * Math.min(1, tipRow.modelData.frac))
                                height: parent.height
                                radius: 4
                                color: Qt.alpha(tipRow.modelData.bar, 0.32)
                            }
                            Label {
                                id: rowText
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.RichText
                                text: tipRow.modelData.html
                                font.family: "monospace"
                                font.pointSize: Theme.fontSize * 0.95
                            }
                        }
                    }
                }
                Label {
                    visible: text !== ""
                    textFormat: Text.RichText
                    elide: Text.ElideNone
                    text: tip.model.foot
                    font.family: "monospace"
                    font.pointSize: Theme.fontSize * 0.95
                }
            }
        }
    }
}
