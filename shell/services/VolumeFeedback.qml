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
// changes (its volume "changes" to the new device's then). One pop once the
// volume stops changing for 150 ms, at the level it ends on: a scroll or a
// held key is one pop (a pop per step sounded like a machine gun), separate
// key presses still pop each.
Singleton {
    id: root

    // Never from a test shell (HEARTH_SESSION_DRYRUN=1: smoke tests, the
    // menu survey's rigs): they share the real audio, and six of them each
    // popped with the real one, a machine gun.
    readonly property bool enabled: Settings.sound.volumeFeedback !== false
        && Quickshell.env("HEARTH_SESSION_DRYRUN") !== "1"
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : -1
    PwObjectTracker { objects: [root.sink] }

    property real last: -1
    property bool armed: false

    Timer { id: arm; interval: 1500; running: true; onTriggered: { root.last = root.volume; root.armed = true; } }
    onSinkChanged: { armed = false; arm.restart(); }

    onVolumeChanged: {
        const v = volume;
        if (!armed || v < 0) { last = v; return; }
        if (Math.abs(v - last) < 0.004) return;
        last = v;
        if (!enabled) return;
        settle.restart();
    }
    Timer { id: settle; interval: 150; onTriggered: root.play() }

    function play() {
        const dir = Quickshell.env("HEARTH_SOUND_DIR");
        if (!dir) return;
        Quickshell.execDetached(["pw-play", dir + "/audio-volume-change.oga"]);
    }
}
