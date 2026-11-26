pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// The macOS volume chime: a short pop each time the output volume changes,
// played through that output at its new level, so you hear how loud it is
// now. Covers every way the volume changes (the volume keys, which arbor
// handles with wpctl; scrolling on the menu bar's volume item; the sliders;
// a mixer app), since it watches the default output itself.
// Settings > Sound > "Play feedback when volume is changed".
//
// Quiet while the shell starts and for a moment after the default output
// changes (its volume "changes" to the new device's then); at most one pop
// per 90 ms, the last one always played, so a fast scroll doesn't pile up.
Singleton {
    id: root

    readonly property bool enabled: Settings.sound.volumeFeedback !== false
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : -1
    PwObjectTracker { objects: [root.sink] }

    property real last: -1
    property bool armed: false
    property real lastPlayed: 0

    Timer { id: arm; interval: 1500; running: true; onTriggered: { root.last = root.volume; root.armed = true; } }
    onSinkChanged: { armed = false; arm.restart(); }

    onVolumeChanged: {
        const v = volume;
        if (!armed || v < 0) { last = v; return; }
        if (Math.abs(v - last) < 0.004) return;
        last = v;
        if (!enabled) return;
        const now = Date.now();
        if (now - lastPlayed >= 90) play();
        else trailing.restart();
    }
    Timer { id: trailing; interval: 90; onTriggered: root.play() }

    function play() {
        const dir = Quickshell.env("HEARTH_SOUND_DIR");
        if (!dir) return;
        lastPlayed = Date.now();
        Quickshell.execDetached(["pw-play", dir + "/audio-volume-change.oga"]);
    }
}
