import QtQuick
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// The menu bar's Help menu (like macOS's): type what you want to do and it
// finds shortcuts, settings and actions ("lock" -> "Lock screen  Super+L";
// Enter or a click runs/opens it), plus the guides.
BarButton {
    id: root
    icon: menuBarItem ? Symbols.info : "help-contextual"
    iconFallback: "help-about"
    implicitWidth: Theme.menuBarItemWidth
    tooltip: "Help: find a shortcut, setting or action, or read a guide"
    active: menu.open
    menuPopup: menu
    onClicked: if (!menuPress) menu.toggle()

    BarPopup {
        id: menu
        menuBarMenu: true
        anchorItem: root
        padding: Theme.menuPadding
        keyboardFocus: WlrKeyboardFocus.OnDemand
        onOpenChanged: if (open) { field.text = ""; focusSoon.restart(); }
        Timer { id: focusSoon; interval: 160; onTriggered: field.forceActiveFocus() }

        Column {
            width: 340
            spacing: 2

            Rectangle {
                width: parent.width
                height: 32
                radius: Theme.radius
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                border.color: field.activeFocus ? Theme.accent : "transparent"
                Icon { x: 9; anchors.verticalCenter: parent.verticalCenter; implicitSize: 16; name: "search" }
                TextInput {
                    id: field
                    x: 32
                    width: parent.width - 40
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    clip: true
                    Keys.onReturnPressed: if (results.length) root.run(results[0])
                    Keys.onEscapePressed: menu.close()
                    readonly property var results: Help.search(text)
                    Label {
                        visible: field.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search: e.g. lock, screenshot, dark mode"
                        color: Theme.fgDim
                    }
                }
            }

            Repeater {
                model: field.results
                MenuItem {
                    required property var modelData
                    required property int index
                    text: modelData.title
                    shortcut: modelData.keys
                    highlighted: index === 0
                    onTriggered: root.run(modelData)
                }
            }
            Label {
                visible: field.text.trim() !== "" && field.results.length === 0
                x: 8
                width: parent.width - 16
                height: 30
                text: "Nothing found. Try another word, or open Keyboard Shortcuts below."
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            MenuSeparator {}
            MenuItem { text: "Keyboard Shortcuts…"; shortcut: "Super+/"; onTriggered: root.guide("shortcuts") }
            MenuItem { text: "Trackpad Gestures…"; onTriggered: root.guide("gestures") }
            MenuItem { text: "How windows work…"; onTriggered: root.guide("windows") }
            MenuItem { text: "Getting Started"; onTriggered: root.guide("welcome") }
        }
    }

    function run(r) { menu.close(); Help.activate(r); }
    function guide(p) { menu.close(); Help.guideRequested(p, ""); }
}
