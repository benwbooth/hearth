pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Pinned taskbar launchers (desktop entry ids), saved in the state dir.
// The defaults are the launchers from the Plasma panel this replaced.
Singleton {
    id: root

    readonly property var defaults: [
        "hearth-settings", "grove", "almanac", "app.bluebubbles.BlueBubbles",
        "tessera", "brave-browser", "google-chrome", "org.keepassxc.KeePassXC", "code",
        "cursor", "chatgpt", "com.anthropic.Claude", "ai.opencode.desktop", "zcode",
        "spotify", "earshot", "org.kog.player", "home-services", "org.jellyfin.JellyfinDesktop",
        "com.stremio.Stremio", "com.nuvio.media.desktop", "org.kde.skanpage", "steam",
        "com.heroicgameslauncher.hgl", "info.exult.exult", "DoomRunner", "vkquake",
        "7th Heaven (2026)", "zzt-complete", "net.mkiol.SpeechNote", "org.pulseaudio.pavucontrol",
        "ns-usbloader", "com.benwbooth.treetop"
    ]

    // KDE apps hearth replaced, swapped in saved pins once: System Settings
    // -> hearth Settings, Dolphin -> grove, Konsole -> tessera.
    readonly property var replaced: ({ "systemsettings": "hearth-settings", "org.kde.systemsettings": "hearth-settings",
                                       "org.kde.dolphin": "grove", "org.kde.konsole": "tessera" })
    function migrate(list) {
        const out = [];
        for (const id of list) {
            const n = replaced[id] || id;
            if (out.indexOf(n) < 0) out.push(n);
        }
        return out;
    }

    // Defaults until (and unless) the saved file loads.
    property list<string> ids: defaults

    function isPinned(id) { return ids.indexOf(id) >= 0; }
    function pin(id) { if (!isPinned(id)) { ids = ids.concat([id]); save(); } }
    function unpin(id) { ids = ids.filter(x => x !== id); save(); }
    function move(id, toIndex) {
        const rest = ids.filter(x => x !== id);
        rest.splice(Math.max(0, Math.min(toIndex, rest.length)), 0, id);
        ids = rest;
        save();
    }
    function save() { file.setText(JSON.stringify({ pins: root.ids }, null, 2)); }

    FileView {
        id: file
        path: Quickshell.statePath("pins.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text()).pins;
                const m = root.migrate(saved);
                root.ids = m;
                if (JSON.stringify(m) !== JSON.stringify(saved)) root.save();
            }
            catch (e) { root.ids = root.defaults; }
        }
        onLoadFailed: root.ids = root.defaults
    }
}
