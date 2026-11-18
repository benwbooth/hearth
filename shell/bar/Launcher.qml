import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// Kickoff-style app launcher: button on the bar, search popup above it.
// Super (via `hearth-ipc call launcher toggle`) opens it too.
// KRunner-style extras above the app hits: qalc answers arithmetic and unit
// conversions ("5 km to mi", "100 f to c"); Enter copies the answer. The
// footer has Kickoff's power buttons. `hearth-ipc call launcher-search set
// TEXT` opens it with TEXT typed (for binds and headless screenshots).
BarButton {
    id: root
    icon: "start-here-kde-symbolic"
    iconFallback: "start-here"
    iconSize: 26
    tooltip: "Applications"
    active: ShellState.launcherOpen
    onClicked: ShellState.launcherOpen = !ShellState.launcherOpen

    readonly property bool here: ShellState.isActiveScreen(root.QsWindow.window ? root.QsWindow.window.screen : null)
    // Touch the Session singleton so its `session` IPC target exists from
    // startup, not only after the first footer click.
    readonly property var session: Session

    IpcHandler {
        target: root.here ? "launcher-search" : ""
        enabled: target !== ""
        function set(text: string): void {
            ShellState.launcherOpen = true;
            search.text = text;
            search.cursorPosition = text.length;
        }
    }

    // --- Calculator / unit conversion through qalc -------------------------
    // What qalc should evaluate for `q`, or "" when it doesn't look like a
    // sum or a conversion (so app searches never get a bogus "= 0 B").
    function calcExpr(q) {
        const s = q.trim();
        if (!/\d/.test(s)) return "";
        const conv = s.match(/^([-+]?[\d.,]+.*?\S)\s+(?:to|in|as|->)\s+([+-]?)(\S.*)$/i);
        if (conv) {
            let src = conv[1], tgt = conv[3].trim();
            // Bare f/c mean degrees when converting temperatures ("100 f to
            // c"); qalc would read femto-/speed of light.
            const temp = /^(°?[fc]|fahrenheit|celsius|k|kelvin)$/i;
            if (temp.test(tgt)) {
                src = src.replace(/\s*°?([fc])$/i, (m, u) => " °" + u.toUpperCase());
                tgt = tgt.replace(/^°?([fc])$/i, (m, u) => "°" + u.toUpperCase());
            }
            // "-" = no mixed units: "3.1 mi", not "3 mi + 188 yd + 0.2 ft".
            return `${src} to ${conv[2] || "-"}${tgt}`;
        }
        const funcs = /\b(sqrt|cbrt|sin|cos|tan|asin|acos|atan|log|log10|log2|ln|exp|abs|round|floor|ceil|pi|e)\b/gi;
        const rest = s.replace(funcs, "");
        if (!/^[\d\s.,+\-*\/^%()×÷!]+$/.test(rest)) return "";
        if (!/[+\-*\/^%×÷!]/.test(rest) && rest.length === s.length) return "";
        return s;
    }
    readonly property string calcWanted: pop.open ? calcExpr(search.text) : ""
    property string calcFor: ""
    property string calcValue: ""
    readonly property bool calcReady: calcWanted !== "" && calcFor === calcWanted && calcValue !== ""
    onCalcWantedChanged: calcTimer.restart()

    Timer {
        id: calcTimer
        interval: 120
        onTriggered: {
            if (root.calcWanted === "" || calcProc.running) return;  // onExited re-runs
            calcProc.expr = root.calcWanted;
            calcProc.command = ["timeout", "3", "qalc", "-t", root.calcWanted];
            calcProc.running = true;
        }
    }
    Process {
        id: calcProc
        property string expr: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const line = (text.trim().split("\n").filter(l => l.trim() !== "").pop() ?? "").trim();
                const same = line.replace(/\s/g, "") === calcProc.expr.replace(/\s/g, "");
                root.calcFor = calcProc.expr;
                root.calcValue = /\d/.test(line) && !same && !/error|warning/i.test(line) ? line : "";
            }
        }
        onExited: if (root.calcWanted !== "" && root.calcWanted !== expr) calcTimer.restart()
    }

    function powerAction(action) {
        ShellState.launcherOpen = false;
        pop.close();
        // Lock and sleep are harmless and immediate; the rest go through the
        // logout screen so a stray click can't end the session.
        if (action === "lock" || action === "suspend") Session.run(action);
        else Session.menu();
    }

    BarPopup {
        id: pop
        anchorItem: root
        padding: 10
        keyboardFocus: WlrKeyboardFocus.Exclusive
        // Not a binding: closing the popup assigns `open`, which would break
        // it and leave the shortcut unable to reopen the launcher.
        Connections {
            target: ShellState
            function onLauncherOpenChanged() {
                const here = ShellState.isActiveScreen(root.QsWindow.window ? root.QsWindow.window.screen : null);
                pop.open = ShellState.launcherOpen && here;
            }
        }
        onOpenChanged: {
            if (!open && ShellState.launcherOpen) ShellState.launcherOpen = false;
            if (open) { search.text = ""; list.currentIndex = 0; search.forceActiveFocus(); }
        }

        // Layouts compute their own implicit size, so the fixed popup size
        // lives on a plain Item around it.
        Item {
            implicitWidth: 520
            implicitHeight: 640
        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Theme.radius
                color: Theme.bg
                border.color: search.activeFocus ? Theme.accent : Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Icon { implicitSize: 16; name: "search" }
                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSize + 1
                        renderType: Text.NativeRendering
                        selectByMouse: true
                        clip: true
                        onTextChanged: list.currentIndex = 0
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Down) { list.incrementCurrentIndex(); event.accepted = true; }
                            else if (event.key === Qt.Key_Up) { list.decrementCurrentIndex(); event.accepted = true; }
                            else if (event.key === Qt.Key_PageDown) { list.currentIndex = Math.min(list.count - 1, list.currentIndex + 10); event.accepted = true; }
                            else if (event.key === Qt.Key_PageUp) { list.currentIndex = Math.max(0, list.currentIndex - 10); event.accepted = true; }
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { list.launch(list.currentIndex); event.accepted = true; }
                            else if (event.key === Qt.Key_Escape) { pop.close(); event.accepted = true; }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text === ""
                            text: "Search applications…"
                            color: Theme.fgDim
                            font.pointSize: Theme.fontSize + 1
                        }
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 1
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds

                readonly property var apps: DesktopEntries.applications.values
                    .filter(e => !e.noDisplay)
                    .sort((a, b) => a.name.localeCompare(b.name))

                function score(e, q) {
                    const name = e.name.toLowerCase();
                    if (name === q) return 1000;
                    if (name.startsWith(q)) return 900 - name.length;
                    if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 800 - name.length;
                    if (name.includes(q)) return 700 - name.indexOf(q);
                    const extra = [e.genericName, e.keywords, e.comment, e.id, e.categories]
                        .join(" ").toLowerCase();
                    if (extra.includes(q)) return 500;
                    // Subsequence match ("ffx" -> "Firefox").
                    let i = 0;
                    for (const ch of name) if (ch === q[i]) i++;
                    if (i === q.length) return 300 - name.length;
                    return -1;
                }

                readonly property var results: {
                    const q = search.text.trim().toLowerCase();
                    if (q === "") {
                        const pinned = Pins.ids.map(id => DesktopEntries.byId(id)).filter(e => e);
                        const rest = apps.filter(e => !Pins.isPinned(e.id));
                        return pinned.map(e => ({ entry: e, section: "Favorites" }))
                            .concat(rest.map(e => ({ entry: e, section: "All applications" })));
                    }
                    const hits = apps.map(e => ({ entry: e, s: score(e, q) }))
                        .filter(x => x.s >= 0)
                        .sort((a, b) => b.s - a.s)
                        .map(x => ({ entry: x.entry, section: "" }));
                    hits.push({ entry: null, command: search.text.trim(), section: "" });
                    if (root.calcReady)
                        hits.unshift({ entry: null, calc: root.calcValue, section: "" });
                    return hits;
                }

                model: results

                function launch(i) {
                    const r = results[i];
                    if (!r) return;
                    if (r.entry) r.entry.execute();
                    else if (r.calc) Quickshell.execDetached(["wl-copy", "--", r.calc.replace(/^[≈=]\s*/, "")]);
                    else Hypr.exec(r.command);
                    pop.close();
                }

                delegate: MouseArea {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool header: modelData.section !== ""
                        && (index === 0 || list.results[index - 1].section !== modelData.section)
                    width: list.width
                    height: 40 + (header ? 26 : 0)
                    hoverEnabled: true
                    onClicked: list.launch(index)
                    onContainsMouseChanged: if (containsMouse) list.currentIndex = index

                    Label {
                        visible: row.header
                        height: 26
                        leftPadding: 6
                        text: row.modelData.section
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: row.header ? 26 : 0
                        radius: Theme.radius
                        color: row.ListView.isCurrentItem ? Theme.accentDim : "transparent"
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.topMargin: row.header ? 26 : 0
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10
                        Icon {
                            implicitSize: 28
                            name: row.modelData.entry ? row.modelData.entry.icon
                                : row.modelData.calc ? "accessories-calculator" : "system-run"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                Layout.fillWidth: true
                                text: row.modelData.entry ? row.modelData.entry.name
                                    : row.modelData.calc ? "= " + row.modelData.calc
                                    : `Run “${row.modelData.command}”`
                                font.weight: row.modelData.calc ? Font.DemiBold : Font.Normal
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.modelData.entry ? (row.modelData.entry.genericName || row.modelData.entry.comment)
                                    : row.modelData.calc ? search.text.trim() + "  ·  Enter to copy" : ""
                                color: Theme.fgDim
                                font.pointSize: Theme.smallFontSize
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
            }

            // Kickoff's footer: power and session buttons.
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [
                        { action: "lock", text: "Lock", icon: "system-lock-screen" },
                        { action: "suspend", text: "Sleep", icon: "system-suspend" },
                        { action: "reboot", text: "Restart", icon: "system-reboot" },
                        { action: "poweroff", text: "Shut Down", icon: "system-shutdown" },
                        { action: "logout", text: "Log Out", icon: "system-log-out" }
                    ]
                    delegate: MouseArea {
                        id: pb
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 34
                        hoverEnabled: true
                        onClicked: root.powerAction(modelData.action)
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius
                            color: pb.pressed ? Theme.pressed : pb.containsMouse ? Theme.hover : "transparent"
                        }
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 16
                                name: pb.modelData.icon
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: pb.modelData.text
                            }
                        }
                    }
                }
            }
        }
    }
        }
}
