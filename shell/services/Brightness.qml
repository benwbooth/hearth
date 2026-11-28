pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Display brightness and night light.
//
// External monitors go over DDC/CI (ddcutil, VCP 0x10); laptop panels go
// through /sys/class/backlight, written via logind's SetBrightness so no
// udev rule is needed. ddcutil takes 0.1-1 s per call, so each display reads
// once at startup (and when asked to refresh) and keeps at most one write in
// flight: dragging a slider only ever sends the latest value.
//
// Night light: 4500 K from 19:00 to 07:00, like KDE's Night Color.
// Hyprland: the hyprsunset daemon keeps that schedule itself; the toggle and
// slider override it live through `hyprctl hyprsunset`.
// arbor: hearth runs it — gammastep holds the temperature (wlr gamma
// control) while night light is on; the schedule timer below flips it.
//
// HEARTH_BRIGHTNESS_DRYRUN=1 logs DDC/backlight writes instead of sending them.
Singleton {
    id: root

    // Device objects (see `component Device` below), DDC first.
    property list<QtObject> displays: []
    readonly property bool available: displays.length > 0
    // The first display's level, for the bar icon.
    readonly property int percent: available ? displays[0].value : 0
    readonly property bool dryRun: Quickshell.env("HEARTH_BRIGHTNESS_DRYRUN") === "1"

    property bool nightLight: scheduledNight()
    property int temperature: 4500
    readonly property int minTemperature: 2500
    readonly property int maxTemperature: 6500

    // Emitted for user-initiated changes (keys, scroll, IPC) so the OSD can
    // show them. Startup reads don't emit it.
    signal osd(int percent)

    function set(device, pct, showOsd) {
        if (!device) return;
        device.set(pct);
        if (showOsd) root.osd(device.value);
    }
    function setAll(pct, showOsd) {
        for (const d of root.displays) d.set(pct);
        if (showOsd && root.available) root.osd(root.displays[0].value);
    }
    function step(delta, showOsd) {
        for (const d of root.displays) d.set(d.value + delta);
        if (showOsd && root.available) root.osd(root.displays[0].value);
    }
    function refresh() {
        for (const d of root.displays) d.read();
    }

    function setNightLight(on) {
        root.nightLight = on;
        // Kept until the schedule next changes, across shell restarts (each
        // hearth update restarts the shell, which used to switch a night
        // light you had turned off straight back on).
        root.overrideUntil = on === root.scheduledNight() ? 0 : root.nextScheduleChange();
        root.applyNightLight();
        root.saveState();
    }
    function setTemperature(k) {
        root.temperature = Math.max(root.minTemperature, Math.min(root.maxTemperature, Math.round(k / 100) * 100));
        tempDebounce.restart();
        root.saveState();
    }

    IpcHandler {
        target: "brightness"
        function up(): void { root.step(5, true); }
        function down(): void { root.step(-5, true); }
        function set(percent: int): void { root.setAll(percent, true); }
        function get(): string { return root.displays.map(d => `${d.name}: ${d.value}%`).join("\n"); }
        function refresh(): void { root.refresh(); }
        function toggleNightLight(): void { root.setNightLight(!root.nightLight); }
        function nightLightOn(): void { root.setNightLight(true); }
        function nightLightOff(): void { root.setNightLight(false); }
        function setTemperature(kelvin: int): void { root.setTemperature(kelvin); }
    }

    // --- Discovery ---------------------------------------------------------

    property var ddcInfo: []       // [{ bus, connector, model }]
    property var backlightInfo: [] // [{ device }]

    Process {
        id: detect
        command: ["ddcutil", "detect", "--brief"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let cur = null;
                for (const raw of text.split("\n")) {
                    const line = raw.trim();
                    if (/^Display \d+/.test(line)) { cur = { bus: -1, connector: "", model: "" }; out.push(cur); }
                    else if (/^Invalid display/.test(line) || /^Phantom display/.test(line)) cur = null;
                    else if (cur) {
                        let m;
                        if ((m = line.match(/^I2C bus:\s*\/dev\/i2c-(\d+)/))) cur.bus = parseInt(m[1]);
                        else if ((m = line.match(/^DRM[ _]connector:\s*(?:card\d+-)?(\S+)/))) cur.connector = m[1];
                        else if ((m = line.match(/^Monitor:\s*[^:]*:([^:]*):/))) cur.model = m[1].trim();
                    }
                }
                root.ddcInfo = out.filter(d => d.bus >= 0);
            }
        }
    }

    Process {
        id: listBacklights
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.backlightInfo = text.split("\n").filter(s => s).map(s => ({ device: s }))
        }
    }

    Instantiator {
        id: ddcInst
        model: root.ddcInfo
        delegate: Device {
            required property var modelData
            kind: "ddc"
            bus: modelData.bus
            name: modelData.connector || ("i2c-" + modelData.bus)
            model: modelData.model
        }
        onObjectAdded: root.collect()
        onObjectRemoved: root.collect()
    }
    Instantiator {
        id: blInst
        model: root.backlightInfo
        delegate: Device {
            required property var modelData
            kind: "backlight"
            device: modelData.device
            name: modelData.device
            model: "Built-in display"
        }
        onObjectAdded: root.collect()
        onObjectRemoved: root.collect()
    }
    function collect() {
        const a = [];
        for (let i = 0; i < ddcInst.count; i++) if (ddcInst.objectAt(i)) a.push(ddcInst.objectAt(i));
        for (let i = 0; i < blInst.count; i++) if (blInst.objectAt(i)) a.push(blInst.objectAt(i));
        root.displays = a;
    }

    // One display. `value` is 0-100 and updates immediately on set(); the
    // hardware catches up with the latest value.
    component Device: Scope {
        id: dev
        property string kind: "ddc"
        property int bus: -1
        property string device: ""
        property string name: ""
        property string model: ""
        property int value: 0
        property int max: 100
        property bool ready: false
        property string error: ""

        property int wanted: -1   // raw value still to be written
        property int written: -1  // raw value last written

        function read() {
            if (writer.running) return;
            if (dev.kind === "ddc") reader.running = true;
            else { blMax.reload(); blCur.reload(); }
        }
        function set(pct) {
            pct = Math.max(dev.kind === "backlight" ? 1 : 0, Math.min(100, Math.round(pct)));
            dev.value = pct;
            dev.wanted = Math.round(pct * dev.max / 100);
            dev.flush();
        }
        function flush() {
            if (writer.running || dev.wanted < 0 || dev.wanted === dev.written) return;
            const raw = dev.wanted;
            dev.written = raw;
            let cmd;
            if (dev.kind === "ddc")
                cmd = ["ddcutil", "--bus", String(dev.bus), "--noverify", "setvcp", "10", String(raw)];
            else
                cmd = ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                       "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", dev.device, String(raw)];
            if (root.dryRun) {
                console.info("hearth brightness (dry run):", cmd.join(" "));
                cmd = ["sleep", "0.3"];
            }
            writer.command = cmd;
            writer.running = true;
        }

        Component.onCompleted: read()

        Process {
            id: reader
            command: ["ddcutil", "--bus", String(dev.bus), "getvcp", "10", "--brief"]
            stdout: StdioCollector {
                onStreamFinished: {
                    // "VCP 10 C <current> <max>"
                    const m = text.match(/VCP\s+10\s+C\s+(\d+)\s+(\d+)/);
                    if (m) {
                        dev.max = Math.max(1, parseInt(m[2]));
                        dev.written = parseInt(m[1]);
                        dev.value = Math.round(parseInt(m[1]) * 100 / dev.max);
                        dev.ready = true;
                        dev.error = "";
                    } else {
                        dev.error = text.trim() || "No reply over DDC/CI";
                    }
                }
            }
            stderr: StdioCollector {
                onStreamFinished: if (text.trim()) dev.error = text.trim()
            }
        }

        Process {
            id: writer
            stderr: StdioCollector {
                onStreamFinished: if (text.trim()) console.warn("hearth brightness:", dev.name, text.trim())
            }
            onExited: (code, status) => dev.flush()
        }

        FileView {
            id: blMax
            path: dev.kind === "backlight" ? `/sys/class/backlight/${dev.device}/max_brightness` : ""
            printErrors: false
            onLoaded: dev.max = Math.max(1, parseInt(text()))
        }
        FileView {
            id: blCur
            path: dev.kind === "backlight" ? `/sys/class/backlight/${dev.device}/brightness` : ""
            printErrors: false
            onLoaded: {
                dev.written = parseInt(text());
                dev.value = Math.round(dev.written * 100 / dev.max);
                dev.ready = true;
            }
        }
    }

    // --- Night light -------------------------------------------------------

    // Settings > Displays > Night Shift: Off (only the switch turns it on)
    // or a schedule from/to (hours). It used to be fixed at 19:00-07:00, so
    // turning it off only lasted until the evening.
    readonly property var cfg: Settings.nightShift || ({})
    readonly property bool scheduleOn: cfg.schedule === "custom"
    readonly property int nightStartHour: cfg.from !== undefined ? cfg.from : 19
    readonly property int nightEndHour: cfg.to !== undefined ? cfg.to : 7
    function scheduledNight() {
        if (!root.scheduleOn) return false;
        const h = new Date().getHours();
        return root.nightStartHour <= root.nightEndHour
            ? h >= root.nightStartHour && h < root.nightEndHour
            : h >= root.nightStartHour || h < root.nightEndHour;
    }
    // When a manual on/off ends (ms since the epoch): the schedule's next
    // switch; with no schedule, switched on lasts until the next morning
    // (the "to" hour), like macOS's "Turn On Until Tomorrow".
    function nextScheduleChange() {
        const d = new Date();
        d.setMinutes(0, 0, 0);
        do d.setHours(d.getHours() + 1);
        while (d.getHours() !== root.nightEndHour && !(root.scheduleOn && d.getHours() === root.nightStartHour));
        return d.getTime();
    }
    // The schedule changed in Settings: follow it (a manual choice ends).
    onScheduleOnChanged: followSchedule()
    onNightStartHourChanged: followSchedule()
    onNightEndHourChanged: followSchedule()
    function followSchedule() {
        if (!root.stateRead) return;
        root.overrideUntil = 0;
        const now = root.scheduledNight();
        if (now !== root.nightLight) {
            root.nightLight = now;
            root.applyNightLight();
        }
        root.saveState();
    }
    // A manual on/off lasts until then (0: following the schedule).
    property real overrideUntil: 0
    // Nothing is applied before the saved state is read.
    property bool stateRead: false

    function applyNightLight() {
        if (Compositor.isArbor) {
            // Restart with the new temperature (or stop).
            gammastep.running = false;
            gammastep.command = ["gammastep", "-P", "-O", String(root.temperature)];
            gammastep.running = root.nightLight;
            return;
        }
        Quickshell.execDetached(root.nightLight
            ? ["hyprctl", "hyprsunset", "temperature", String(root.temperature)]
            : ["hyprctl", "hyprsunset", "identity"]);
    }
    Process { id: gammastep }
    function stateReady() {
        if (root.stateRead) return;
        root.stateRead = true;
        if (Compositor.isArbor) root.applyNightLight();
    }

    Timer {
        id: tempDebounce
        interval: 150
        onTriggered: if (root.nightLight) root.applyNightLight()
    }

    // Follow the schedule's flips so the switch matches the screen.
    Timer {
        interval: 60000
        running: true
        repeat: true
        property bool last: root.scheduledNight()
        onTriggered: {
            // A manual choice runs out (with no schedule: off the next morning).
            if (root.overrideUntil > 0 && Date.now() >= root.overrideUntil) {
                root.overrideUntil = 0;
                const s = root.scheduledNight();
                if (s !== root.nightLight) {
                    root.nightLight = s;
                    if (Compositor.isArbor) root.applyNightLight();
                }
                root.saveState();
            }
            const now = root.scheduledNight();
            if (now !== last) {
                last = now;
                root.overrideUntil = 0;
                root.nightLight = now;
                if (Compositor.isArbor) root.applyNightLight();
                root.saveState();
            }
        }
    }

    function saveState() {
        const s = { temperature: root.temperature };
        if (root.overrideUntil > Date.now()) s.override = { on: root.nightLight, until: root.overrideUntil };
        state.setText(JSON.stringify(s, null, 2));
    }

    FileView {
        id: state
        path: Quickshell.statePath("brightness.json")
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                if (s.temperature) root.temperature = s.temperature;
                if (s.override && s.override.until > Date.now()) {
                    root.overrideUntil = s.override.until;
                    root.nightLight = !!s.override.on;
                }
            } catch (e) {}
            root.stateReady();
        }
        onLoadFailed: root.stateReady()
    }
}
