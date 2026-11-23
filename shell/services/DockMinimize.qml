pragma Singleton
import QtQuick
import Quickshell

// Settings > Dock > "Minimize windows using": arbor draws the effect
// (`animations { window-minimize { effect "genie" | "scale" | "none" } }`).
// Written to ~/.config/hearth/arbor-dock.kdl, which arbor's config includes;
// no file for Genie, arbor's default. The Dock (bar/Dock.qml) tells arbor
// where each window's slot is (SetDockTargets).
Singleton {
    id: root

    readonly property string effect: ["genie", "scale", "none"].indexOf(Settings.dock.minimizeEffect) >= 0
        ? Settings.dock.minimizeEffect : "genie"
    property string error: ""

    function apply() {
        if (!Compositor.isArbor || !Settings.loaded) return;
        if (root.effect === "genie") {
            ArborConfig.remove("arbor-dock.kdl", (ok, err) => root.error = err);
            return;
        }
        ArborConfig.write("arbor-dock.kdl", `// Written by hearth (Settings > Dock). Edits here are replaced.
animations {
    window-minimize {
        effect "${root.effect}"
    }
}`, (ok, err) => root.error = err);
    }
    onEffectChanged: writeSoon.restart()
    Connections {
        target: Settings
        function onLoadedChanged() { writeSoon.restart(); }
    }
    Component.onCompleted: writeSoon.restart()
    Timer { id: writeSoon; interval: 300; onTriggered: root.apply() }
}
