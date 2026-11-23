import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Hot Corners (popups/HotCorners.qml does the work).
ColumnLayout {
    id: pane
    spacing: 14

    readonly property var actions: [
        { value: "none", label: "Nothing", note: "The corner does nothing (and never gets in the way)." },
        { value: "overview", label: "Mission Control", note: "See all your windows at once (the overview)." },
        { value: "desktop", label: "Show Desktop", note: "Move to an empty desktop; again to come back." },
        { value: "lock", label: "Lock Screen", note: "Lock right away; your password opens it." },
        { value: "launchpad", label: "Launchpad", note: "Every installed app in a full-screen grid." },
        { value: "launcher", label: "Launcher", note: "Search apps, files and more." },
        { value: "notifications", label: "Notification Center", note: "Your notifications and Do Not Disturb." },
        { value: "displayoff", label: "Put Display to Sleep", note: "Turn the screens off; move the mouse to wake them." }
    ]
    function setCorner(key, v) { Settings.set("hotCorners." + key, v); }

    Label {
        Layout.fillWidth: true
        text: "Move the pointer into a corner of the screen and rest it there to do something, like on a Mac."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    // A small screen with a picker in each corner.
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 250
        radius: Theme.popupRadius
        color: Theme.bgAlt
        border.color: Theme.border
        Rectangle {
            id: screenPic
            anchors.centerIn: parent
            width: 300
            height: 170
            radius: 8
            color: Theme.dark ? "#1b2b3a" : "#cfe3f5"
            border.color: Theme.border
            border.width: 2
            Label {
                anchors.centerIn: parent
                text: "Your screen"
                color: Theme.fgDim
            }
        }
        Repeater {
            model: [
                { key: "topLeft", label: "Top left", left: true, top: true },
                { key: "topRight", label: "Top right", left: false, top: true },
                { key: "bottomLeft", label: "Bottom left", left: true, top: false },
                { key: "bottomRight", label: "Bottom right", left: false, top: false }
            ]
            Dropdown {
                id: dd
                required property var modelData
                width: 190
                x: modelData.left ? 16 : parent.width - width - 16
                y: modelData.top ? 16 : parent.height - height - 16
                options: pane.actions
                value: Settings.hotCorners[modelData.key] || "none"
                onPicked: v => pane.setCorner(modelData.key, v)
                listWidth: 300
                Tooltip {
                    anchorItem: dd
                    text: dd.modelData.label + " corner: what happens when the pointer rests there."
                    hovered: dd.containsMouse
                }
            }
        }
    }

    SettingsGroup {
        SettingsRow {
            label: "Wait before acting"
            note: "How long the pointer must rest in the corner first, so passing through doesn't set it off."
            ValueSlider {
                implicitWidth: 300
                from: 0; to: 1500; step: 50; suffix: " ms"
                value: Number(Settings.hotCorners.delay) || 0
                onMoved: v => Settings.set("hotCorners.delay", v)
            }
        }
    }
    Label {
        Layout.fillWidth: true
        text: "Tip: a corner that has an action catches clicks on its very last pixel; if a click there doesn't reach a button, click again."
        color: Theme.fgDim
        font.pointSize: Theme.smallFontSize
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
}
