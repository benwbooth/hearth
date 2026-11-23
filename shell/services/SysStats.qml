pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// treetop's numbers for the menu bar graphs (bar/SysMonitor.qml), sampled
// once however many graph items show them: CPU, memory, each GPU and its
// VRAM, the system drive, network rates and temperatures, straight from
// /proc and sysfs (amdgpu/hwmon). Histories hold one sample a second.
Singleton {
    id: root

    // Ben's Plasma config: hiddenGpus=1,2,3; the rest are the plasmoid's
    // defaults.
    readonly property int updateRate: 1000
    readonly property int historyLength: 60   // samples (one a second): a minute across the graph
    readonly property var hiddenGpus: ["1", "2", "3"]   // display positions, "0" = GPU1
    readonly property bool hideIdleGpus: true
    // Per-GPU sample objects (busy, vram, temp, hist, vhist), `gpus` order.
    readonly property var gpuFiles: gpuInst

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
        id: gpuInst
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
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
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


}
