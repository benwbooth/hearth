import QtQuick
import "../services"
import ".."

// What one screen's wallpaper shows (a view from services/Wallpaper.qml):
// a still (cross-faded on every change), a dynamic set (two stills
// blended by the time of day), a video or a GLSL shader. Wallpaper Engine
// projects draw their own surface (desktop/Background.qml runs them); here
// they show their preview still. Used by the desktop background and the
// lock screen (lock/LockSurface.qml).
//
// `speed` (0..1) slows shaders and videos down; at 0 they hold still
// without costing frames (the lock screen settles this way when you
// start typing, like macOS).
Item {
    id: root
    property var view: null
    property size px: Qt.size(width, height)
    property bool paused: false
    property real speed: 1
    // Save a still of a shader for the lock screen and the menu bar.
    property bool posters: false
    readonly property string kind: view ? view.kind : "still"
    readonly property bool held: paused || speed <= 0.001

    // Dynamic sets: the earlier frame underneath, the current one
    // blended over it.
    StillLayer {
        id: lower
        anchors.fill: parent
        visible: !!(root.view && root.view.fileA)
        source: root.view && root.view.fileA ? root.view.fileA : ""
        fit: root.view ? root.view.fit : "fill"
        pixelSize: root.px
    }
    StillLayer {
        id: still
        anchors.fill: parent
        source: root.view ? root.view.file : ""
        fit: root.view ? root.view.fit : "fill"
        pixelSize: root.px
        fadeMs: 1200
        opacity: root.view && root.view.fileA ? root.view.blend : 1
        Behavior on opacity { NumberAnimation { duration: 2500 } }
        onReadyChanged: if (ready && root.posters) Wallpaper.backgroundReady()
    }
    readonly property bool ready: still.ready

    Loader {
        id: video
        anchors.fill: parent
        active: root.kind === "video" && !!root.view.video
        source: "VideoLayer.qml"
        onLoaded: item.source = Qt.binding(() => root.view ? root.view.video || "" : "")
        Binding { target: video.item; property: "paused"; value: root.held; when: video.item !== null }
        Binding { target: video.item; property: "rate"; value: Math.max(0.1, root.speed); when: video.item !== null }
        Binding { target: video.item; property: "fit"; value: root.view ? root.view.fit : "fill"; when: video.item !== null }
    }

    // GLSL shaders, rendered into a smaller texture (wallpaper.shaderScale)
    // and scaled up: soft shaders look the same at a quarter of the cost.
    Loader {
        id: shader
        anchors.fill: parent
        active: root.kind === "shader" && !!root.view.shader
        sourceComponent: Item {
            id: sh
            readonly property real q: Math.max(0.25, Math.min(1, Number(Wallpaper.cfg.shaderScale) || 0.5))
            layer.enabled: q < 1
            layer.smooth: true
            layer.textureSize: Qt.size(Math.round(root.px.width * q), Math.round(root.px.height * q))
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: 900 } }
            ShaderEffect {
                id: fx
                anchors.fill: parent
                property real iTime: Wallpaper.st.shaderTime || 0
                property size res: Qt.size(root.px.width * sh.q, root.px.height * sh.q)
                property real dark: Theme.dark ? 1 : 0
                fragmentShader: root.view ? root.view.shader : ""
            }
            // Time advances at the frame cap only while not paused, so
            // a paused shader costs nothing (no new frames).
            Timer {
                interval: Math.round(1000 / Math.max(1, Math.min(144, Number(Wallpaper.cfg.fps) || 30)))
                running: !root.held
                repeat: true
                property double last: 0
                onRunningChanged: last = Date.now()
                onTriggered: {
                    const now = Date.now();
                    fx.iTime += Math.min(0.25, (now - last) / 1000) * root.speed;
                    last = now;
                }
            }
            // A still of it, for the lock screen and the menu bar.
            Timer {
                interval: 1500
                running: root.posters
                onTriggered: {
                    const path = Wallpaper.shaderPosterPath(root.view.shaderPath);
                    const key = root.view.shaderPath;
                    sh.grabToImage(r => { r.saveToFile(path); Wallpaper.setPoster(key, path); },
                                   Qt.size(Math.min(1920, root.width), Math.min(1920, root.width) * root.height / root.width));
                }
            }
        }
    }
}
