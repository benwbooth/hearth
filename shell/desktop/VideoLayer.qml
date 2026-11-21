import QtQuick
import QtMultimedia

// A looping, silent video wallpaper (QtMultimedia's FFmpeg backend decodes
// on the GPU through VA-API when it can). Pauses when `paused`.
Item {
    id: root
    property string source: ""
    property string fit: "fill"
    property bool paused: false
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState && player.hasVideo
    property bool firstFrame: false

    MediaPlayer {
        id: player
        source: root.source ? "file://" + root.source : ""
        loops: MediaPlayer.Infinite
        videoOutput: out
        onSourceChanged: { root.firstFrame = false; root.sync(); }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.LoadedMedia) root.sync();
            if (mediaStatus === MediaPlayer.InvalidMedia) console.warn("hearth wallpaper: can't play", root.source, errorString);
        }
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) firstTimer.restart()
        onErrorOccurred: (e, s) => console.warn("hearth wallpaper: video:", s)
    }
    // The first frames can lag the state change: show the poster a moment longer.
    Timer { id: firstTimer; interval: 250; onTriggered: root.firstFrame = true }
    onPausedChanged: sync()
    function sync() {
        if (!root.source) return;
        if (root.paused) player.pause(); else player.play();
    }
    Component.onCompleted: sync()

    VideoOutput {
        id: out
        anchors.fill: parent
        fillMode: root.fit === "fit" ? VideoOutput.PreserveAspectFit
                : root.fit === "stretch" ? VideoOutput.Stretch : VideoOutput.PreserveAspectCrop
        opacity: root.firstFrame ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }
}
