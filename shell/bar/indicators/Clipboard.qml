import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../widgets"
import "../.."

// Clipboard history via cliphist. While hearth runs, `wl-paste --watch`
// records every text and image copy into cliphist's database; the popup
// lists it (images as thumbnails), with search, click to copy, per-item
// delete and clear all.
Indicator {
    id: root
    icon: "edit-paste"
    tooltip: "Clipboard"
    tooltipSub: entries.length > 0 ? entries.length + " items in history" : "History is empty"

    // [{ id, text, image: { kind, w, h } | null, line }], newest first.
    property var entries: []
    property bool thumbsReady: false
    readonly property string thumbDir: Quickshell.cachePath("clipboard-thumbs")

    // Record history only once, from the bar on the first screen.
    readonly property bool recorder: QsWindow.window !== null && QsWindow.window.screen === Quickshell.screens[0]

    function refresh() { lister.running = true; }
    function copy(e) {
        Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy', "sh", e.id]);
        root.popup.close();
    }
    function remove(e) {
        root.entries = root.entries.filter(x => x !== e);
        deleter.stdinLine = e.line;
        deleter.running = true;
    }
    function wipe() {
        root.entries = [];
        Quickshell.execDetached(["cliphist", "wipe"]);
    }

    Connections {
        target: root.popup
        function onOpenChanged() { if (root.popup.open) root.refresh(); }
    }

    Repeater {
        model: root.recorder ? ["text", "image"] : []
        delegate: Item {
            id: watch
            required property string modelData
            Process {
                id: watcher
                // pdeathsig: don't leave watchers behind if hearth is killed.
                command: ["setpriv", "--pdeathsig", "TERM", "--", "wl-paste", "--type", watch.modelData, "--watch", "cliphist", "store"]
                running: true
                onExited: restart.start()
            }
            Timer {
                id: restart
                interval: 3000
                onTriggered: watcher.running = true
            }
        }
    }

    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const id = line.substring(0, tab);
                    const preview = line.substring(tab + 1);
                    const m = preview.match(/^\[\[ binary data .* (\w+) (\d+)x(\d+) \]\]$/);
                    out.push({
                        id: id,
                        line: line,
                        text: preview,
                        image: m ? { kind: m[1], w: +m[2], h: +m[3] } : null
                    });
                }
                root.entries = out;
                root.thumbsReady = false;
                const specs = out.filter(e => e.image).slice(0, 40).map(e => e.id + "." + e.image.kind);
                thumbs.command = ["sh", "-c", `
                    dir=$1; shift; mkdir -p "$dir"
                    for f in "$dir"/*; do
                        [ -e "$f" ] || continue
                        keep=0; for s in "$@"; do [ "$f" = "$dir/$s" ] && keep=1; done
                        [ $keep = 1 ] || rm -f "$f"
                    done
                    for s in "$@"; do
                        [ -s "$dir/$s" ] || cliphist decode "\${s%%.*}" > "$dir/$s"
                    done`, "sh", root.thumbDir].concat(specs);
                thumbs.running = true;
            }
        }
    }

    Process {
        id: thumbs
        onExited: root.thumbsReady = true
    }

    Process {
        id: deleter
        property string stdinLine: ""
        command: ["cliphist", "delete"]
        stdinEnabled: true
        onStarted: { write(stdinLine + "\n"); stdinEnabled = false; }
        onExited: stdinEnabled = true
    }

    popupContent: ColumnLayout {
        id: pane
        spacing: 8
        readonly property var shown: {
            const q = search.text.trim().toLowerCase();
            if (!q) return root.entries;
            return root.entries.filter(e => !e.image && e.text.toLowerCase().includes(q));
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 440
            spacing: 6
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: Theme.radius
                color: Theme.bg
                border.color: search.activeFocus ? Theme.accent : Theme.border
                Icon {
                    id: searchIcon
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 16
                    name: "search"
                }
                TextInput {
                    id: search
                    anchors.left: searchIcon.right
                    anchors.right: parent.right
                    anchors.leftMargin: 6
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    focus: true
                    renderType: Text.NativeRendering
                    color: Theme.fg
                    selectionColor: Theme.accentDim
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.fontSize
                    Component.onCompleted: forceActiveFocus()
                    onAccepted: if (pane.shown.length > 0) root.copy(pane.shown[0])
                    Keys.onEscapePressed: root.popup.close()
                    Label {
                        anchors.fill: parent
                        visible: !search.text
                        text: "Search clipboard history"
                        color: Theme.fgDim
                    }
                }
            }
            BarButton {
                implicitHeight: 32
                icon: "edit-clear-history"
                iconSize: 16
                text: "Clear all"
                enabled: root.entries.length > 0
                opacity: enabled ? 1 : 0.5
                onClicked: root.wipe()
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: 20
            Layout.bottomMargin: 20
            visible: pane.shown.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: root.entries.length === 0 ? "Clipboard history is empty" : "No matches"
            color: Theme.fgDim
        }

        ListView {
            id: list
            Layout.fillWidth: true
            // ListView only builds rows that fit, so size it from the data.
            Layout.preferredHeight: Math.min(560, pane.shown.reduce((h, e) => h + (e.image ? 76 : 32) + 2, -2))
            visible: pane.shown.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: pane.shown
            delegate: Row {
                id: row
                required property var modelData
                readonly property var e: modelData
                width: list.width
                height: e.image ? 76 : 32
                spacing: 2

                MouseArea {
                    id: body
                    width: row.width - del.width - 2
                    height: row.height
                    hoverEnabled: true
                    onClicked: root.copy(row.e)
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radius
                        color: body.pressed ? Theme.pressed : body.containsMouse ? Theme.hover : "transparent"
                    }
                    Label {
                        visible: !row.e.image
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        text: row.e.text
                        textFormat: Text.PlainText
                        maximumLineCount: 1
                    }
                    Row {
                        visible: row.e.image !== null
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Rectangle {
                            width: 96
                            height: 64
                            radius: 4
                            color: Theme.bg
                            border.color: Theme.border
                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                sourceSize.width: 192
                                sourceSize.height: 128
                                source: row.e.image && root.thumbsReady
                                    ? "file://" + root.thumbDir + "/" + row.e.id + "." + row.e.image.kind : ""
                            }
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.e.image ? row.e.image.kind.toUpperCase() + " image, " + row.e.image.w + "×" + row.e.image.h : ""
                            color: Theme.fgDim
                        }
                    }
                }
                BarButton {
                    id: del
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: 28
                    implicitWidth: 28
                    iconSize: 14
                    icon: "edit-delete"
                    tooltip: "Delete"
                    onClicked: root.remove(row.e)
                }
            }
        }
    }
}
