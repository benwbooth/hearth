import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "../widgets"
import "../services"
import ".."

// On-screen display for volume and brightness changes, like macOS 26: a
// glass panel under the menu bar at the top right with Control Center's
// slider, gone 1.5 s after the last change. While it shows, its slider
// works: drag or click to set the level, scroll on it to step, and it stays
// up while the pointer is on it. It stays quiet while things settle at
// startup or when the default output device changes.
Scope {
    id: root

    property string icon: ""
    property real value: 0      // 0..1 (volume may go above 1)
    property bool muted: false
    property bool showing: false
    onShowingChanged: ShellState.osdShowing = showing

    // Ignore the initial volume readout (and the one after switching sinks).
    property bool armed: false
    Timer {
        id: armTimer
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }

    readonly property PwNode sink: Pipewire.defaultAudioSink
    onSinkChanged: { root.armed = false; armTimer.restart(); }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    function show(icon, value, muted, title) {
        root.title = title || "";
        root.icon = icon;
        root.value = value;
        root.muted = muted;
        root.showing = true;
        if (!root.held) hideTimer.restart();
    }

    // The pointer is on the panel (or dragging its slider): it stays up,
    // and goes 1.5 s after the pointer leaves.
    property bool held: false
    onHeldChanged: if (held) hideTimer.stop(); else if (showing) hideTimer.restart()

    // Set from the slider: 0..1 of the track.
    function setLevel(v) {
        v = Math.max(0, Math.min(1, v));
        if (root.title === "Display") {
            Brightness.setAll(Math.round(v * 100), true);
        } else if (root.sink && root.sink.audio) {
            root.sink.audio.muted = false;
            root.sink.audio.volume = Math.round(v * 100) / 100;
        }
    }
    function stepLevel(n) {
        if (root.title === "Display") Brightness.step(5 * n, true);
        else root.setLevel(Math.round((root.value + 0.05 * n) * 20) / 20);
    }

    function showVolume() {
        if (!root.armed || !root.sink || !root.sink.audio) return;
        if (Date.now() < ShellState.osdQuietUntil) return;
        const a = root.sink.audio;
        const v = a.volume;
        const icon = a.muted || v <= 0 ? "audio-volume-muted"
                   : v < 0.34 ? "audio-volume-low"
                   : v < 0.67 ? "audio-volume-medium"
                   : "audio-volume-high";
        root.show(icon + "-symbolic", v, a.muted, "Sound");
    }

    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() { root.showVolume(); }
        function onMutedChanged() { root.showVolume(); }
    }

    Connections {
        target: Brightness
        function onOsd(percent) {
            root.show((percent >= 50 ? "brightness-high" : "brightness-low") + "-symbolic", percent / 100, false, "Display");
        }
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.showing = false
    }

    // `hearth-ipc call osd preview 0.4 Sound` (tests, scripts): the panel at
    // that level without changing anything.
    IpcHandler {
        target: "osd"
        function preview(value: real, title: string): void {
            root.show(title === "Display" ? "brightness-high-symbolic" : "audio-volume-medium-symbolic",
                      value, false, title || "Sound");
        }
    }

    // What the slider is for: "Sound" or "Display", as macOS titles them.
    property string title: ""

    // macOS 26: a glass panel just under the menu bar at the top right,
    // with Control Center's thick slider (the symbol inside its fill),
    // following each step as you scroll or press the keys.
    PanelWindow {
        id: win
        screen: Compositor.focusedScreen
        anchors.top: true
        anchors.right: true
        margins.top: Math.round(6 * Theme.pt) - frame.shadowPad
        margins.right: Math.round(8 * Theme.pt) - frame.shadowPad
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: frame.width + 2 * frame.shadowPad
        implicitHeight: frame.height + 2 * frame.shadowPad
        visible: frame.opacity > 0
        // The panel takes the pointer while it shows (its slider works);
        // fading out, clicks go through to whatever is underneath.
        mask: Region { item: root.showing ? frame : null }

        GlassFrame {
            id: frame
            x: shadowPad
            y: shadowPad
            width: Math.round(300 * Theme.pt)
            height: Math.round(62 * Theme.pt)
            radius: Math.round(18 * Theme.pt)
            opacity: root.showing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.showing ? 120 : 260; easing.type: Easing.OutCubic } }
            transform: Translate { x: 0.001; y: 0.001 }

            Label {
                x: Math.round(14 * Theme.pt)
                y: Math.round(9 * Theme.pt)
                text: root.title
                font.pointSize: Theme.menuSmallFontSize
                font.weight: Font.DemiBold
            }
            Label {
                anchors.right: parent.right
                anchors.rightMargin: Math.round(14 * Theme.pt)
                y: Math.round(9 * Theme.pt)
                text: root.muted ? "Muted" : Math.round(root.value * 100) + "%"
                color: Theme.fgSecondary
                font.pointSize: Theme.menuSmallFontSize
            }
            // Anywhere on the panel: hold it up; on the slider: drag or click
            // to set; the wheel steps 5% a notch like the menu bar item.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.showing
                onContainsMouseChanged: root.held = containsMouse || pressed
                onPressedChanged: root.held = containsMouse || pressed
                function levelAt(mx) { return (mx - track.x) / track.width; }
                onPressed: mouse => root.setLevel(levelAt(mouse.x))
                onPositionChanged: mouse => { if (pressed) root.setLevel(levelAt(mouse.x)); }
                WheelNotches { id: osdNotches }
                onWheel: w => { const n = osdNotches.feed(w); if (n) root.stepLevel(n); }
            }
            Item {
                id: track
                x: Math.round(12 * Theme.pt)
                width: parent.width - 2 * x
                height: Math.round(22 * Theme.pt)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(10 * Theme.pt)
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
                }
                Rectangle {
                    width: Math.max(height, parent.width * (root.muted ? 0 : Math.max(0, Math.min(1, root.value))))
                    height: parent.height
                    radius: height / 2
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.92) : "#ffffff"
                    border.color: Theme.dark ? "transparent" : Qt.rgba(0, 0, 0, 0.06)
                    Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                }
                Icon {
                    x: 5
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 14
                    name: root.icon
                    // Dark glyph on the white fill, like macOS.
                    layer.enabled: true
                    layer.effect: MultiEffect { brightness: -1; saturation: -1 }
                    opacity: 0.55
                }
            }
        }
    }
}
