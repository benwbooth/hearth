import QtQuick
import QtQuick.Layouts
import Quickshell
import "../widgets"
import "../services"
import ".."

// Kickoff-style app launcher: button on the bar, search popup above it.
// Super (via `hearth-ipc call launcher toggle`) opens it too.
BarButton {
    id: root
    icon: "start-here-kde-symbolic"
    iconFallback: "start-here"
    iconSize: 26
    tooltip: "Applications"
    active: ShellState.launcherOpen
    onClicked: ShellState.launcherOpen = !ShellState.launcherOpen

    BarPopup {
        id: pop
        anchorItem: root
        padding: 10
        open: ShellState.launcherOpen
        onOpenChanged: {
            ShellState.launcherOpen = open;
            if (open) { search.text = ""; list.currentIndex = 0; search.forceActiveFocus(); }
        }

        ColumnLayout {
            implicitWidth: 520
            implicitHeight: 640
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
                    return hits;
                }

                model: results

                function launch(i) {
                    const r = results[i];
                    if (!r) return;
                    if (r.entry) r.entry.execute();
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
                            name: row.modelData.entry ? row.modelData.entry.icon : "system-run"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label {
                                Layout.fillWidth: true
                                text: row.modelData.entry ? row.modelData.entry.name : `Run “${row.modelData.command}”`
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.modelData.entry ? (row.modelData.entry.genericName || row.modelData.entry.comment) : ""
                                color: Theme.fgDim
                                font.pointSize: Theme.smallFontSize
                            }
                        }
                    }
                }
            }
        }
    }
}
