//@ pragma NativeTextRendering
//@ pragma IconTheme breeze-dark
//@ pragma ShellId hearth-greeter
// hearth's login screen (README "Login screen"): `hearth-greeter` runs this
// as the `greeter` user inside a greeter-only arbor that greetd starts
// (nix/greeter.nix). Shares the lock screen's pieces (lock/, widgets/).
import QtQuick
import Quickshell
import Quickshell.Wayland
import "greeter"
import "services"

ShellRoot {
    id: shell
    // The screen with the password field: the first one, or the last one clicked.
    property string mainOutput: Quickshell.screens.length ? Quickshell.screens[0].name : ""

    Component.onCompleted: { void Greeter; void Keyboard; }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool isMain: modelData.name === shell.mainOutput
                                           || !Quickshell.screens.some(s => s.name === shell.mainOutput)
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "black"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hearth-greeter"
            WlrLayershell.keyboardFocus: isMain ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            GreeterSurface {
                anchors.fill: parent
                screen: win.modelData
                isMain: win.isMain
                MouseArea {
                    anchors.fill: parent
                    enabled: !win.isMain
                    onPressed: shell.mainOutput = win.modelData.name
                }
            }
        }
    }
}
