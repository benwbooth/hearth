import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"
import ".."

// Hot corners (Settings > Desktop & Dock > Hot Corners), like macOS: push
// the pointer into a screen corner and rest it there for `delay` ms to run
// that corner's action. Each corner with an action gets an invisible 1 px
// layer-shell surface on every screen; corners set to "Nothing" get none,
// so they never take a click. A click that lands on a trigger isn't lost
// for long: the trigger steps aside for a moment so the next click reaches
// what's under it.
Scope {
    id: root
    readonly property var hc: Settings.hotCorners

    // Show Desktop: an empty workspace, and back again.
    property var desktopFrom: null
    function showDesktop() {
        const ws = Compositor.focusedWorkspace;
        if (desktopFrom !== null && ws && Compositor.windowsOn(ws.id).length === 0) {
            Compositor.focusWorkspace(desktopFrom);
            desktopFrom = null;
        } else {
            desktopFrom = ws ? ws.id : null;
            Compositor.focusEmptyWorkspace();
        }
    }

    function run(action) {
        switch (action) {
        case "overview":
            if (Compositor.isArbor) Compositor.arborAction("ToggleOverview", {});
            else ShellState.overviewRequested();
            break;
        case "desktop": showDesktop(); break;
        case "lock": Session.run("lock"); break;
        case "launcher": Quickshell.execDetached(["vicinae", "toggle"]); break;
        case "notifications": Notifications.toggleCenter(); break;
        case "displayoff":
            if (Compositor.isArbor) Compositor.arborAction("PowerOffMonitors", {});
            else Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"off\" })"]);
            break;
        }
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: perScreen
            required property var modelData
            Variants {
                model: [
                    { key: "topLeft", top: true, left: true },
                    { key: "topRight", top: true, left: false },
                    { key: "bottomLeft", top: false, left: true },
                    { key: "bottomRight", top: false, left: false }
                ]
                Scope {
                    id: corner
                    required property var modelData
                    readonly property string action: root.hc[modelData.key] || "none"
                    LazyLoader {
                        active: corner.action !== "none"
                        PanelWindow {
                            id: trig
                            screen: perScreen.modelData
                            WlrLayershell.namespace: "hearth-hotcorner"
                            WlrLayershell.layer: WlrLayer.Overlay
                            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                            exclusionMode: ExclusionMode.Ignore
                            anchors.top: corner.modelData.top
                            anchors.bottom: !corner.modelData.top
                            anchors.left: corner.modelData.left
                            anchors.right: !corner.modelData.left
                            implicitWidth: 1
                            implicitHeight: 1
                            color: "transparent"
                            property bool stepAside: false
                            property bool fired: false
                            mask: trig.stepAside ? noInput : allInput
                            Region { id: noInput }
                            Region { id: allInput; item: area }

                            MouseArea {
                                id: area
                                anchors.fill: parent
                                hoverEnabled: true
                                onContainsMouseChanged: {
                                    if (containsMouse) { trig.fired = false; wait.restart(); }
                                    else wait.stop();
                                }
                                onPressed: { wait.stop(); trig.stepAside = true; back.restart(); }
                            }
                            Timer {
                                id: wait
                                interval: Math.max(0, Number(root.hc.delay) || 0)
                                onTriggered: if (area.containsMouse && !trig.fired) { trig.fired = true; root.run(corner.action); }
                            }
                            Timer { id: back; interval: 1500; onTriggered: trig.stepAside = false }
                        }
                    }
                }
            }
        }
    }
}
