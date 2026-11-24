import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../widgets"
import "../.."

// Settings > Printers, like macOS's Printers & Scanners (and in place of
// KDE's printer manager): every CUPS queue with its status, the default
// printer, pause/resume, remove, the print queue; Add Printer finds
// network printers that need no driver (IPP Everywhere, AirPrint) and USB
// printers, takes an IP address or host name, and falls back to a driver
// list for old printers. Each printer's page has a test page and its main
// defaults (paper size, two-sided, colour).
// All CUPS work runs in helpers/hearth-printers (never on the UI thread).
ColumnLayout {
    id: pane
    spacing: 14

    property string page: "list"           // list | add | printer
    property string current: ""             // the printer page's queue
    property var printers: []
    property string defaultName: ""
    property bool loaded: false
    property string listError: ""
    property string status: ""
    property bool statusBad: false
    property string busy: ""                // what's running, for the buttons
    property string confirmRemove: ""
    // "printers:add" opens Add Printer.
    property string arg: ""
    onArgChanged: if (arg === "add") openAdd()

    readonly property var cur: printers.find(p => p.name === current) || null

    function say(msg, bad) { status = msg; statusBad = !!bad; }

    // ---------------------------------------------------------------- helper
    // call(args, cb(lastJsonLine), onLine(eachJsonLine))
    function call(args, cb, onLine) {
        const j = jobComp.createObject(pane, { command: ["hearth-printers"].concat(args), cb: cb || null, onLine: onLine || null });
        j.running = true;
        return j;
    }
    Component {
        id: jobComp
        Process {
            id: job
            property var cb
            property var onLine
            property var last: null
            stdout: SplitParser {
                onRead: line => {
                    let r = null;
                    try { r = JSON.parse(line); } catch (e) { return; }
                    job.last = r;
                    if (job.onLine) job.onLine(r);
                }
            }
            // After the last stdout line has been read.
            onExited: Qt.callLater(() => {
                const r = job.last || { ok: false, error: "hearth-printers didn't answer (is CUPS installed?)." };
                if (job.cb) job.cb(r);
                job.destroy();
            })
        }
    }

    // A poll already under way may predate the last change: ask again
    // once it's done.
    property bool again: false
    function refresh() {
        if (lister.running) { again = true; return; }
        lister.running = true;
    }
    Process {
        id: lister
        command: ["hearth-printers", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(text); } catch (e) {}
                pane.loaded = true;
                if (!r) { pane.listError = "Couldn't ask CUPS for the printers."; return; }
                pane.listError = r.error || "";
                pane.printers = r.printers;
                pane.defaultName = r["default"];
                if (pane.again) { pane.again = false; Qt.callLater(pane.refresh); }
            }
        }
    }
    Component.onCompleted: refresh()
    Timer {
        // Quicker while something prints, so the queue keeps up.
        interval: pane.printers.some(p => p.jobs.length > 0) ? 2000 : 5000
        running: pane.visible
        repeat: true
        onTriggered: pane.refresh()
    }

    // One admin action, then a fresh list.
    function act(args, done, okMsg) {
        busy = args.join(" ");
        say("", false);
        call(args, r => {
            pane.busy = "";
            if (r.ok) { if (okMsg) pane.say(okMsg, false); if (done) done(r); }
            else pane.say(r.error || "That didn't work.", true);
            pane.refresh();
        });
    }

    function stateText(p) {
        if (!p) return "";
        const reasons = p.reasons.length ? p.reasons.join(", ") : "";
        switch (p.state) {
        case "printing": return p.jobs.length > 1 ? "Printing · " + p.jobs.length + " jobs" : "Printing";
        case "paused": return "Paused" + (p.jobs.length ? " · " + p.jobs.length + (p.jobs.length === 1 ? " job waiting" : " jobs waiting") : "");
        case "error": return "Needs attention: " + (p.message || reasons || "the printer reported a problem");
        default: return p.jobs.length ? (p.jobs.length === 1 ? "1 job waiting" : p.jobs.length + " jobs waiting") : (reasons ? "Ready · " + reasons : "Ready");
        }
    }
    function stateColor(p) {
        return !p ? Theme.fgDim : p.state === "error" ? Theme.bad : p.state === "paused" ? Theme.warn : p.state === "printing" ? Theme.accent : Theme.fgDim;
    }
    function iconFor(p) {
        return p.state === "error" ? "printer-error" : p.state === "printing" ? "printer-printing" : "printer";
    }

    function openPrinter(name) {
        current = name;
        confirmRemove = "";
        options = [];
        page = "printer";
        say("", false);
        loadOptions();
    }

    // ---------------------------------------------------------------- list
    Label {
        Layout.fillWidth: true
        visible: pane.status !== ""
        text: pane.status
        color: pane.statusBad ? Theme.bad : Theme.good
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    ColumnLayout {
        visible: pane.page === "list"
        Layout.fillWidth: true
        spacing: 14

        Label {
            Layout.fillWidth: true
            visible: pane.listError !== ""
            text: pane.listError + ". Printing needs the CUPS print service (services.printing.enable in the NixOS configuration)."
            color: Theme.bad
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }

        SettingsGroup {
            Label {
                visible: pane.loaded && pane.printers.length === 0 && pane.listError === ""
                height: 44
                width: parent ? parent.width : 0
                verticalAlignment: Text.AlignVCenter
                text: "No printers yet. Click Add Printer… to find one on your network or plugged in by USB."
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Label {
                visible: !pane.loaded
                height: 44
                verticalAlignment: Text.AlignVCenter
                text: "Asking CUPS…"
                color: Theme.fgDim
            }
            Repeater {
                model: pane.printers
                Column {
                    id: pr
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    SettingsDivider { visible: pr.index > 0 }
                    MouseArea {
                        width: parent.width
                        implicitHeight: row.implicitHeight
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.openPrinter(pr.modelData.name)
                        SettingsRow {
                            id: row
                            width: parent.width
                            label: pr.modelData.info + (pr.modelData.isDefault ? " · Default" : "")
                            note: pane.stateText(pr.modelData)
                            tip: [pr.modelData.make, pr.modelData.location ? "Location: " + pr.modelData.location : "", "Queue name: " + pr.modelData.name].filter(s => s).join("\n")
                            RowLayout {
                                spacing: 6
                                Icon { implicitSize: 24; name: pane.iconFor(pr.modelData); fallback: "printer" }
                                PushButton {
                                    visible: !pr.modelData.isDefault
                                    text: "Make Default"
                                    tooltip: "Apps pick this printer first when you print"
                                    enabled: pane.busy === ""
                                    onClicked: pane.act(["default", pr.modelData.name], null, pr.modelData.info + " is now the default printer.")
                                }
                                PushButton {
                                    text: pr.modelData.state === "paused" ? "Resume" : "Pause"
                                    tooltip: pr.modelData.state === "paused" ? "Start printing waiting jobs again" : "Hold new and waiting jobs until you resume (handy to clear a jam)"
                                    enabled: pane.busy === ""
                                    onClicked: pane.act([pr.modelData.state === "paused" ? "resume" : "pause", pr.modelData.name])
                                }
                                PushButton {
                                    text: "Details…"
                                    tooltip: "Print queue, test page, paper size and other defaults, and removing it"
                                    onClicked: pane.openPrinter(pr.modelData.name)
                                }
                            }
                        }
                    }
                }
            }
        }
        RowLayout {
            PushButton {
                text: "Add Printer…"
                primary: true
                tooltip: "Find a printer on your network or plugged in by USB, or type its address"
                onClicked: pane.openAdd()
            }
        }

        SettingsGroup {
            visible: pane.printers.length > 1
            SettingsRow {
                label: "Default printer"
                note: "The one apps choose first. You can still pick another in each app's Print dialog."
                Dropdown {
                    implicitWidth: 260
                    options: pane.printers.map(p => ({ value: p.name, label: p.info }))
                    value: pane.defaultName
                    enabled: pane.busy === ""
                    onPicked: v => pane.act(["default", v])
                }
            }
        }
    }

    // ---------------------------------------------------------------- printer
    property var options: []
    readonly property var optPaper: options.find(o => o.key === "PageSize") || null
    readonly property var optDuplex: options.find(o => o.key === "Duplex" && o.choices.length > 1) || null
    readonly property var optColor: options.find(o => o.key === "ColorModel" && o.choices.length > 1) || null
    function loadOptions() {
        const name = current;
        call(["options", name], null, r => { if (Array.isArray(r) && pane.current === name) pane.options = r; });
    }
    function setOpt(key, value) {
        act(["setopt", current, key, value], () => pane.loadOptions(), "Saved. New print jobs use it unless you change it in the app.");
    }
    readonly property var paperNames: ({
        Letter: "US Letter", Legal: "US Legal", A4: "A4", A3: "A3", A5: "A5", A6: "A6", B5: "B5 (JIS)",
        Executive: "Executive", Tabloid: "Tabloid", Env10: "Envelope #10", EnvDL: "Envelope DL",
        EnvC5: "Envelope C5", EnvMonarch: "Envelope Monarch", "3x5": "Index card 3×5″", "4x6": "Photo 4×6″", "5x7": "Photo 5×7″"
    })
    function paperLabel(c) {
        const borderless = /\.Borderless$/.test(c);
        const b = c.replace(/\.(Borderless|Fullbleed)$/, "");
        let l = paperNames[b] || b.replace(/^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)(mm|in)?$/, (m, w, h, u) => w + " × " + h + " " + (u || "mm"));
        return borderless ? l + " (borderless)" : l;
    }
    function isGray(c) { return /gray|grey|mono|black|kgray/i.test(c); }

    ColumnLayout {
        visible: pane.page === "printer" && !!pane.cur
        Layout.fillWidth: true
        spacing: 14

        RowLayout {
            PushButton { text: "‹ All Printers"; onClicked: { pane.page = "list"; pane.say("", false); } }
        }

        RowLayout {
            spacing: 14
            Icon { implicitSize: 64; name: pane.cur ? pane.iconFor(pane.cur) : "printer"; fallback: "printer" }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: pane.cur ? pane.cur.info : ""; font.pointSize: Theme.fontSize + 3; font.weight: Font.DemiBold }
                Label { text: pane.stateText(pane.cur); color: pane.stateColor(pane.cur) }
                Label {
                    text: pane.cur && pane.cur.isDefault ? "Default printer" : ""
                    visible: text !== ""
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
            }
        }

        RowLayout {
            spacing: 6
            PushButton {
                text: "Print Test Page"
                tooltip: "Prints one page so you can check the printer works and the colours look right"
                enabled: pane.busy === "" && !!pane.cur && pane.cur.state !== "paused"
                onClicked: pane.act(["testpage", pane.current], null, "Test page sent.")
            }
            PushButton {
                visible: !!pane.cur && !pane.cur.isDefault
                text: "Make Default"
                tooltip: "Apps pick this printer first when you print"
                enabled: pane.busy === ""
                onClicked: pane.act(["default", pane.current])
            }
            PushButton {
                text: pane.cur && pane.cur.state === "paused" ? "Resume" : "Pause"
                tooltip: pane.cur && pane.cur.state === "paused" ? "Start printing waiting jobs again" : "Hold jobs until you resume"
                enabled: pane.busy === ""
                onClicked: pane.act([pane.cur.state === "paused" ? "resume" : "pause", pane.current])
            }
            Item { Layout.fillWidth: true }
            PushButton {
                text: pane.confirmRemove === pane.current ? "Really remove?" : "Remove Printer…"
                destructive: true
                tooltip: "Take this printer off the computer, for every user. Waiting jobs are cancelled. You can add it again later. Asks first."
                enabled: pane.busy === ""
                onClicked: {
                    if (pane.confirmRemove !== pane.current) { pane.confirmRemove = pane.current; return; }
                    const label = pane.cur.info;
                    pane.confirmRemove = "";
                    pane.act(["remove", pane.current], () => { pane.page = "list"; }, label + " was removed.");
                }
            }
        }

        // The queue.
        RowLayout {
            Label { text: "Print queue"; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            PushButton {
                visible: !!pane.cur && pane.cur.jobs.length > 1
                text: "Cancel All"
                destructive: true
                tooltip: "Cancel every job waiting for this printer"
                onClicked: pane.act(["cancel", "all:" + pane.current])
            }
        }
        SettingsGroup {
            Label {
                visible: !!pane.cur && pane.cur.jobs.length === 0
                height: 40
                verticalAlignment: Text.AlignVCenter
                text: "Nothing waiting to print."
                color: Theme.fgDim
            }
            Repeater {
                model: pane.cur ? pane.cur.jobs : []
                Column {
                    id: jb
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    SettingsDivider { visible: jb.index > 0 }
                    SettingsRow {
                        label: jb.modelData.file
                        note: (jb.modelData.active ? "Printing" : "Waiting") + " · " + jb.modelData.size + (jb.modelData.owner ? " · from " + jb.modelData.owner : "")
                        PushButton {
                            text: "Cancel"
                            tooltip: "Stop this job and take it out of the queue"
                            onClicked: pane.act(["cancel", pane.current + "-" + jb.modelData.id])
                        }
                    }
                }
            }
        }

        // Defaults.
        Label { text: "Defaults"; font.weight: Font.DemiBold; visible: pane.optPaper || pane.optDuplex || pane.optColor }
        SettingsGroup {
            visible: !!(pane.optPaper || pane.optDuplex || pane.optColor)
            SettingsRow {
                visible: !!pane.optPaper
                label: "Paper size"
                note: "What apps print on unless you pick another size in the Print dialog."
                Dropdown {
                    implicitWidth: 260
                    options: pane.optPaper ? pane.optPaper.choices.map(c => ({ value: c, label: pane.paperLabel(c) })) : []
                    value: pane.optPaper ? pane.optPaper.default : ""
                    enabled: pane.busy === ""
                    onPicked: v => pane.setOpt("PageSize", v)
                }
            }
            SettingsDivider { visible: !!pane.optPaper && !!pane.optDuplex }
            SettingsRow {
                visible: !!pane.optDuplex
                label: "Two-sided"
                note: "Print on both sides of the paper. Long edge turns pages like a book; short edge like a notepad."
                Segmented {
                    options: pane.optDuplex ? pane.optDuplex.choices.map(c => ({ value: c,
                        label: c === "None" ? "Off" : c === "DuplexNoTumble" ? "Long edge" : c === "DuplexTumble" ? "Short edge" : c })) : []
                    value: pane.optDuplex ? pane.optDuplex.default : ""
                    onPicked: v => pane.setOpt("Duplex", v)
                }
            }
            SettingsDivider { visible: !!pane.optColor && (!!pane.optPaper || !!pane.optDuplex) }
            SettingsRow {
                visible: !!pane.optColor
                label: "Colour"
                note: "Black & white saves colour ink or toner."
                Dropdown {
                    implicitWidth: 200
                    options: pane.optColor ? pane.optColor.choices.map(c => ({ value: c,
                        label: pane.isGray(c) ? (c === "Gray" ? "Black & white" : "Black & white (" + c + ")") : (c === "RGB" || c === "Color" || c === "CMYK" ? "Colour" : "Colour (" + c + ")") })) : []
                    value: pane.optColor ? pane.optColor.default : ""
                    enabled: pane.busy === ""
                    onPicked: v => pane.setOpt("ColorModel", v)
                }
            }
        }

        Label { text: "About this printer"; font.weight: Font.DemiBold }
        SettingsGroup {
            Repeater {
                model: pane.cur ? [
                    { k: "Model", v: pane.cur.make || "Unknown", t: "The printer's make and model as its driver names it" },
                    { k: "Driver", v: pane.cur.driverless ? "Driverless (IPP Everywhere / AirPrint)" : "A printer driver", t: "Driverless printers describe themselves to the computer, so no driver package is needed" },
                    { k: "Location", v: pane.cur.location || "Not set", t: "A note on where the printer is" },
                    { k: "Address", v: pane.cur.uri, t: "How CUPS reaches the printer (its device URI)" },
                    { k: "Queue name", v: pane.cur.name, t: "Its name in CUPS, used by lp and lpr on the command line" },
                    { k: "Shared", v: pane.cur.shared ? "Yes, if printer sharing is on in CUPS" : "No", t: "Whether other computers on the network may print to it through this one" }
                ] : []
                Column {
                    id: inf
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    SettingsDivider { visible: inf.index > 0 }
                    SettingsRow {
                        label: inf.modelData.k
                        tip: inf.modelData.t
                        Label {
                            text: inf.modelData.v
                            color: Theme.fgDim
                            width: Math.min(implicitWidth, 420)
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- add
    property var found: []                  // discover results
    property bool searching: false
    property var probed: null               // add-by-address result
    property bool probing: false
    property var needDriver: null           // { uri, info, location } waiting for a driver
    property var drivers: []
    property bool driversLoading: false
    property string driver: ""

    function openAdd() {
        page = "add";
        needDriver = null;
        probed = null;
        say("", false);
        discover();
    }
    function discover() {
        if (searching) return;
        searching = true;
        found = [];
        call(["discover", "10"], r => { pane.searching = false; if (r.error) pane.say(r.error, true); }, r => {
            if (!r.uri) return;
            // One row per printer: lpstat and lpinfo may both report it.
            const name = (r.info || r.make || r.uri).toLowerCase();
            if (pane.found.some(f => f.uri === r.uri || (f.info || f.make || f.uri).toLowerCase() === name)) return;
            pane.found = pane.found.concat([r]);
        });
    }
    // Already a queue for it? (same address, or the same model's name)
    function added(d) {
        return printers.some(p => p.uri === d.uri || (d.make && p.make && p.make.replace(/\s*-\s*IPP Everywhere.*/, "") === d.make)
                                   || (d.info && p.info === d.info));
    }
    function addFound(d) {
        if (!d.driverless) { pickDriver(d); return; }
        act(["add", d.uri, "everywhere", d.info || d.make || "", d.location || ""], r => {
            pane.openPrinter(r.name);
            pane.say((d.info || d.make || "The printer") + " was added. Try Print Test Page.", false);
        });
    }
    function pickDriver(d) {
        needDriver = d;
        driver = "";
        if (drivers.length === 0 && !driversLoading) {
            driversLoading = true;
            call(["drivers"], r => { pane.driversLoading = false; if (Array.isArray(r)) pane.drivers = r; });
        }
    }
    function probe() {
        const a = addr.text.trim();
        if (!a || probing) return;
        probing = true;
        probed = null;
        say("", false);
        call(["probe", a], r => {
            pane.probing = false;
            if (r.error) pane.say(r.error, true);
            else pane.probed = r;
        });
    }
    function deviceKind(d) {
        return d.uri.startsWith("usb:") ? "USB" : d.uri.startsWith("socket:") || d.uri.startsWith("lpd:") ? "Network (needs a driver)" : "Network";
    }

    ColumnLayout {
        visible: pane.page === "add"
        Layout.fillWidth: true
        spacing: 14

        RowLayout {
            PushButton { text: "‹ All Printers"; onClicked: { pane.page = "list"; pane.say("", false); } }
        }

        RowLayout {
            Label { text: "Printers found"; font.weight: Font.DemiBold }
            Label { text: pane.searching ? "searching…" : ""; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize }
            Item { Layout.fillWidth: true }
            PushButton {
                text: "Search Again"
                enabled: !pane.searching
                tooltip: "Look for printers on the network and on USB again"
                onClicked: pane.discover()
            }
        }
        Label {
            Layout.fillWidth: true
            text: "Printers on your network that speak IPP Everywhere or AirPrint (almost every printer made since 2014) work without a driver. Turn the printer on and connect it to the same network, or plug it in by USB."
            color: Theme.fgDim
            font.pointSize: Theme.smallFontSize
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        SettingsGroup {
            Label {
                visible: pane.found.length === 0
                height: 44
                width: parent ? parent.width : 0
                verticalAlignment: Text.AlignVCenter
                text: pane.searching ? "Looking for printers… (takes about 10 seconds)" : "No printers found. Check it's on, then try its address below."
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Repeater {
                model: pane.found
                Column {
                    id: fd
                    required property var modelData
                    required property int index
                    readonly property bool isAdded: pane.added(modelData)
                    width: parent ? parent.width : 0
                    SettingsDivider { visible: fd.index > 0 }
                    SettingsRow {
                        label: fd.modelData.info || fd.modelData.make || fd.modelData.uri
                        note: [pane.deviceKind(fd.modelData), fd.modelData.driverless ? "no driver needed" : "",
                               fd.modelData.location, fd.isAdded ? "already added" : ""].filter(s => s).join(" · ")
                        tip: fd.modelData.make + "\n" + fd.modelData.uri
                        RowLayout {
                            spacing: 6
                            Icon { implicitSize: 22; name: fd.modelData.uri.startsWith("usb:") ? "drive-removable-media-usb" : "printer"; fallback: "printer" }
                            PushButton {
                                text: fd.modelData.driverless ? "Add" : "Add…"
                                primary: !fd.isAdded
                                enabled: pane.busy === ""
                                tooltip: fd.modelData.driverless ? "Add it now, no driver needed" : "Pick a driver for it, then add it"
                                onClicked: pane.addFound(fd.modelData)
                            }
                            PushButton {
                                visible: fd.modelData.driverless
                                text: "Driver…"
                                enabled: pane.busy === ""
                                tooltip: "Use a specific driver instead (only if printing without one doesn't work right)"
                                onClicked: pane.pickDriver(fd.modelData)
                            }
                        }
                    }
                }
            }
        }

        Label { text: "Add by address"; font.weight: Font.DemiBold }
        SettingsGroup {
            SettingsRow {
                label: "IP address or host name"
                note: "Find it on the printer's own screen or a network report it prints (e.g. 192.168.1.50 or printer.local)."
                RowLayout {
                    spacing: 6
                    TextBox {
                        id: addr
                        implicitWidth: 220
                        placeholder: "192.168.1.50"
                        onAccepted: pane.probe()
                    }
                    PushButton {
                        text: pane.probing ? "Looking…" : "Find"
                        enabled: !pane.probing && addr.text.trim() !== ""
                        tooltip: "Ask that address whether a printer answers"
                        onClicked: pane.probe()
                    }
                }
            }
            SettingsDivider { visible: !!pane.probed }
            SettingsRow {
                visible: !!pane.probed
                label: pane.probed ? (pane.probed.make || pane.probed.info || "Printer at " + addr.text.trim()) : ""
                note: pane.probed ? (pane.probed.driverless ? "Found. No driver needed." : "Found, but it needs a driver: pick one below.") + " " + pane.probed.uri : ""
                PushButton {
                    text: pane.probed && pane.probed.driverless ? "Add" : "Add…"
                    primary: true
                    enabled: pane.busy === ""
                    onClicked: pane.addFound(pane.probed)
                }
            }
        }

        // Driver picker: old printers that don't describe themselves.
        Label { visible: !!pane.needDriver; text: "Choose a driver"; font.weight: Font.DemiBold }
        SettingsGroup {
            visible: !!pane.needDriver
            SettingsRow {
                label: pane.needDriver ? (pane.needDriver.info || pane.needDriver.make || pane.needDriver.uri) : ""
                note: pane.driversLoading ? "Loading the driver list…" : "Search for your printer's make and model. If it isn't listed, a similar model from the same maker often works."
                Dropdown {
                    implicitWidth: 340
                    listWidth: 460
                    searchable: true
                    placeholder: pane.driversLoading ? "Loading…" : "Choose a driver…"
                    enabled: !pane.driversLoading
                    options: pane.drivers.map(d => ({ value: d.model, label: d.name }))
                    value: pane.driver
                    onPicked: v => pane.driver = v
                }
            }
            SettingsDivider {}
            RowLayout {
                width: parent ? parent.width : 0
                height: 44
                Item { Layout.fillWidth: true }
                PushButton { text: "Cancel"; onClicked: pane.needDriver = null }
                PushButton {
                    text: "Add Printer"
                    primary: true
                    enabled: pane.driver !== "" && pane.busy === ""
                    tooltip: "Add the printer with the chosen driver"
                    onClicked: {
                        const d = pane.needDriver;
                        // Named after the printer, or else the driver's model ("HP LaserJet 4000").
                        const drv = pane.drivers.find(x => x.model === pane.driver);
                        const label = d.info || d.make || (drv ? drv.name.replace(/\s+-\s+.*$/, "").replace(/,.*$/, "") : "");
                        pane.act(["add", d.uri, pane.driver, label, d.location || ""], r => {
                            pane.needDriver = null;
                            pane.openPrinter(r.name);
                            pane.say("Added. Try Print Test Page.", false);
                        });
                    }
                }
            }
        }
    }
}
