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
    // The menu bar (Settings > Menu Bar > Style): "transparent" (macOS 26's
    // default: items float on the wallpaper over a faint shade), "glass"
    // (a liquid-glass strip, macOS's "Show menu bar background") or
    // "solid". Reduce transparency forces solid.
    readonly property string menuBarStyle: ap.reduceTransparency ? "solid" : (Settings.menubar.style || "transparent")
    // Glass strip opacity. Hyprland only blurs pixels above its
    // ignore_alpha (0.3, hypr/hyprland.lua), so it never goes below 0.32.
    readonly property real menuBarOpacity: Math.max(0.32, Math.min(0.95, Number(Settings.menubar.opacity) || 0.36))
    readonly property color menuBarTint: menuBarStyle === "solid" ? bg
        : dark ? Qt.rgba(0.19, 0.20, 0.23, menuBarOpacity) : Qt.rgba(0.97, 0.97, 0.98, menuBarOpacity)
    // Specular light on glass edges (widgets/GlassFrame.qml, shaders/glass.frag):
    // lit from the top-left, reflected at the bottom-right.
    readonly property real specular: dark ? 0.42 : 0.9
    // Light gathered along the edges (lensing) and the sheen at the top.
    readonly property real glassGlow: dark ? 0.16 : 0.32
    readonly property real glassSheen: dark ? 0.05 : 0.16
    // Liquid glass "regular" (menus, popovers, tooltips) and the clearer
    // Dock glass. Tahoe's menus are fairly dense; the Dock is clearer.
    readonly property color glassMenu: glassColor(dark ? Qt.rgba(0.15, 0.155, 0.17, 1) : Qt.rgba(0.975, 0.975, 0.98, 1), 0.52)
    readonly property color glassDock: glassColor(dark ? Qt.rgba(0.17, 0.18, 0.20, 1) : Qt.rgba(0.98, 0.98, 0.99, 1), 0.36)
    readonly property color glassDockSolid: glassColor(dark ? Qt.rgba(0.16, 0.17, 0.19, 1) : Qt.rgba(0.97, 0.97, 0.98, 1), 0.85)
    readonly property color glassTip: glassColor(dark ? Qt.rgba(0.16, 0.165, 0.18, 1) : Qt.rgba(0.98, 0.98, 0.985, 1), 0.78)
    // The thin bright rim and darker outline that make glass read as a pane.
    readonly property color glassRim: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.75)
    readonly property color glassEdge: dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.16)
    // Under menu bar text: lifts it off busy wallpaper (a soft blurred
    // shade, MenuBar.qml), stronger on the transparent bar.
    readonly property color textHalo: menuBarStyle === "transparent"
        ? (dark ? Qt.rgba(0, 0, 0, 0.7) : Qt.rgba(1, 1, 1, 0.8))
        : (dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.6))
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.45 : 0.22)
    // Drop shadows under glass (menus, popovers, Dock, tooltips): large,
    // soft and faint like macOS's window shadows. Peak opacity stays under
    // Hyprland's ignore_alpha (0.3) so the blur never spreads into them.
    readonly property real shadowOpacity: dark ? 0.27 : 0.17
    readonly property real menuShadowBlur: 26
    readonly property real menuShadowY: 9

    // --- macOS 26 metrics (README "Look") ---
    // Logical px per macOS point. Apple's 5K at 2x is 109 pt/inch; Ben's
    // 34" 5120x2160 at 4/3 is ~122 logical px/inch, so 1 pt = 1.125 px
    // keeps everything the physical size it is on a Mac.
    readonly property real pt: 1.125
    readonly property int barHeight: 44
    readonly property int menuBarHeight: Math.round(24 * pt)          // 24 pt (HIG)
    readonly property int iconSize: 22
    readonly property int menuBarIconSize: 17                         // ~15 pt SF Symbol
    readonly property int menuBarItemWidth: 31                        // status item slot
    readonly property int taskIconSize: 32
    readonly property int radius: 6
    readonly property int popupRadius: Math.round(12 * pt)            // Tahoe menus: 12 pt
    readonly property int menuRadius: popupRadius
    readonly property int menuPadding: Math.round(4 * pt)             // around the rows
    readonly property int menuRowHeight: Math.round(24 * pt)          // 13 pt text + 2 x 4 pt
    readonly property int menuSelectionRadius: Math.round(8 * pt)     // 12 - 4: concentric
    readonly property int menuTextInset: Math.round(10 * pt)
    readonly property int menuGutter: Math.round(20 * pt)             // checkmark / icon column
    readonly property int spacing: 6
    // Selection and highlight colours (accent fill, white text in menus;
    // a translucent capsule behind open menu bar items).
    readonly property color menuBarHighlight: dark || menuBarStyle === "transparent"
        ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.11)
    readonly property color menuSeparator: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.11)
    readonly property color fgDisabled: dark ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0, 0, 0, 0.26)
    readonly property color fgSecondary: dark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.5)

    // --- motion (README "Look": timings and their sources) ---
    // Menus: appear at once with a short fade/scale from the anchor, fade
    // out a little slower; switching between open menu bar menus is
    // instant, like macOS.
    readonly property int menuInMs: 160
    readonly property int menuOutMs: 180
    readonly property int submenuDelayMs: 120     // hover before a submenu opens
    readonly property int tooltipDelayMs: 800      // macOS help tags: ~1 s
    readonly property int labelFadeMs: 120

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
    // Body text in hearth's own windows.
    readonly property real fontSize: 10
    readonly property real smallFontSize: 8.5
    // macOS's 13 pt menu font (menu bar, menus, Dock labels) at `pt` scale:
    // 14.6 px for SF Pro. Inter runs about 4% larger at the same size, so
    // it gets 12.5 pt's worth (14 px) to match SF's x-height and width.
    readonly property bool usingSF: fontFamily.startsWith("SF Pro")
    function macPt(points) { return points * pt * (usingSF ? 1 : 0.962) * 0.75; }
    readonly property real menuFontSize: macPt(13)
    readonly property real menuBarFontSize: menuFontSize
    readonly property real menuSmallFontSize: macPt(11)
    // SF Pro Text tracks 13 pt at -0.08 pt; Inter's dynamic metrics give
    // the same (-0.6%) at 14 px.
    readonly property real menuTracking: -0.09
    readonly property string monoFamily: "Hack"
}
