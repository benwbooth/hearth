pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mouse & touchpad settings from hearth's Settings window, applied live:
// Hyprland through `hyprctl eval` (also at every login, over the config's
// defaults); arbor/niri through ~/.config/hearth/arbor-input.kdl, which the
// arbor config includes (optional) and reloads on change.
// Values in ~/.config/hearth/mouse.json, next to settings.json.
Singleton {
    id: root

    property real speed: 0.3          // -1 .. 1
    property bool acceleration: true  // adaptive, as Plasma; off = flat
    property bool naturalScroll: true // touchpad: content follows fingers
    property bool loaded: false

    function set(key, value) {
        root[key] = value;
        save();
        apply();
    }
    function save() {
        file.setText(JSON.stringify({ speed: root.speed, acceleration: root.acceleration,
                                      naturalScroll: root.naturalScroll }, null, 2));
    }
    function apply() {
        const s = Math.round(root.speed * 100) / 100;
        const profile = root.acceleration ? "adaptive" : "flat";
        if (Compositor.isHyprland) {
            hypr.command = ["hyprctl", "eval",
                `hl.config({ input = { sensitivity = ${s}, accel_profile = "${profile}", touchpad = { natural_scroll = ${root.naturalScroll} } } })`];
            hypr.running = true;
        } else if (Compositor.isArbor) {
            arborFile.setText(`// Written by hearth (Settings > Mouse & Touchpad). Edits here are replaced.
input {
    mouse {
        accel-speed ${s}
        accel-profile "${profile}"
    }
    touchpad {
        accel-speed ${s}
        accel-profile "${profile}"
        natural-scroll ${root.naturalScroll}
    }
}
`);
        }
    }

    Process { id: hypr }
    FileView {
        id: arborFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hearth/arbor-input.kdl"
        printErrors: false
        blockLoading: false
    }
    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hearth/mouse.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (typeof d.speed === "number") root.speed = d.speed;
                if (typeof d.acceleration === "boolean") root.acceleration = d.acceleration;
                if (typeof d.naturalScroll === "boolean") root.naturalScroll = d.naturalScroll;
                root.loaded = true;
                root.apply();
            } catch (e) {}
        }
    }
}
