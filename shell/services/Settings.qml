pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// User settings, ~/.config/hearth/settings.json, edited by the Settings
// window (popups/SettingsWindow.qml) and applied live. Keys are dotted paths
// into the JSON ("dock.size"); anything missing falls back to `defaults`.
//
//   hearth-ipc call settings open
//   hearth-ipc call settings set dock.size 64        (value is JSON)
//   hearth-ipc call settings get dock
//   hearth-ipc call settings reset dock.size
// HEARTH_LAYOUT=mac|panel overrides `layout` (tests).
Singleton {
    id: root

    readonly property var defaults: ({
        layout: "mac",                  // "mac" (top bar + dock) | "panel" (classic bottom panel)
        appearance: {
            mode: "dark",               // "dark" | "light" | "auto" (light 7:00-19:00)
            accent: "#3daee9",
            glass: 0.55,                // 0 = opaque .. 1 = most transparent
            reduceTransparency: false,
            realGlass: true,            // arbor: the compositor draws refracting liquid glass under panes
            realGlassStrength: 1.0,     // 0..1: refraction, blur, rim and vibrancy together
            font: "auto",               // "auto" (SF Pro if installed, else Inter) | "sf" | "inter" | "noto"
            cursor: "adwaita"           // "adwaita" | "macos" (apple-cursor's macOS theme, if installed) | "breeze"
        },
        menubar: {
            autohide: false,
            style: "transparent",       // "transparent" (macOS 26 default) | "glass" | "solid"
            opacity: 0.36,              // glass strip opacity, 0.32 .. 0.95
            showSysMonitor: true,       // treetop's CPU/memory/GPU graphs
            monochromeIcons: true,      // status icons in the text colour, like SF Symbols
            showAppName: true,
            logo: "nixos",              // "nixos" | "penguin" | "none"   (shell/assets/<name>.svg)
            clock24h: true,
            showDate: true,
            showWeekday: true,
            showSeconds: false,
            hiddenIndicators: []        // ipcNames from bar/Tray.qml
        },
        dock: {
            size: 54,                   // icon px (macOS's 48 pt default)
            magnify: true,
            magnifySize: 80,            // icon px under the pointer
            position: "bottom",         // "bottom" | "left" | "right"
            autohide: true,
            autohideDelay: 250,         // ms after the pointer leaves
            showDelay: 120,             // ms at the edge before it shows (just enough that
                                        // passing the edge on the way somewhere doesn't pop it)
            animationMs: 220,           // slide in/out
            showIndicators: true,
            showRecents: true,          // recently used, unpinned apps
            recents: [],                // kept by the dock
            minimizeEffect: "scale",    // "scale" | "genie"
            minimizeIntoApp: false
        },
        notifications: {
            timeout: 6,
            showOnTop: true             // position follows the bar
        },
        // Hot corners (services/HotCorners.qml): "none" | "overview" |
        // "desktop" | "lock" | "launcher" | "notifications" | "displayoff"
        hotCorners: {
            topLeft: "none",
            topRight: "none",
            bottomLeft: "none",
            bottomRight: "none",
            delay: 250                  // ms the pointer rests in the corner first
        },
        // Sleep & power (services/Power.qml runs swayidle under arbor).
        // Seconds; 0 = never.
        power: {
            displayOff: 900,
            lock: 600,
            sleep: 0,
            lockOnSleep: true,          // ask for the password after sleep
            powerButton: "menu"         // "menu" | "sleep" | "lock" | "poweroff" | "displayoff" | "nothing"
        },
        // Lock screen (services/Lock.qml, lock/LockScreen.qml).
        lockScreen: {
            clock: "auto",              // "auto" (like the menu bar) | "12" | "24"
            dateFormat: "long",         // "long" (Friday, November 20) | "short" (Fri Nov 20) | "none"
            showMedia: true,            // now playing controls
            showNotifications: true,    // how many notifications came in
            showPower: true,            // Sleep / Restart / Shut Down buttons
            grace: 0,                   // seconds after an idle lock that need no password
            fingerprint: true,          // unlock with the fingerprint reader as well as the password
            animated: true,             // play video/shader wallpapers on the lock screen
            screenOff: 60               // seconds without input before the locked screens go dark; 0 = never
        },
        // Clipboard history (services/Clipboard.qml: cliphist + wl-paste).
        clipboard: {
            enabled: true,
            historySize: 100,           // items kept (pinned ones don't count)
            images: true,               // keep copied pictures too
            primary: false,             // also keep selected text (middle-click paste)
            ignoreSecrets: true,        // skip what password managers mark secret
            ignoreApps: [],             // app ids: copies made in them aren't kept
            clearOnLogout: false        // forget the history (not pins) when you log out
        },
        // Wallpaper (services/Wallpaper.qml, drawn by desktop/Background.qml).
        // displays: output name or "*" (all) -> what it shows:
        //   { type: "potd", source: "bing" } | { type: "image", path }
        //   { type: "folder", path, interval (min), shuffle, recursive }
        //   { type: "dynamic", path, index } | { type: "video", path }
        //   { type: "shader", path ("builtin:aurora" or a .frag/.glsl) }
        //   { type: "we", path (Wallpaper Engine project dir) }
        wallpaper: {
            displays: { "*": { type: "potd", source: "bing" } },
            fit: "fill",                // "fill" | "fit" | "center" | "tile"
            smartCrop: true,            // fill: crop around the interesting part (libvips attention)
            stillOnly: false,           // never animate: videos, shaders and Wallpaper Engine show a still
            fps: 30,                    // shaders and Wallpaper Engine
            shaderScale: 0.5,           // shaders render at this fraction of the screen's pixels
            pauseCovered: true,         // pause animation on a screen covered by windows
            pauseFullscreen: true,      // pause everywhere while any app is full screen (games)
            pauseBattery: true,
            pauseIdle: true,            // pause once the screen locks or turns off when idle
            weAudio: false,             // Wallpaper Engine sounds
            weVolume: 15,
            lockScreen: true,           // copy it for the lock and login screens
            sources: {},                // per source options: { interval (min), query, ... }
            folders: [],                // slideshow folders: [{ path, interval, shuffle, recursive }]
            added: [],                  // pictures/videos/shaders/dynamic sets added by hand: [{ type, path }]
            extraDirs: []               // more folders to look in for videos, shaders and dynamic sets
        }
    })

    property var data: ({})
    property bool loaded: false

    readonly property string dir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hearth"
    readonly property string path: dir + "/settings.json"

    function lookup(obj, key) {
        let o = obj;
        for (const p of key.split(".")) {
            if (o === null || o === undefined || typeof o !== "object" || !(p in o)) return undefined;
            o = o[p];
        }
        return o;
    }
    function get(key) {
        const v = lookup(root.data, key);
        return v !== undefined ? v : lookup(root.defaults, key);
    }
    function set(key, value) {
        const d = JSON.parse(JSON.stringify(root.data || {}));
        const parts = key.split(".");
        let o = d;
        for (let i = 0; i < parts.length - 1; i++) {
            if (typeof o[parts[i]] !== "object" || o[parts[i]] === null) o[parts[i]] = {};
            o = o[parts[i]];
        }
        if (value === undefined) delete o[parts[parts.length - 1]];
        else o[parts[parts.length - 1]] = value;
        root.data = d;
        saveSoon.restart();
    }
    function reset(key) { set(key, undefined); }

    // Convenience bindings (re-evaluate whenever `data` changes).
    readonly property string layout: Quickshell.env("HEARTH_LAYOUT") || get("layout")
    readonly property bool mac: layout !== "panel"
    readonly property var appearance: { void root.data; return Object.assign({}, defaults.appearance, data.appearance || {}); }
    readonly property var menubar: { void root.data; return Object.assign({}, defaults.menubar, data.menubar || {}); }
    readonly property var dock: { void root.data; return Object.assign({}, defaults.dock, data.dock || {}); }
    readonly property var notifications: { void root.data; return Object.assign({}, defaults.notifications, data.notifications || {}); }
    readonly property var hotCorners: { void root.data; return Object.assign({}, defaults.hotCorners, data.hotCorners || {}); }
    readonly property var power: { void root.data; return Object.assign({}, defaults.power, data.power || {}); }
    readonly property var lockScreen: { void root.data; return Object.assign({}, defaults.lockScreen, data.lockScreen || {}); }
    readonly property var clipboard: { void root.data; return Object.assign({}, defaults.clipboard, data.clipboard || {}); }
    readonly property var wallpaper: { void root.data; return Object.assign({}, defaults.wallpaper, data.wallpaper || {}); }

    // pane: "" (last used) or a Settings window pane id ("dock", ...).
    signal openRequested(string pane)

    IpcHandler {
        target: "settings"
        function open(): void { root.openRequested(""); }
        function openPane(pane: string): void { root.openRequested(pane); }
        function set(key: string, json: string): string {
            let v;
            try { v = JSON.parse(json); } catch (e) { v = json; }
            root.set(key, v);
            return JSON.stringify(root.get(key));
        }
        function get(key: string): string { return JSON.stringify(key ? root.get(key) : root.data, null, 2); }
        function reset(key: string): void { root.reset(key); }
    }

    Timer {
        id: saveSoon
        interval: 250
        onTriggered: {
            mkdir.running = true;
        }
    }
    // The config dir may not exist yet; FileView writes atomically after.
    Process {
        id: mkdir
        command: ["mkdir", "-p", root.dir]
        onExited: file.setText(JSON.stringify(root.data, null, 2) + "\n")
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (JSON.stringify(d) !== JSON.stringify(root.data)) root.data = d;
            } catch (e) { console.warn("settings.json:", e); }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
}
