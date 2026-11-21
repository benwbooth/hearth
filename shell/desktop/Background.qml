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

    WallpaperView {
        anchors.fill: parent
        view: win.view
        px: win.px
        paused: win.paused
        posters: true
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
