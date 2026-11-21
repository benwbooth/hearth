//@ pragma UseQApplication
//@ pragma NativeTextRendering
//@ pragma IconTheme breeze-dark
// Fixed id: state/cache dirs are otherwise keyed by the shell's path,
// which changes with every Nix build (losing pins, weather, wallpaper).
//@ pragma ShellId hearth
import QtQuick
import Quickshell
import "bar"
import "desktop"
import "lock"
import "popups"
import "services"

ShellRoot {
    // Touch the singleton so swaync starts with the shell.
    // Touch singletons that own IPC targets (or start daemons): singletons
    // are created on first use, so e.g. `session` (Super+L) wouldn't exist.
    Component.onCompleted: { void Swaync; void Session; void AppMenu; void Help; void Mouse; void Power; void Keyboard; void Lock; void Displays; void WindowRules; void Binds; void Clipboard; }
    // The wallpaper (services/Wallpaper.qml): hearth's own background
    // surface on every screen.
    Variants {
        model: Quickshell.screens
        Background {}
    }
    // Layout "mac" (default): menu bar + dock; "panel": the classic bottom
    // panel. Settings > Layout, or settings.json `layout`.
    Variants {
        model: Settings.mac ? Quickshell.screens : []
        MenuBar {}
    }
    Variants {
        model: Settings.mac ? Quickshell.screens : []
        Dock {}
    }
    Variants {
        model: Settings.mac ? [] : Quickshell.screens
        Bar {}
    }

    // hearth's lock screen (services/Lock.qml): ext-session-lock surfaces.
    LockScreen {}
    Osd {}
    BtPairDialog {}
    // FanzyZones is Hyprland Lua.
    LazyLoader { active: Compositor.isHyprland; ZoneOverlay {} }
    Switcher {}
    Overview {}
    WallpaperInfo {}
    Screenshot {}
    ScreenshotEditor {}
    SettingsWindow {}
    HotCorners {}
    DisplayConfirm {}
    HelpWindow {}
}
