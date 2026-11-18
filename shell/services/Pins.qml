pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Pinned taskbar launchers (desktop entry ids), saved in the state dir.
// The defaults are the launchers from the Plasma panel this replaced.
Singleton {
    id: root

    readonly property var defaults: [
        "systemsettings", "org.kde.dolphin", "almanac", "app.bluebubbles.BlueBubbles",
        "tessera", "brave-browser", "google-chrome", "org.keepassxc.KeePassXC", "code",
        "cursor", "chatgpt", "com.anthropic.Claude", "ai.opencode.desktop", "zcode",
        "spotify", "earshot", "org.kog.player", "home-services", "org.jellyfin.JellyfinDesktop",
        "com.stremio.Stremio", "com.nuvio.media.desktop", "org.kde.skanpage", "steam",
        "com.heroicgameslauncher.hgl", "info.exult.exult", "DoomRunner", "vkquake",
        "7th Heaven (2026)", "zzt-complete", "net.mkiol.SpeechNote", "org.pulseaudio.pavucontrol",
        "ns-usbloader", "com.benwbooth.treetop"
    ]

    property list<string> ids: []

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
            try { root.ids = JSON.parse(text()).pins; }
            catch (e) { root.ids = root.defaults; }
        }
        onLoadFailed: root.ids = root.defaults
    }
}
