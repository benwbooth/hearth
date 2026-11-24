import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../widgets"
import "../../services"
import "../.."

// Print queue, like Plasma's printer tray icon: shown while jobs are queued
// or a printer is stopped. The popup lists each printer's queue with cancel
// buttons; finished and failed jobs raise a notification.
Indicator {
    id: root
    readonly property var jobs: printers.reduce((a, p) => a.concat(p.jobs), [])
    readonly property var stopped: printers.filter(p => p.stopped)
    icon: stopped.length > 0 ? "printer-error" : jobs.length > 0 ? "printer-printing" : "printer"
    iconFallback: "printer"
    shown: jobs.length > 0 || stopped.length > 0
    tooltip: jobs.length > 0 ? (jobs.length === 1 ? "1 print job" : jobs.length + " print jobs")
           : stopped.length > 0 ? stopped[0].name + " is stopped" : "Printers"
    tooltipSub: jobs.map(j => (j.active ? "Printing: " : "Waiting: ") + j.file).join("\n")

    // [{ name, state, stopped, isDefault, jobs: [{ id, printer, rank, active, owner, file, size }] }]
    property var printers: []
    // Job ids seen last poll -> { printer, file }, to notify when they leave.
    property var lastJobs: ({})
    property string error: ""

    function fmtSize(s) {
        let b = parseInt(s);
        if (isNaN(b)) return s || "";
        const u = ["B", "KiB", "MiB", "GiB"];
        let i = 0;
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
        return (i === 0 || b >= 100 ? Math.round(b) : b.toFixed(1)) + " " + u[i];
    }

    function parse(text) {
        const ps = [];
        const byName = {};
        let def = "";
        for (const line of text.split("\n")) {
            const f = line.split("\t");
            if (f[0] === "D") def = f[1];
            else if (f[0] === "P") {
                const st = f[2] || "";
                const p = { name: f[1], state: st, stopped: /disabled/.test(st), isDefault: false, jobs: [] };
                ps.push(p);
                byName[p.name] = p;
            } else if (f[0] === "J" && byName[f[1]]) {
                byName[f[1]].jobs.push({
                    printer: f[1], rank: f[2], active: f[2] === "active",
                    owner: f[3], id: f[4], file: f[5] || "(untitled)", size: fmtSize(f[6])
                });
            }
        }
        for (const p of ps) p.isDefault = p.name === def;
        root.printers = ps;

        // Jobs that left the queue: done if CUPS lists them as completed.
        const now = {};
        for (const p of ps) for (const j of p.jobs) now[j.id] = { printer: p.name, file: j.file };
        const gone = Object.keys(root.lastJobs).filter(id => !now[id]);
        if (gone.length > 0) {
            completed.pending = gone.map(id => Object.assign({ id: id }, root.lastJobs[id]));
            completed.running = true;
        }
        root.lastJobs = now;
    }

    function notify(summary, body, icon) {
        Quickshell.execDetached(["notify-send", "-a", "Printers", "-i", icon, summary, body]);
    }

    // One pass over every queue: "D\tdefault", "P\tname\tstate line",
    // "J\tprinter\trank\towner\tjob\tfile\tsize" (from lpq, which has file names).
    Process {
        id: poll
        command: ["sh", "-c", `
            printf 'D\\t%s\\n' "$(lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p')"
            for p in $(lpstat -e 2>/dev/null); do
                printf 'P\\t%s\\t%s\\n' "$p" "$(lpstat -p "$p" 2>/dev/null | head -1)"
                lpq -P "$p" 2>/dev/null | awk -v p="$p" 'NR > 2 && NF >= 5 {
                    file = ""; for (i = 4; i <= NF - 2; i++) file = file (file ? " " : "") $i
                    printf "J\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s %s\\n", p, $1, $2, $3, file, $(NF-1), $NF }'
            done`]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
    Timer {
        // Quick while something's printing or the popup is open.
        interval: root.jobs.length > 0 || root.popup.open ? 2000 : 15000
        running: true
        repeat: true
        onTriggered: if (!poll.running) poll.running = true
    }

    Process {
        id: completed
        property var pending: []
        command: ["lpstat", "-W", "completed", "-o"]
        stdout: StdioCollector {
            onStreamFinished: {
                const done = text.split("\n").map(l => l.split(/\s+/)[0]);
                for (const j of completed.pending) {
                    const ok = done.some(d => d === j.printer + "-" + j.id);
                    if (ok) root.notify("Printed", `${j.file} on ${j.printer}`, "printer");
                    else root.notify("Print job ended", `${j.file} on ${j.printer} was cancelled or failed`, "printer-error");
                }
                completed.pending = [];
            }
        }
    }

    Process {
        id: action
        stderr: StdioCollector { id: actionErr }
        onExited: code => {
            root.error = code === 0 ? "" : (actionErr.text.trim() || "Failed (exit " + code + ")");
            if (!poll.running) poll.running = true;
        }
    }
    function run(cmd) { if (!action.running) { action.command = cmd; action.running = true; } }

    popupContent: ColumnLayout {
        spacing: 10

        Label {
            text: "Printers"
            font.weight: Font.DemiBold
            Layout.minimumWidth: 380
        }

        Repeater {
            model: root.printers
            delegate: ColumnLayout {
                id: pr
                required property var modelData
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Icon {
                        implicitSize: 32
                        name: pr.modelData.stopped ? "printer-error" : "printer"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label {
                            Layout.fillWidth: true
                            text: pr.modelData.name.replace(/_/g, " ") + (pr.modelData.isDefault ? "  (default)" : "")
                        }
                        Label {
                            Layout.fillWidth: true
                            text: pr.modelData.stopped ? "Stopped"
                                : pr.modelData.jobs.length > 0 ? (pr.modelData.jobs.length === 1 ? "1 job" : pr.modelData.jobs.length + " jobs")
                                : "Idle"
                            color: pr.modelData.stopped ? Theme.warn : Theme.fgDim
                            font.pointSize: Theme.smallFontSize
                        }
                    }
                    BarButton {
                        implicitHeight: 30
                        visible: pr.modelData.jobs.length > 1
                        icon: "edit-clear-all"
                        tooltip: "Cancel all jobs"
                        onClicked: root.run(["cancel", "-a", pr.modelData.name])
                    }
                }

                Repeater {
                    model: pr.modelData.jobs
                    delegate: RowLayout {
                        id: job
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 40
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                Layout.fillWidth: true
                                text: job.modelData.file
                            }
                            Label {
                                Layout.fillWidth: true
                                text: (job.modelData.active ? "Printing" : "Waiting") + " · " + job.modelData.size
                                    + (job.modelData.owner ? " · " + job.modelData.owner : "")
                                color: job.modelData.active ? Theme.accent : Theme.fgDim
                                font.pointSize: Theme.smallFontSize
                            }
                        }
                        BarButton {
                            implicitHeight: 28
                            icon: "process-stop"
                            tooltip: "Cancel"
                            onClicked: root.run(["cancel", job.modelData.printer + "-" + job.modelData.id])
                        }
                    }
                }
            }
        }

        Label {
            visible: root.error !== ""
            Layout.fillWidth: true
            Layout.maximumWidth: 380
            text: root.error
            color: Theme.bad
            wrapMode: Text.Wrap
        }

        MenuItem {
            Layout.fillWidth: true
            text: "Printer settings…"
            icon: "configure"
            onTriggered: { Settings.openRequested("printers"); root.popup.close(); }
        }
    }
}
