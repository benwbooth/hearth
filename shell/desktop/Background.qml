import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"
import ".."

// The wallpaper of one screen: a full-screen surface on the compositor's
// background layer, drawing what services/Wallpaper.qml says this screen
// shows: a still (cross-faded on every change), a dynamic set (two stills
// blended by the time of day), a video, a GLSL shader, or a Wallpaper
// Engine project (linux-wallpaperengine draws its own background surface;
// hearth's steps aside once it's up and keeps the preview underneath until
// then). Animation pauses whenever Wallpaper.paused(screen) says so.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    readonly property string output: modelData.name
    readonly property var view: Wallpaper.views[output] || null
    readonly property string kind: view ? view.kind : "still"
    readonly property bool paused: { void Wallpaper.covered; void Wallpaper.pauseReason; return Wallpaper.paused(output); }
    readonly property size px: Qt.size(Math.round(width * (modelData.devicePixelRatio || 1)),
                                       Math.round(height * (modelData.devicePixelRatio || 1)))

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "hearth-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "black"
    // Wallpaper Engine draws its own surface; hide ours once it's running.
    visible: !(kind === "we" && we.up)
    mask: Region {}

    Item {
        id: content
        anchors.fill: parent

        // Dynamic sets: the earlier frame underneath, the current one
        // blended over it.
        StillLayer {
            id: lower
            anchors.fill: parent
            visible: !!(win.view && win.view.fileA)
            source: win.view && win.view.fileA ? win.view.fileA : ""
            fit: win.view ? win.view.fit : "fill"
            pixelSize: win.px
        }
        StillLayer {
            id: still
            anchors.fill: parent
            source: win.view ? win.view.file : ""
            fit: win.view ? win.view.fit : "fill"
            pixelSize: win.px
            fadeMs: 1200
            opacity: win.view && win.view.fileA ? win.view.blend : 1
            Behavior on opacity { NumberAnimation { duration: 2500 } }
            onReadyChanged: if (ready) Wallpaper.backgroundReady()
        }

        Loader {
            id: video
            anchors.fill: parent
            active: win.kind === "video" && !!win.view.video
            source: "VideoLayer.qml"
            onLoaded: item.source = Qt.binding(() => win.view ? win.view.video || "" : "")
            Binding { target: video.item; property: "paused"; value: win.paused; when: video.item !== null }
            Binding { target: video.item; property: "fit"; value: win.view ? win.view.fit : "fill"; when: video.item !== null }
        }

        // GLSL shaders, rendered into a smaller texture (wallpaper.shaderScale)
        // and scaled up: soft shaders look the same at a quarter of the cost.
        Loader {
            id: shader
            anchors.fill: parent
            active: win.kind === "shader" && !!win.view.shader
            sourceComponent: Item {
                id: sh
                readonly property real q: Math.max(0.25, Math.min(1, Number(Wallpaper.cfg.shaderScale) || 0.5))
                layer.enabled: q < 1
                layer.smooth: true
                layer.textureSize: Qt.size(Math.round(win.px.width * q), Math.round(win.px.height * q))
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 900 } }
                ShaderEffect {
                    id: fx
                    anchors.fill: parent
                    property real iTime: Wallpaper.st.shaderTime || 0
                    property size res: Qt.size(win.px.width * sh.q, win.px.height * sh.q)
                    property real dark: Theme.dark ? 1 : 0
                    fragmentShader: win.view ? win.view.shader : ""
                }
                // Time advances at the frame cap only while not paused, so
                // a paused shader costs nothing (no new frames).
                Timer {
                    interval: Math.round(1000 / Math.max(1, Math.min(144, Number(Wallpaper.cfg.fps) || 30)))
                    running: !win.paused
                    repeat: true
                    property double last: 0
                    onRunningChanged: last = Date.now()
                    onTriggered: {
                        const now = Date.now();
                        fx.iTime += Math.min(0.25, (now - last) / 1000);
                        last = now;
                    }
                }
                // A still of it, for the lock screen and the menu bar.
                Timer {
                    interval: 1500
                    running: true
                    onTriggered: {
                        const path = Wallpaper.shaderPosterPath(win.view.shaderPath);
                        const key = win.view.shaderPath;
                        sh.grabToImage(r => { r.saveToFile(path); Wallpaper.setPoster(key, path); },
                                       Qt.size(Math.min(1920, win.width), Math.min(1920, win.width) * win.height / win.width));
                    }
                }
            }
        }
    }

    // ---- Wallpaper Engine (linux-wallpaperengine, its own layer surface) ----
    Item {
        id: we
        property bool up: false
        readonly property string path: win.kind === "we" && win.view ? win.view.wePath || "" : ""
        readonly property var command: {
            if (!path) return [];
            const c = Wallpaper.cfg;
            const a = ["linux-wallpaperengine", "--screen-root", win.output, "--bg", path,
                       "--fps", String(Math.max(1, Math.min(144, Number(c.fps) || 30))),
                       "--scaling", win.view.fit === "fit" ? "fit" : "fill",
                       // hearth pauses it itself (SIGSTOP), covered or not.
                       "--no-fullscreen-pause", "--disable-mouse"];
            if (c.weAudio) a.push("--volume", String(Number(c.weVolume) || 15), "--noautomute");
            else a.push("--silent");
            if (Wallpaper.weAssets) a.push("--assets-dir", Wallpaper.weAssets);
            return a;
        }
        onCommandChanged: { proc.running = false; up = false; if (command.length) restart.restart(); }
        Timer { id: restart; interval: 300; onTriggered: proc.running = we.command.length > 0 }
        Process {
            id: proc
            command: we.command
            stderr: SplitParser { onRead: l => { if (/error|fail/i.test(l)) console.warn("linux-wallpaperengine:", l); } }
            onStarted: upTimer.restart()
            onExited: code => {
                we.up = false;
                if (we.command.length && code !== 0 && code !== 15 && code !== 143) {
                    console.warn("hearth wallpaper: linux-wallpaperengine exited", code);
                    retry.start();
                }
            }
        }
        // Give it time to draw before hearth's preview goes away.
        Timer { id: upTimer; interval: 4000; onTriggered: we.up = proc.running }
        Timer { id: retry; interval: 15000; onTriggered: if (we.command.length && !proc.running) proc.running = true }
        // Pause = SIGSTOP (it keeps its last frame), resume = SIGCONT.
        readonly property bool stop: win.paused && proc.running
        onStopChanged: if (proc.processId) Quickshell.execDetached(["kill", stop ? "-STOP" : "-CONT", String(proc.processId)])
        Component.onDestruction: if (proc.running && proc.processId) Quickshell.execDetached(["kill", "-CONT", String(proc.processId)])
    }
}
