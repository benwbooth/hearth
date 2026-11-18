//@ pragma UseQApplication
//@ pragma NativeTextRendering
//@ pragma IconTheme breeze-dark
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
}
