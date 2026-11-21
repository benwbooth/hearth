import QtQuick
import QtQuick.Effects
import "../widgets"
import ".."

// Glass on the lock screen. A lock surface has nothing behind it for the
// compositor to blur, so this blurs its own patch of the wallpaper
// (`backdrop`) and lays hearth's glass tint, rim and outline over it.
Item {
    id: root
    required property Item backdrop
    property real radius: height / 2
    property color tint: Qt.rgba(1, 1, 1, 0.14)
    property real blur: 1
    default property alias content: holder.data

    // Where this item sits over the backdrop. Ancestors moving don't
    // notify, so it's re-read a few times a second while shown.
    property int tick: 0
    Timer { interval: 150; repeat: true; running: root.visible; onTriggered: root.tick++ }
    readonly property rect area: {
        void x; void y; void width; void height; void tick;
        const p = root.mapToItem(root.backdrop, 0, 0);
        return Qt.rect(p.x, p.y, root.width, root.height);
    }

    Item {
        id: blurred
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shape
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        ShaderEffectSource {
            id: patch
            anchors.fill: parent
            sourceItem: root.backdrop
            sourceRect: root.area
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: patch
            blurEnabled: true
            blur: root.blur
            blurMax: 48
            saturation: 0.25
            brightness: 0.02
        }
    }
    Rectangle {
        id: shape
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }
    GlassFrame {
        anchors.fill: parent
        radius: root.radius
        tint: root.tint
        shadow: false
        compositorGlass: false
    }
    Item {
        id: holder
        anchors.fill: parent
    }
}
