pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Mouse & touchpad settings and the pointer theme from hearth's Settings
// window, applied live:
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
            // Through ArborConfig.write: checked with `arbor validate` before it
            // replaces the file, so a bad line can never break arbor's config
            // (it once wrote `natural-scroll true`; arbor wants a bare flag).
            ArborConfig.write("arbor-input.kdl", `// Written by hearth (Settings > Mouse & Touchpad). Edits here are replaced.
input {
    mouse {
        accel-speed ${s}
        accel-profile "${profile}"
    }
    touchpad {
        accel-speed ${s}
        accel-profile "${profile}"
${root.naturalScroll ? "        natural-scroll\n" : ""}    }
}
cursor {
    xcursor-theme "${root.cursorTheme}"
    xcursor-size ${root.cursorSize}
}
`, (ok, err) => { if (!ok) console.warn("hearth: arbor-input.kdl not written:", err); });
        }
    }

    Process { id: hypr }

    // --- pointer (Settings > Appearance > Pointer) ---
    // "macos": the open macOS-style cursors (nixpkgs apple-cursor, theme
    // "macOS": black arrow, white outline) at 28, which on Ben's 4/3
    // display is the size of macOS's arrow on a 5K Mac; "breeze": KDE's.
    // Applied live (hyprctl setcursor / arbor's cursor block) when the
    // theme is installed; otherwise the compositor keeps its own.
    readonly property string cursorChoice: Settings.appearance.cursor || "macos"
    readonly property string cursorTheme: cursorChoice === "macos" && macInstalled ? "macOS" : "breeze_cursors"
    readonly property int cursorSize: cursorTheme === "macOS" ? 28 : 24
    property bool macInstalled: false
    Process {
        id: findTheme
        running: true
        command: ["sh", "-c", "for d in \"$HOME/.icons\" \"$HOME/.local/share/icons\" $(echo \"${XDG_DATA_DIRS:-/run/current-system/sw/share}\" | tr : ' ' | sed 's|$|/icons|g') /run/current-system/sw/share/icons; do [ -d \"$d/macOS/cursors\" ] && exit 0; done; exit 1"]
        onExited: code => { root.macInstalled = code === 0; root.applyCursor(); }
    }
    onCursorThemeChanged: applyCursor()
    function applyCursor() {
        if (findTheme.running) return;
        if (Compositor.isHyprland) {
            cursorProc.command = ["hyprctl", "setcursor", cursorTheme, String(cursorSize)];
            cursorProc.running = true;
        } else if (Compositor.isArbor) {
            apply();
        }
    }
    Process { id: cursorProc }
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
