//@ pragma UseQApplication
//@ pragma NativeTextRendering
//@ pragma IconTheme breeze-dark
// Fixed id: state/cache dirs are otherwise keyed by the shell's path,
// which changes with every Nix build (losing pins, weather, wallpaper).
//@ pragma ShellId hearth
import QtQuick
import Quickshell
import "bar"
import "popups"
import "services"

ShellRoot {
    // Touch the singleton so swaync starts with the shell.
    // Touch singletons that own IPC targets (or start daemons): singletons
    // are created on first use, so e.g. `session` (Super+L) wouldn't exist.
    Component.onCompleted: { void Swaync; void Session; }
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    Osd {}
    BtPairDialog {}
    ZoneOverlay {}
    Switcher {}
    Overview {}
    WallpaperInfo {}
    Screenshot {}
}
