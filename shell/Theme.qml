pragma Singleton
import QtQuick
import Quickshell
import "services"

// Colours and sizes. Breeze Dark / Breeze Light, picked by Settings
// (appearance.mode: dark, light, or auto by time of day), with the accent
// from settings. The `glass*` colours are the translucent macOS-style
// surfaces (menu bar, dock, menus): the compositor blurs what's behind them
// (hypr/hyprland.lua layer rules, arbor/hearth-layer-rules.kdl); without blur
// they are still opaque enough to read.
Singleton {
    id: root

    readonly property var ap: Settings.appearance
    SystemClock { id: clock; precision: SystemClock.Hours }
    readonly property bool dark: ap.mode === "light" ? false
                               : ap.mode === "auto" ? (clock.hours < 7 || clock.hours >= 19)
                               : true

    readonly property color bg: dark ? "#202326" : "#eff0f1"
    readonly property color bgAlt: dark ? "#292c30" : "#fcfcfc"
    readonly property color bgRaised: dark ? "#31363b" : "#ffffff"
    readonly property color border: dark ? "#3f444a" : "#c9ced3"
    readonly property color fg: dark ? "#fcfcfc" : "#232629"
    readonly property color fgDim: dark ? "#a1a9b1" : "#6e7882"
    readonly property color accent: ap.accent || "#3daee9"
    readonly property color accentDim: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.35 : 0.25)
    readonly property color accentText: "#ffffff"
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
    readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color selected: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color good: "#27ae60"
    readonly property color warn: "#f67400"
    readonly property color bad: "#da4453"

    // --- glass ---
    // 0 (opaque) .. 1 (clearest); "reduce transparency" makes it solid.
    readonly property real glass: ap.reduceTransparency ? 0 : Math.max(0, Math.min(1, ap.glass))
    function glassColor(base, minAlpha) {
        const a = 1 - glass * (1 - minAlpha);
        return Qt.rgba(base.r, base.g, base.b, a);
    }
    readonly property color glassBar: glassColor(dark ? Qt.rgba(0.10, 0.11, 0.12, 1) : Qt.rgba(0.95, 0.95, 0.96, 1), 0.34)
    // The menu bar (Settings > Menu Bar > Style): "glass" (a light tinted
    // strip with a specular rim), "transparent" (macOS 26: items float on
    // the wallpaper) or "solid". Reduce transparency forces solid.
    readonly property string menuBarStyle: ap.reduceTransparency ? "solid" : (Settings.menubar.style || "glass")
    // Glass strip opacity. Hyprland only blurs pixels above its
    // ignore_alpha (0.25, hypr/hyprland.lua), so it never goes below 0.28.
    readonly property real menuBarOpacity: Math.max(0.28, Math.min(0.95, Number(Settings.menubar.opacity) || 0.32))
    readonly property color menuBarTint: menuBarStyle === "solid" ? bg
        : dark ? Qt.rgba(0.19, 0.20, 0.23, menuBarOpacity) : Qt.rgba(0.97, 0.97, 0.98, menuBarOpacity)
    // Specular light on glass edges: strongest at the top-left, like a
    // light source above-left of the screen.
    readonly property real specular: dark ? 0.30 : 0.85
    readonly property color glassDock: glassColor(dark ? Qt.rgba(0.16, 0.17, 0.19, 1) : Qt.rgba(0.97, 0.97, 0.98, 1), 0.40)
    readonly property color glassDockSolid: glassColor(dark ? Qt.rgba(0.16, 0.17, 0.19, 1) : Qt.rgba(0.97, 0.97, 0.98, 1), 0.85)
    readonly property color glassMenu: glassColor(dark ? Qt.rgba(0.14, 0.15, 0.17, 1) : Qt.rgba(0.97, 0.97, 0.98, 1), 0.62)
    // The thin bright rim and darker outline that make glass read as a pane.
    readonly property color glassRim: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.75)
    readonly property color glassEdge: dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.16)
    // Under menu bar text: lifts it off busy wallpaper behind the glass.
    // Stronger on the transparent menu bar, where text sits on the wallpaper.
    readonly property color textHalo: menuBarStyle === "transparent"
        ? (dark ? Qt.rgba(0, 0, 0, 0.7) : Qt.rgba(1, 1, 1, 0.8))
        : (dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.6))
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.45 : 0.22)

    readonly property int barHeight: 44
    readonly property int menuBarHeight: 30
    readonly property int iconSize: 22
    readonly property int menuBarIconSize: 16
    readonly property int taskIconSize: 32
    readonly property int radius: 6
    readonly property int popupRadius: 10
    readonly property int spacing: 6

    // --- fonts ---
    // macOS uses SF Pro, which is Apple-licensed: used when it is installed,
    // never shipped. Otherwise Inter, its closest open relative, which the
    // hearth wrapper hands over in HEARTH_FONT_DIR (nixpkgs `inter`) so it
    // works without a system-wide install. Settings > Appearance > Font.
    readonly property string fontDir: Quickshell.env("HEARTH_FONT_DIR") || ""
    FontLoader {
        id: interFile
        source: root.fontDir ? "file://" + root.fontDir + "/Inter.ttc" : ""
    }
    readonly property var families: { void interFile.status; return Qt.fontFamilies(); }
    function hasFamily(f) { return families.indexOf(f) >= 0; }
    readonly property string sfFamily: hasFamily("SF Pro") ? "SF Pro" : hasFamily("SF Pro Text") ? "SF Pro Text" : ""
    readonly property string interFamily: hasFamily("Inter") ? "Inter" : hasFamily("Inter Variable") ? "Inter Variable" : ""
    readonly property string fontChoice: ap.font || "auto"   // "auto" | "sf" | "inter" | "noto"
    readonly property string fontFamily: fontChoice === "noto" ? "Noto Sans"
        : fontChoice === "inter" ? (interFamily || "Noto Sans")
        : (sfFamily || interFamily || "Noto Sans")
    // Large titles: the Display cut where there is one.
    readonly property string displayFontFamily: fontFamily === "Inter" && hasFamily("Inter Display") ? "Inter Display"
        : fontFamily.startsWith("SF Pro") && hasFamily("SF Pro Display") ? "SF Pro Display" : fontFamily
    // 10 pt = 13.3 logical px, macOS's 13 pt menu text; the menu bar uses
    // exactly 13 px like macOS.
    readonly property real fontSize: 10
    readonly property real menuBarFontSize: 9.75
    readonly property real smallFontSize: 8.5
    readonly property string monoFamily: "Hack"
}
