import QtQuick
import QtQuick.Window
import ".."

// A pop-up button (macOS NSPopUpButton): shows the chosen option; clicking
// opens a list over the window, with a search field when `searchable`.
// `options` is [{ value, label, note?, icon? }]. Emits picked(value).
// The list is drawn inside the same window (no extra surface), above
// everything else, and closes on a click outside it or Esc.
MouseArea {
    id: root
    property var options: []
    property var value
    property string placeholder: "Choose…"
    property bool searchable: options.length > 15
    property int listWidth: Math.max(width, 260)
    signal picked(var value)

    readonly property var current: options.find(o => o.value === value) || null
    implicitWidth: Math.min(320, Math.max(140, lbl.implicitWidth + 44))
    implicitHeight: 28
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    opacity: enabled ? 1 : 0.4
    onClicked: open()

    function open() {
        const host = root.Window.contentItem;
        if (!host) return;
        const p = listComp.createObject(host, {});
        const pt = root.mapToItem(host, 0, root.height + 2);
        p.panelX = Math.max(4, Math.min(pt.x, host.width - p.panelWidth - 4));
        const below = host.height - pt.y - 8;
        if (below < Math.min(p.panelHeight, 200) && pt.y - root.height > below)
            p.panelY = Math.max(4, pt.y - root.height - 4 - p.panelHeight);
        else
            p.panelY = pt.y;
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.pressed ? Theme.pressed : root.containsMouse ? Theme.hover : (Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05))
        border.color: Theme.border
    }
    Label {
        id: lbl
        x: 10
        width: parent.width - 34
        anchors.verticalCenter: parent.verticalCenter
        text: root.current ? root.current.label : root.placeholder
        color: root.current ? Theme.fg : Theme.fgDim
    }
    Icon {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        implicitSize: 12
        name: "arrow-down"
    }

    Component {
        id: listComp
        MouseArea {
            id: catcher
            anchors.fill: parent
            z: 10000
            property real panelX: 0
            property real panelY: 0
            readonly property int panelWidth: root.listWidth
            readonly property int panelHeight: Math.min(360, list.contentHeight + (search.visible ? 44 : 8))
            onPressed: close()
            function close() { Qt.callLater(() => catcher.destroy()); }
            function choose(v) { root.picked(v); close(); }
            readonly property var shown: {
                const q = search.text.trim().toLowerCase();
                if (!q) return root.options;
                return root.options.filter(o => (o.label + " " + (o.note || "") + " " + o.value).toLowerCase().includes(q));
            }
            Keys.onEscapePressed: close()
            focus: true
            Component.onCompleted: { if (search.visible) search.forceActiveFocus(); else catcher.forceActiveFocus(); }

            Rectangle {
                id: panel
                x: catcher.panelX
                y: catcher.panelY
                width: catcher.panelWidth
                height: catcher.panelHeight
                radius: Theme.popupRadius
                color: Theme.bgRaised
                border.color: Theme.border
                MouseArea { anchors.fill: parent }  // clicks inside don't close

                Rectangle {
                    id: searchBox
                    visible: root.searchable
                    x: 6; y: 6
                    width: parent.width - 12
                    height: visible ? 30 : 0
                    radius: Theme.radius
                    color: Theme.bgAlt
                    border.color: search.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: search
                        x: 8
                        width: parent.width - 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSize
                        renderType: Text.NativeRendering
                        clip: true
                        Keys.onEscapePressed: catcher.close()
                        Keys.onReturnPressed: if (catcher.shown.length) catcher.choose(catcher.shown[0].value)
                        Label {
                            visible: search.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Type to search"
                            color: Theme.fgDim
                        }
                    }
                }
                ListView {
                    id: list
                    x: 4
                    y: searchBox.visible ? 40 : 4
                    width: parent.width - 8
                    height: parent.height - y - 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: catcher.shown
                    delegate: MouseArea {
                        id: opt
                        required property var modelData
                        width: list.width
                        height: modelData.note ? 40 : 28
                        hoverEnabled: true
                        onClicked: catcher.choose(modelData.value)
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius
                            color: opt.containsMouse ? Theme.accent : "transparent"
                        }
                        Row {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            width: parent.width - 16
                            Icon {
                                visible: !!opt.modelData.icon
                                name: opt.modelData.icon || ""
                                implicitSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - (opt.modelData.icon ? 26 : 0)
                                Label {
                                    width: parent.width
                                    text: (opt.modelData.value === root.value ? "✓ " : "") + opt.modelData.label
                                    color: opt.containsMouse ? Theme.accentText : Theme.fg
                                }
                                Label {
                                    visible: !!opt.modelData.note
                                    width: parent.width
                                    text: opt.modelData.note || ""
                                    font.pointSize: Theme.smallFontSize
                                    color: opt.containsMouse ? Theme.accentText : Theme.fgDim
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
