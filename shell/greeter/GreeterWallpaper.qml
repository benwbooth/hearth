import QtQuick
import Quickshell.Io
import "../desktop"

// The login screen's wallpaper: what hearth last copied to
// /var/lib/hearth/wallpaper (wallpaper.json: the still in `path`, a
// `video`, a compiled `shader`), the same picture the lock screen shows.
// Videos and shaders play and slow to a still while you type (`speed`).
// Nothing there yet (first boot, or the copy is off): a soft macOS-like
// gradient drawn here, or $HEARTH_GREETER_WALLPAPER.
Item {
    id: root
    property string dir: "/var/lib/hearth/wallpaper"
    property string fallback: ""
    property real speed: 1
    property size px: Qt.size(width, height)
    property var info: ({})
    readonly property string kind: info.video ? "video" : info.shader ? "shader" : info.path ? "still" : "none"
    readonly property bool ready: kind === "none" ? !fallbackStill.source || fallbackStill.ready : still.ready

    FileView {
        path: root.dir + "/wallpaper.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                // Only files inside the shared directory (it's group-writable).
                const inDir = p => typeof p === "string" && p.startsWith(root.dir + "/") ? p : "";
                root.info = { path: inDir(j.path), video: inDir(j.video), shader: inDir(j.shader), fit: j.fit || "fill" };
            } catch (e) { root.info = {}; }
        }
        onLoadFailed: root.info = {}
    }

    // Built-in fallback: deep blue to violet with two soft glows.
    Rectangle {
        anchors.fill: parent
        visible: root.kind === "none"
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: "#0d1b3e" }
            GradientStop { position: 0.55; color: "#2b2a6b" }
            GradientStop { position: 1; color: "#5b2f6e" }
        }
        Rectangle {
            x: -parent.width * 0.15; y: parent.height * 0.35
            width: parent.width * 0.8; height: width; radius: width / 2
            opacity: 0.35
            gradient: Gradient {
                GradientStop { position: 0; color: "#3a7bd5" }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        Rectangle {
            x: parent.width * 0.55; y: -parent.height * 0.3
            width: parent.width * 0.6; height: width; radius: width / 2
            opacity: 0.25
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: "#c06c84" }
            }
        }
    }
    StillLayer {
        id: fallbackStill
        anchors.fill: parent
        visible: root.kind === "none" && root.fallback !== ""
        source: root.kind === "none" ? root.fallback : ""
        pixelSize: root.px
    }

    StillLayer {
        id: still
        anchors.fill: parent
        source: root.info.path || ""
        fit: root.info.fit || "fill"
        pixelSize: root.px
    }
    Loader {
        id: video
        anchors.fill: parent
        active: root.kind === "video"
        source: "../desktop/VideoLayer.qml"
        onLoaded: item.source = Qt.binding(() => root.info.video || "")
        Binding { target: video.item; property: "paused"; value: root.speed <= 0.001; when: video.item !== null }
        Binding { target: video.item; property: "rate"; value: Math.max(0.1, root.speed); when: video.item !== null }
        Binding { target: video.item; property: "fit"; value: root.info.fit || "fill"; when: video.item !== null }
    }
    Loader {
        anchors.fill: parent
        active: root.kind === "shader"
        sourceComponent: Item {
            id: sh
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.round(root.px.width * 0.5), Math.round(root.px.height * 0.5))
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: 900 } }
            ShaderEffect {
                id: fx
                anchors.fill: parent
                property real iTime: 0
                property size res: Qt.size(root.px.width * 0.5, root.px.height * 0.5)
                property real dark: 1
                fragmentShader: "file://" + root.info.shader
            }
            Timer {
                interval: 33
                running: root.speed > 0.001
                repeat: true
                property double last: Date.now()
                onRunningChanged: last = Date.now()
                onTriggered: {
                    const now = Date.now();
                    fx.iTime += Math.min(0.25, (now - last) / 1000) * root.speed;
                    last = now;
                }
            }
        }
    }
}
