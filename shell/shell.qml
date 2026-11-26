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
    // Touch singletons that own IPC targets (or start daemons): singletons
    // are created on first use, so e.g. `session` (Super+L) wouldn't exist.
    Component.onCompleted: { void Notifications; void Session; void AppMenu; void Help; void Mouse; void Power; void Keyboard; void Lock; void Displays; void WindowRules; void Binds; void Clipboard; void Spotlight; void Voice; void Ai; void About; void ColorScheme; void TrayWindows; void DockMinimize; void Launchpad; void VolumeFeedback; }
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
    // FanzyZones: Hyprland Lua (hypr/fanzyzones.lua) or arbor's own zones
    // (services/ArborZones.qml).
    LazyLoader { active: Compositor.isHyprland || Compositor.isArbor; ZoneOverlay {} }
    Switcher {}
    Overview {}
    WallpaperInfo {}
    Screenshot {}
    ScreenshotEditor {}
    ZoneEditorWindow {}
    SettingsWindow {}
    HotCorners {}
    DisplayConfirm {}
    HelpWindow {}
    SpotlightWindow {}
    LaunchpadWindow {}
    VoiceOverlay {}
    AboutWindow {}
    PolkitDialog {}
    // The keyring's password prompt (services/KeyringPrompter).
    KeyringDialog {}
    // What apps ask through the desktop portal (services/Portal.qml):
    // permissions, Open With, printing, adding web apps.
    PortalDialog {}
    NotificationBanners {}
    NotificationCenter {}
}
