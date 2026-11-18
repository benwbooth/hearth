import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../widgets"
import ".."

// FanzyZones drag overlay: the zones of the layout under the cursor, with
// numbers, the one under the cursor highlighted. Hyprland's Lua can't draw,
// so hypr/fanzyzones.lua tracks drags and sends socket2 `custom` events:
//   fanzyzones show <monitor> <layout-id> <x> <y> <w> <h>   (work area, monitor-relative)
//   fanzyzones hover <zone, 1-based; 0 = none>
//   fanzyzones flash <monitor> <layout-id> <x> <y> <w> <h>  (layout switched: brief preview)
//   fanzyzones hide
// The window ignores input, so the drag carries on underneath it.
PanelWindow {
    id: win

    property var cfg: null
    property string monitorName: ""
    property string layoutId: ""
    property rect area: Qt.rect(0, 0, 0, 0)
    property int hover: 0
    property bool shownByDrag: false
    property bool flashing: false

    readonly property var layout: cfg && cfg.layouts ? (cfg.layouts.find(l => l.id === layoutId) || null) : null
    readonly property color tint: cfg && cfg.highlight_color
        ? Qt.rgba(cfg.highlight_color.red, cfg.highlight_color.green, cfg.highlight_color.blue, 1)
        : Theme.accent
    readonly property real opacityLevel: cfg && cfg.overlay_opacity !== undefined ? cfg.overlay_opacity : 0.35

    screen: Quickshell.screens.find(s => s.name === monitorName) ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hearth-zones"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    mask: Region {}
    visible: (shownByDrag || flashing) && layout !== null

    FileView {
        path: {
            const env = Quickshell.env("HEARTH_ZONES_CONFIG");
            if (env) return env;
            const xdg = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
            return xdg + "/hearth/zones.json";
        }
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { win.cfg = JSON.parse(text()); } catch (e) {} }
    }

    Timer {
        id: flashTimer
        interval: 1100
        onTriggered: win.flashing = false
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "custom" || !event.data.startsWith("fanzyzones ")) return;
            const a = event.data.split(" ");
            switch (a[1]) {
            case "show":
            case "flash":
                win.monitorName = a[2];
                win.layoutId = a[3];
                win.area = Qt.rect(+a[4], +a[5], +a[6], +a[7]);
                if (a[1] === "show") {
                    win.shownByDrag = true;
                    win.flashing = false;
                } else if (!win.shownByDrag) {
                    win.hover = 0;
                    win.flashing = true;
                    flashTimer.restart();
                }
                break;
            case "hover":
                win.hover = +a[2];
                break;
            case "hide":
                win.shownByDrag = false;
                win.hover = 0;
                break;
            }
        }
    }

    Item {
        anchors.fill: parent
        transform: Translate { x: 0.001; y: 0.001 }
        opacity: win.flashing && !win.shownByDrag ? 0.8 : 1

        Repeater {
            model: win.layout ? win.layout.zones : []
            delegate: Rectangle {
                id: z
                required property var modelData
                required property int index
                readonly property bool lit: win.hover === index + 1
                readonly property real pad: Math.max(0, win.cfg ? (win.cfg.outer_padding || 0) : 0)
                readonly property real gap: Math.max(0, win.cfg ? (win.cfg.gap || 0) : 0)
                readonly property real uw: win.area.width - pad * 2
                readonly property real uh: win.area.height - pad * 2
                // Same rectangles as fanzyzones.lua's zone_rect, inset a little.
                x: Math.round(win.area.x + pad + uw * modelData.x + gap / 2) + 4
                y: Math.round(win.area.y + pad + uh * modelData.y + gap / 2) + 4
                width: Math.max(1, Math.round(uw * modelData.width - gap)) - 8
                height: Math.max(1, Math.round(uh * modelData.height - gap)) - 8
                radius: Theme.popupRadius
                color: Qt.rgba(win.tint.r, win.tint.g, win.tint.b, lit ? Math.min(1, win.opacityLevel + 0.25) : win.opacityLevel * 0.45)
                border.color: Qt.rgba(win.tint.r, win.tint.g, win.tint.b, lit ? 1 : 0.7)
                border.width: lit ? 3 : 2

                Label {
                    anchors.centerIn: parent
                    visible: !win.cfg || win.cfg.show_zone_numbers !== false
                    text: z.index + 1
                    font.pointSize: Math.max(18, Math.min(72, z.height / 6))
                    font.bold: true
                    color: z.lit ? Theme.fg : Qt.rgba(1, 1, 1, 0.75)
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.35)
                }
            }
        }
    }
}
