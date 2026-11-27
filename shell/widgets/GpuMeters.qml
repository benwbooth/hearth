import QtQuick
import QtQuick.Layouts
import ".."

// The AI menu's GPU header: how busy the GPU is and how full its memory
// is, the memory as one bar split by who holds it (each loaded model in
// its category's colour, then other apps). services/Ai.qml.
ColumnLayout {
    id: root
    property var gpu: null
    property var loaded: []
    property var apps: []
    spacing: 6

    readonly property real total: gpu && gpu.total ? gpu.total : 1
    readonly property real usedFrac: gpu ? Math.min(1, gpu.used / total) : 0
    readonly property var segments: {
        const out = [];
        let sum = 0;
        for (const m of loaded) {
            if (!m.vram) continue;
            out.push({ name: m.name, bytes: m.vram, color: Theme.aiCategoryColor(m.category), model: true });
            sum += m.vram;
        }
        let appBytes = 0;
        for (const a of apps) appBytes += a.vram;
        if (gpu) appBytes = Math.min(appBytes, Math.max(0, gpu.used - sum));
        if (appBytes > 0) out.push({ name: "Apps and desktop", bytes: appBytes, color: Theme.fgDim, model: false });
        const rest = gpu ? gpu.used - sum - appBytes : 0;
        if (rest > 64 * 1048576) out.push({ name: "Other", bytes: rest, color: Theme.border, model: false });
        return out;
    }
    function gb(b) { return (b / 1073741824).toFixed(b >= 10 * 1073741824 ? 0 : 1); }

    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        // GPU busy
        ColumnLayout {
            spacing: 2
            Layout.preferredWidth: 110
            Label { text: "GPU"; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize }
            Label {
                text: root.gpu && root.gpu.busy !== null && root.gpu.busy !== undefined ? root.gpu.busy + "%" : "—"
                font.pointSize: Theme.fontSize * 1.5
                font.weight: Font.DemiBold
            }
            Rectangle {
                Layout.fillWidth: true
                height: 4
                radius: 2
                color: Theme.hover
                Rectangle {
                    width: parent.width * Math.min(1, (root.gpu && root.gpu.busy ? root.gpu.busy : 0) / 100)
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }
        }
        // Graphics memory
        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                Label { text: "Graphics memory"; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize; Layout.fillWidth: true }
                Label {
                    // Only a real spill: a loaded model with part of itself in
                    // system RAM (slow), or a nearly full card pushing memory
                    // out. GTT always holds a GB or two of ordinary shared
                    // buffers (the screen's, apps' uploads): that isn't one.
                    readonly property var spilled: root.loaded.filter(m => (m.gtt || 0) >= 268435456)
                    readonly property string spillText: {
                        if (!root.gpu) return "";
                        if (spilled.length) {
                            const gtt = spilled.reduce((a, m) => a + m.gtt, 0);
                            return (spilled.length === 1 ? spilled[0].name : spilled.length + " models") + ": " + root.gb(gtt) + " GB spilled to RAM";
                        }
                        if (root.gpu.percent >= 92 && root.gpu.gttUsed > 1073741824) return root.gb(root.gpu.gttUsed) + " GB spilled to RAM";
                        return "";
                    }
                    visible: spillText !== ""
                    text: spillText
                    color: Theme.warn
                    font.pointSize: Theme.smallFontSize
                }
            }
            RowLayout {
                spacing: 6
                Label {
                    text: root.gpu ? root.gpu.percent + "%" : "—"
                    font.pointSize: Theme.fontSize * 1.5
                    font.weight: Font.DemiBold
                    color: root.usedFrac > 0.92 ? Theme.bad : root.usedFrac > 0.8 ? Theme.warn : Theme.fg
                }
                Label {
                    text: root.gpu ? `${root.gb(root.gpu.used)} of ${root.gb(root.gpu.total)} GB · ${root.gb(root.gpu.free)} GB free` : ""
                    color: Theme.fgSecondary
                    font.pointSize: Theme.smallFontSize
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 3
                }
            }
            // Who holds it.
            Item {
                id: bar
                Layout.fillWidth: true
                implicitHeight: 8
                Rectangle { anchors.fill: parent; radius: 4; color: Theme.hover }
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: root.segments
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: Math.max(1, bar.width * modelData.bytes / root.total)
                            height: bar.height
                            color: modelData.color
                            opacity: modelData.model ? 1 : 0.55
                            radius: index === 0 || index === root.segments.length - 1 ? 4 : 0
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            HoverHandler { id: hv }
                            Tooltip { anchorItem: parent; hovered: hv.hovered; text: modelData.name; subtext: root.gb(modelData.bytes) + " GB" }
                        }
                    }
                }
            }
        }
    }
}
