import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// The panel's Dev apps button (ported from devloop's org.devloop.devapps
// plasmoid): every devloop project, with buttons to open each way it runs
// (app, web page, terminal), stop it, pause its watching, deploy its image
// and read its log, and
// what it's doing (building, failed, running, deployed). All of it comes
// from `devloop status --json`, asked every few seconds.
Indicator {
    id: root

    readonly property string cli: Quickshell.env("HOME") + "/.local/bin/devloop"
    property var projects: []
    property real now: Date.now() / 1000
    readonly property bool anyBusy: projects.some(p => p.building || p.deploying)
    readonly property bool anyFailed: projects.some(p => p.failed || p.deployFailed)

    icon: "applications-development"
    iconSize: Theme.taskIconSize
    implicitWidth: Theme.barHeight
    tooltip: "Dev apps"
    tooltipSub: summary()

    IpcHandler {
        target: ShellState.isActiveScreen(QsWindow.window ? QsWindow.window.screen : null) ? "devapps" : ""
        function toggle(): void { root.popup.toggle(); }
        function open(): void { root.popup.open = true; }
        function close(): void { root.popup.close(); }
    }

    // Building or deploying: a spinner on the icon; failed: a red dot.
    // Both sit on the button itself, not inside the icon: in the menu bar the
    // icon is drawn through a monochrome layer the size of the icon, which
    // cut the badge off at its edge (and greyed it).
    Spinner {
        parent: root
        visible: root.anyBusy
        z: 2
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: Math.round(root.iconSize * 0.4)
        anchors.verticalCenterOffset: Math.round(root.iconSize * 0.35)
        size: Math.max(10, Math.round(root.iconSize * 0.6))
    }
    Rectangle {
        parent: root
        visible: root.anyFailed && !root.anyBusy
        z: 2
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: Math.round(root.iconSize * 0.4)
        anchors.verticalCenterOffset: Math.round(root.iconSize * 0.35)
        width: Math.max(6, Math.round(root.iconSize * 0.35))
        height: width
        radius: width / 2
        color: Theme.bad
        border.color: Theme.bg
        border.width: 1
    }

    // ---- devloop -----------------------------------------------------------
    Process {
        id: statusProc
        command: [root.cli, "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                try { root.projects = root.group(JSON.parse(text)); }
                catch (e) { console.warn("devloop status:", e); }
            }
        }
    }
    function refresh() { if (!statusProc.running) statusProc.running = true; }

    // Runs `devloop <args...>` and refreshes once it has had time to act.
    // Opening something (start, the log window) goes through Launch, as the
    // Dock's launches do: under arbor that gives it an xdg-activation token,
    // so `devloop start` of a terminal app (`tessera -e`, a tab in the open
    // Tessera) brings that window forward instead of leaving it behind.
    function act(args) {
        if (args[0] === "start" || args[0] === "logs-window") Launch.run([cli].concat(args), "devloop");
        else Quickshell.execDetached([cli].concat(args));
        refreshSoon.restart();
    }

    Timer {
        interval: root.popup.open ? 1000 : 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { root.now = Date.now() / 1000; root.refresh(); }
    }
    Timer { id: refreshSoon; interval: 1500; onTriggered: root.refresh() }

    // "<state> <start> [<seconds>]" and "<state> <time> [<sig>] [current=<sig>]".
    function words(s) { return (s || "").split(" ").filter(w => w.length); }

    // Apps sharing a project folder are one row: Kog, Kog Web and Kog
    // Terminal are Kog's three ways to open.
    function group(apps) {
        const byDir = {};
        const order = [];
        for (const a of apps) {
            if (!byDir[a.dir]) { byDir[a.dir] = { dir: a.dir, variants: [] }; order.push(byDir[a.dir]); }
            const b = words(a.build);
            a.buildState = b[0] || "";
            a.buildStart = Number(b[1] || 0);
            a.buildSecs = Number(b[2] || 0);
            byDir[a.dir].variants.push(a);
        }
        const kindOrder = { app: 0, web: 1, terminal: 2 };
        for (const p of order) {
            const v = p.variants;
            // The primary one (PRIMARY=1) names the row: Commander Blood, not
            // its sibling Big Bug Bang. Then apps before web pages and terminals.
            v.sort((x, y) => (y.primary - x.primary) || (kindOrder[x.kind] - kindOrder[y.kind]));
            const main = v[0];
            p.name = main.kind === "web" ? main.name.replace(/ Web$/, "") : main.name;
            p.icon = main.icon;
            p.main = main;
            p.running = v.filter(a => a.running);
            // Paused (devloop pause): not watched, no builds, greyed here.
            p.paused = v.some(a => a.paused);
            // The latest build of any of them.
            const last = v.reduce((x, y) => (y.buildStart > x.buildStart ? y : x));
            p.last = last;
            p.building = v.some(a => a.buildState === "building" || a.buildState === "waiting");
            p.waiting = v.some(a => a.buildState === "waiting");
            p.failed = !p.building && last.buildState === "failed";
            p.built = Math.max(...v.map(a => a.built));
            const img = v.find(a => a.image);
            p.image = img || null;
            p.deploying = false;
            p.deployFailed = false;
            p.deployStale = false;
            if (img) {
                const d = words(img.deploy);
                const cur = (d.find(w => w.startsWith("current=")) || "").slice(8);
                const plain = d.filter(w => !w.startsWith("current="));
                p.deploying = img.deploying || ["queued", "deploying", "switching"].includes(plain[0]);
                p.deployFailed = !p.deploying && plain[0] === "failed";
                p.deployedAt = Number(plain[1] || 0);
                p.deployState = plain[0] || "";
                p.deployStale = plain[0] === "deployed" && plain[2] !== cur;
            }
        }
        order.sort((x, y) => x.name.localeCompare(y.name));
        return order;
    }

    function ago(t) {
        const s = Math.max(0, Math.round(now - t));
        if (s < 60) return "just now";
        if (s < 3600) return Math.round(s / 60) + " min ago";
        if (s < 86400) return Math.round(s / 3600) + " h ago";
        return Math.round(s / 86400) + " d ago";
    }

    // The project's line under its name, and whether it's bad news.
    function status(p) {
        const parts = [];
        let bad = false;
        if (p.paused && !p.building) {
            parts.push("Paused" + (p.running.length ? ", still running" : "") + " — not watching for changes");
            if (p.built) parts.push("built " + ago(p.built));
        } else if (p.building) {
            const b = p.variants.find(a => a.buildState === "building" || a.buildState === "waiting");
            parts.push((p.waiting ? "Waiting for another cargo run (cargo test?)… " : "Building… ")
                       + Math.max(0, Math.round(now - b.buildStart)) + "s");
        } else if (p.failed) {
            parts.push("Build failed " + ago(p.last.buildStart));
            bad = true;
        } else {
            if (p.main.buildOnly)
                parts.push(p.running.length ? "Watching for changes" : "Not watching");
            else
                parts.push(p.running.length
                    ? "Running" + (p.variants.length > 1 ? " (" + p.running.map(kindName).join(", ") + ")" : "")
                    : "Stopped");
            if (p.built) parts.push("built " + ago(p.built));
        }
        if (p.image) {
            if (p.deploying) parts.push({ queued: "deploy queued", switching: "swapping the container…" }[p.deployState] || "deploying…");
            else if (p.deployState === "cancelled") parts.push("deploy cancelled for a newer build");
            else if (p.deployFailed) { parts.push("deploy failed"); bad = true; }
            else if (p.deployState === "deployed")
                parts.push(p.deployStale ? "deployed " + ago(p.deployedAt) + " (newer build not deployed yet)" : "deployed " + ago(p.deployedAt));
        }
        return { text: parts.join(" · "), bad: bad };
    }

    function kindName(a) { return { app: "app", web: "web", terminal: "terminal" }[a.kind]; }
    function kindIcon(a) {
        return { app: "media-playback-start", web: "internet-web-browser", terminal: "utilities-terminal" }[a.kind];
    }

    // The whole project's log: every variant's builds and runs, and its
    // deploys, interleaved.
    function logArgs(p) { return p.variants.map(a => a.id); }

    function summary() {
        if (!projects.length) return "";
        const lines = [];
        for (const p of projects) {
            if (p.building) lines.push(p.name + ": building");
            else if (p.failed) lines.push(p.name + ": build failed");
            if (p.deploying) lines.push(p.name + ": deploying");
            else if (p.deployFailed) lines.push(p.name + ": deploy failed");
        }
        const n = projects.filter(p => p.running.length).length;
        lines.push(n ? n + " running" : "Nothing running");
        return lines.join("\n");
    }

    // A small spinning arc (Plasma's BusyIndicator).
    component Spinner: Item {
        id: sp
        property int size: 16
        width: size
        height: size
        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.lineWidth = Math.max(1.5, width / 8);
                // The whole stroke inside the canvas (it rotates in place).
                const r = width / 2 - ctx.lineWidth / 2 - 0.5;
                ctx.strokeStyle = Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.8);
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI);
                ctx.stroke();
                ctx.strokeStyle = Theme.accent;
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, r, 0, 1.4 * Math.PI);
                ctx.stroke();
            }
            RotationAnimator on rotation {
                running: sp.visible
                from: 0
                to: 360
                duration: 1000
                loops: Animation.Infinite
            }
        }
    }

    // ---- the list ----------------------------------------------------------
    popupContent: ColumnLayout {
        id: pane
        spacing: 6

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: "Dev apps"
            font.pointSize: Theme.fontSize + 6
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.preferredWidth: 540
            // Tall enough for every project; past 85% of the screen it scrolls.
            readonly property real maxH: (root.QsWindow.window && root.QsWindow.window.screen
                ? root.QsWindow.window.screen.height : 1600) * 0.85 - 80
            Layout.preferredHeight: Math.min(list.implicitHeight, maxH)
            contentHeight: list.implicitHeight
            contentWidth: width
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: list
                width: flick.width
                spacing: 0

                Repeater {
                    model: root.projects
                    delegate: MouseArea {
                        id: row
                        required property var modelData
                        readonly property var p: modelData
                        readonly property var st: root.status(p)
                        Layout.fillWidth: true
                        implicitHeight: rowLayout.implicitHeight + 12
                        hoverEnabled: true
                        onClicked: { root.act(["start", p.main.id]); root.popup.close(); }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius
                            color: row.pressed ? Theme.pressed : row.containsMouse ? Theme.hover : "transparent"
                        }

                        RowLayout {
                            id: rowLayout
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 4
                            spacing: 8

                            Item {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                // Paused: grey and faded, like a disabled app.
                                opacity: row.p.paused ? 0.45 : 1
                                layer.enabled: row.p.paused
                                layer.effect: MultiEffect { saturation: -1 }
                                Icon {
                                    anchors.fill: parent
                                    implicitSize: 32
                                    name: row.p.icon
                                }
                                Rectangle {
                                    visible: row.p.running.length > 0
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    width: 12
                                    height: width
                                    radius: width / 2
                                    color: Theme.good
                                    border.color: Theme.bgAlt
                                    border.width: 1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label {
                                    Layout.fillWidth: true
                                    text: row.p.name
                                    font.weight: Font.DemiBold
                                    color: row.p.paused ? Theme.fgDim : Theme.fg
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Spinner {
                                        visible: row.p.building || row.p.deploying
                                        size: 14
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: row.st.text
                                        font.pointSize: Theme.smallFontSize
                                        color: row.st.bad ? Theme.bad
                                             : row.p.deployStale ? Theme.warn
                                             : Theme.fgDim
                                    }
                                }
                            }
                            // One button per way to open it (app, web page, terminal),
                            // highlighted while it runs. Clicking the row opens the first.
                            Repeater {
                                model: row.p.variants
                                delegate: BarButton {
                                    required property var modelData
                                    implicitHeight: 36
                                    implicitWidth: 32
                                    iconSize: 16
                                    icon: root.kindIcon(modelData)
                                    active: modelData.running
                                    tooltip: "Open " + modelData.name + (modelData.running ? " (running)" : "")
                                    onClicked: { root.act(["start", modelData.id]); root.popup.close(); }
                                }
                            }
                            BarButton {
                                visible: row.p.image !== null
                                enabled: !row.p.deploying
                                opacity: enabled ? 1 : 0.35
                                implicitHeight: 36
                                implicitWidth: 32
                                iconSize: 16
                                icon: "cloud-upload"
                                tooltip: row.p.deploying ? "Deploying…" : "Deploy " + row.p.name
                                tooltipSub: row.p.deploying ? "" : "Deploy the current build to its Docker container now (it also deploys after every build)"
                                onClicked: root.act(["deploy-background", row.p.image.id])
                            }
                            BarButton {
                                implicitHeight: 36
                                implicitWidth: 32
                                iconSize: 16
                                icon: row.p.paused ? "media-playback-start" : "media-playback-pause"
                                active: row.p.paused
                                tooltip: row.p.paused ? "Resume watching " + row.p.name : "Pause watching " + row.p.name
                                tooltipSub: row.p.paused
                                    ? "Watch its source again (inotify), building whatever changed while paused"
                                    : "Stop watching its source (frees its inotify watches) and stop rebuilding it; anything running keeps running its last build"
                                onClicked: root.act([row.p.paused ? "resume" : "pause", row.p.main.id])
                            }
                            BarButton {
                                enabled: row.p.running.length > 0
                                opacity: enabled ? 1 : 0.35
                                implicitHeight: 36
                                implicitWidth: 32
                                iconSize: 16
                                icon: "media-playback-stop"
                                tooltip: "Stop " + row.p.name
                                onClicked: row.p.running.forEach(a => root.act(["stop", a.id]))
                            }
                            BarButton {
                                implicitHeight: 36
                                implicitWidth: 32
                                iconSize: 16
                                icon: "view-list-text"
                                tooltip: "Log"
                                tooltipSub: "Builds, runs and deploys, as they happen"
                                onClicked: { root.act(["logs-window"].concat(root.logArgs(row.p))); root.popup.close(); }
                            }
                        }
                    }
                }
            }
        }
    }
}
