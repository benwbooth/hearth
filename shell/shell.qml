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
    Variants {
        model: Quickshell.screens
        Bar {}
    }

    NotificationPopups {}
    Osd {}
    PolkitDialog {}
    BtPairDialog {}
    ZoneOverlay {}
    Switcher {}
    WallpaperInfo {}
}
