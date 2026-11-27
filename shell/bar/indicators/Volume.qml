import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../../widgets"
import "../../services"
import "../.."

// Volume: default output volume/mute in the bar (scroll = ±5%, middle click
// = mute). The popup has output and input sliders, default device choice and
// per-application stream volumes. Pure Pipewire, no wpctl.
Indicator {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    // Audio nodes, split by role. Streams are application playback/record.
    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio)
    readonly property var sinks: nodes.filter(n => !n.isStream && n.isSink).sort(byName)
    readonly property var sources: nodes.filter(n => n.type === PwNodeType.AudioSource).sort(byName)
    readonly property var streams: nodes.filter(n => n.type === PwNodeType.AudioOutStream)

    // Volume/mute only bind on tracked nodes.
    PwObjectTracker { objects: [root.sink, root.source] }

    function byName(a, b) { return nodeName(a).localeCompare(nodeName(b)); }
    function clamp(v) { return Math.max(0, Math.min(1, v)); }
    function pct(v) { return Math.round(v * 100) + "%"; }
    function nodeName(n) {
        if (!n) return "";
        return n.description || n.nickname || n.name;
    }
    function volIcon(vol, mute) {
        if (mute || vol <= 0.001) return "audio-volume-muted";
        if (vol < 0.34) return "audio-volume-low";
        if (vol < 0.67) return "audio-volume-medium";
        return "audio-volume-high";
    }
    function micIcon(vol, mute) {
        if (mute || vol <= 0.001) return "microphone-sensitivity-muted";
        if (vol < 0.34) return "microphone-sensitivity-low";
        if (vol < 0.67) return "microphone-sensitivity-medium";
        return "microphone-sensitivity-high";
    }

    shown: sink !== null
    closeOnOsd: true
    icon: volIcon(volume, muted)
    tooltip: muted ? "Volume: muted" : "Volume: " + pct(volume)
    tooltipSub: nodeName(sink)

    onScrolled: delta => {
        if (!sink?.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = clamp(Math.round((volume + (delta > 0 ? 0.05 : -0.05)) * 20) / 20);
    }
    onMiddleClicked: if (sink?.audio) sink.audio.muted = !sink.audio.muted

    popupContent: ColumnLayout {
        spacing: 4

        PwObjectTracker { objects: root.sinks.concat(root.sources, root.streams) }

        Heading { text: "Output" }
        VolRow {
            node: root.sink
            label: root.nodeName(root.sink)
            iconName: root.volIcon(root.volume, root.muted)
        }
        DevicePicker {
            nodes: root.sinks
            current: root.sink
            onPicked: n => Pipewire.preferredDefaultAudioSink = n
        }

        Heading { text: "Input"; visible: root.source !== null }
        VolRow {
            visible: root.source !== null
            node: root.source
            label: root.nodeName(root.source)
            iconName: root.micIcon(node?.audio?.volume ?? 0, node?.audio?.muted ?? false)
        }
        DevicePicker {
            nodes: root.sources
            current: root.source
            onPicked: n => Pipewire.preferredDefaultAudioSource = n
        }

        Heading { text: "Applications"; visible: root.streams.length > 0 }
        Repeater {
            model: root.streams
            delegate: VolRow {
                required property var modelData
                Layout.fillWidth: true
                node: modelData
                appIcon: true
                label: {
                    const p = modelData.properties;
                    const app = p["application.name"] || root.nodeName(modelData);
                    const media = p["media.name"] || "";
                    return media && media !== app ? app + " — " + media : app;
                }
                iconName: modelData.properties["application.icon-name"]
                          || (modelData.properties["application.process.binary"] ?? "").toLowerCase()
                          || "audio-x-generic"
            }
        }
    }

    component Heading: Label {
        Layout.fillWidth: true
        Layout.topMargin: 6
        font.weight: Font.DemiBold
        color: Theme.fgDim
    }

    // Name, then [mute button][slider][percent].
    component VolRow: ColumnLayout {
        id: row
        property var node: null
        property string label: ""
        property string iconName: ""
        property bool appIcon: false
        readonly property real vol: node?.audio?.volume ?? 0
        readonly property bool mute: node?.audio?.muted ?? false
        Layout.fillWidth: true
        Layout.preferredWidth: 380
        spacing: 0

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: row.label
            font.pointSize: Theme.smallFontSize
            color: Theme.fgDim
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            BarButton {
                implicitHeight: 30
                implicitWidth: 32
                icon: row.iconName
                iconFallback: row.appIcon ? "audio-x-generic" : "audio-volume-high"
                opacity: row.appIcon && row.mute ? 0.4 : 1
                tooltip: row.mute ? "Unmute" : "Mute"
                onClicked: if (row.node?.audio) { ShellState.osdQuietUntil = Date.now() + 400; row.node.audio.muted = !row.node.audio.muted; }
            }
            Slider {
                Layout.fillWidth: true
                value: row.vol
                dim: row.mute
                onMoved: v => {
                    if (!row.node?.audio) return;
                    ShellState.osdQuietUntil = Date.now() + 400;
                    row.node.audio.muted = false;
                    row.node.audio.volume = v;
                }
            }
            Label {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: row.mute ? "muted" : root.pct(row.vol)
                color: row.mute ? Theme.fgDim : Theme.fg
            }
        }
    }

    component Slider: Item {
        id: sl
        property real value: 0
        property bool dim: false
        signal moved(real v)
        implicitHeight: 24
        implicitWidth: 200

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            x: 7
            width: parent.width - 14
            height: 4
            radius: 2
            color: Theme.border
            Rectangle {
                width: parent.width * root.clamp(sl.value)
                height: parent.height
                radius: 2
                color: sl.dim ? Theme.fgDim : Theme.accent
            }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: track.x + track.width * root.clamp(sl.value) - width / 2
            width: 14
            height: 14
            radius: 7
            color: ma.pressed || ma.containsMouse ? Theme.fg : Theme.fgDim
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            function set(x) { sl.moved(root.clamp((x - track.x) / track.width)); }
            onPressed: m => set(m.x)
            onPositionChanged: m => { if (pressed) set(m.x); }
            WheelNotches { id: sliderNotches }
            onWheel: w => {
                const n = sliderNotches.feed(w);
                if (n) sl.moved(root.clamp(Math.round((sl.value + 0.05 * n) * 20) / 20));
            }
        }
    }

    // Choose the default device; hidden when there's only one.
    component DevicePicker: Column {
        id: dp
        property var nodes: []
        property var current: null
        signal picked(var node)
        Layout.fillWidth: true
        visible: nodes.length > 1
        Repeater {
            model: dp.nodes
            delegate: MouseArea {
                id: item
                required property var modelData
                readonly property bool current: modelData === dp.current
                width: dp.width
                implicitHeight: 28
                hoverEnabled: true
                onClicked: dp.picked(modelData)
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: item.pressed ? Theme.pressed : item.containsMouse ? Theme.hover : "transparent"
                }
                // Radio dot.
                Rectangle {
                    id: dot
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: "transparent"
                    border.color: item.current ? Theme.accent : Theme.fgDim
                    border.width: 1.5
                    Rectangle {
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: Theme.accent
                        visible: item.current
                    }
                }
                Label {
                    anchors.left: dot.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.nodeName(item.modelData)
                    color: item.current ? Theme.fg : Theme.fgDim
                }
            }
        }
    }
}
