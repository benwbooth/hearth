import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../widgets"
import "../../services"
import "../.."

// Caps Lock / Num Lock and keyboard layout, from `hyprctl devices -j`.
// Shown only while Caps Lock is on or when more than one layout is
// configured; the popup switches layouts (`hyprctl switchxkblayout`).
// Hyprland sends no event for lock keys, so this polls (fast while Caps
// Lock is on) and refreshes at once on `activelayout`.
Indicator {
    id: root

    property bool capsLock: false
    property bool numLock: false
    property string keyboard: ""
    property var layouts: []      // [{ code, variant }]
    property int activeIndex: 0
    property string activeName: ""
    // "us" / "de:nodeadkeys" -> human name, from xkeyboard-config.
    property var names: ({})

    readonly property bool multi: layouts.length > 1
    shown: capsLock || multi
    icon: capsLock ? "input-caps-on" : "input-keyboard"
    text: multi && layouts[activeIndex] ? layouts[activeIndex].code.toUpperCase() : ""
    tooltip: activeName || "Keyboard"
    tooltipSub: [capsLock ? "Caps Lock on" : "", numLock ? "Num Lock on" : ""].filter(s => s).join(", ")

    function layoutName(l) {
        return root.names[l.code + (l.variant ? ":" + l.variant : "")]
            || (l.variant ? l.code + " (" + l.variant + ")" : l.code);
    }
    function refresh() { if (!query.running) query.running = true; }
    function switchTo(i) {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(i)]);
        root.activeIndex = i;
        refreshSoon.restart();
    }

    onScrolled: delta => {
        if (!multi) return;
        const n = layouts.length;
        switchTo((activeIndex + (delta < 0 ? 1 : n - 1)) % n);
    }

    Process {
        id: query
        command: ["hyprctl", "devices", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text); } catch (e) { return; }
                const kbs = d.keyboards || [];
                if (kbs.length === 0) return;
                const main = kbs.find(k => k.main) || kbs[0];
                root.capsLock = kbs.some(k => k.capsLock);
                root.numLock = kbs.some(k => k.numLock);
                root.keyboard = main.name;
                const codes = (main.layout || "").split(",");
                const vars = (main.variant || "").split(",");
                const ls = codes.map((c, i) => ({ code: c.trim(), variant: (vars[i] || "").trim() }));
                if (JSON.stringify(ls) !== JSON.stringify(root.layouts)) root.layouts = ls;
                root.activeIndex = main.active_layout_index ?? 0;
                root.activeName = main.active_keymap || "";
            }
        }
    }

    Timer {
        interval: root.capsLock ? 400 : 1500
        // hyprctl only; niri's layouts would come from its event stream.
        running: Compositor.isHyprland
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        id: refreshSoon
        interval: 80
        onTriggered: root.refresh()
    }
    Connections {
        target: Compositor.isHyprland ? Hyprland : null
        function onRawEvent(event) {
            if (event.name === "activelayout" || event.name === "configreloaded") refreshSoon.restart();
        }
    }

    // Layout and variant descriptions for the popup.
    FileView {
        path: root.multi ? "/etc/X11/xkb/rules/evdev.lst" : ""
        printErrors: false
        onLoaded: {
            const m = {};
            let section = "";
            for (const line of text().split("\n")) {
                if (line.startsWith("!")) { section = line.substring(1).trim(); continue; }
                const mm = line.match(/^\s+(\S+)\s+(.*)$/);
                if (!mm) continue;
                if (section === "layout") m[mm[1]] = mm[2];
                else if (section === "variant") {
                    const v = mm[2].match(/^(\S+): (.*)$/);
                    if (v) m[v[1] + ":" + mm[1]] = v[2];
                }
            }
            root.names = m;
        }
    }

    popupContent: ColumnLayout {
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 280
            Layout.bottomMargin: 6
            spacing: 8
            LockBadge { label: "Caps Lock"; on: root.capsLock }
            LockBadge { label: "Num Lock"; on: root.numLock }
        }

        Label {
            Layout.leftMargin: 8
            visible: root.layouts.length > 0
            text: "Layout"
            color: Theme.fgDim
            font.pointSize: Theme.smallFontSize
        }
        Repeater {
            model: root.layouts
            delegate: MouseArea {
                id: item
                required property var modelData
                required property int index
                readonly property bool current: index === root.activeIndex
                Layout.fillWidth: true
                implicitHeight: 30
                hoverEnabled: true
                onClicked: root.switchTo(index)
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: item.pressed ? Theme.pressed : item.containsMouse ? Theme.hover : "transparent"
                }
                Row {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Item {
                        width: 16
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        // Breeze's "checkmark" glyph.
                        Icon {
                            anchors.fill: parent
                            visible: item.current
                            implicitSize: 16
                            name: "dialog-ok-apply"
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.layoutName(item.modelData)
                        font.weight: item.current ? Font.DemiBold : Font.Normal
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: item.modelData.code
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                    }
                }
            }
        }
    }

    component LockBadge: Rectangle {
        property string label: ""
        property bool on: false
        Layout.fillWidth: true
        implicitHeight: 30
        radius: Theme.radius
        color: on ? Theme.accentDim : Theme.bgRaised
        border.color: on ? Theme.accent : Theme.border
        Label {
            anchors.centerIn: parent
            text: parent.label + (parent.on ? " on" : " off")
            color: parent.on ? Theme.fg : Theme.fgDim
        }
    }
}
