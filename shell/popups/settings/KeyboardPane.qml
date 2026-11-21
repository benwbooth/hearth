import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Keyboard (services/Keyboard.qml).
ColumnLayout {
    id: pane
    spacing: 14

    Label {
        visible: !Compositor.isArbor
        Layout.fillWidth: true
        text: "These settings work under the arbor compositor."
        color: Theme.warn
    }

    Label { text: "Layouts"; font.weight: Font.DemiBold }
    Label {
        Layout.fillWidth: true
        text: "Which letters your keys type. With more than one, switch between them with the key below (the first one is used at startup)."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        Repeater {
            model: Keyboard.layouts
            SettingsRow {
                id: lr
                required property var modelData
                required property int index
                label: Keyboard.describe(modelData)
                note: (modelData.variant ? `${modelData.layout} (${modelData.variant})` : modelData.layout)
                      + (index === 0 ? " · used at startup" : "")
                tip: "Keyboard layout " + (index + 1) + ". Use the arrows to change the order, × to remove it."
                Row {
                    spacing: 6
                    PushButton { text: "↑"; implicitWidth: 34; enabled: lr.index > 0; tooltip: "Move up"; onClicked: Keyboard.moveLayout(lr.index, -1) }
                    PushButton { text: "↓"; implicitWidth: 34; enabled: lr.index < Keyboard.layouts.length - 1; tooltip: "Move down"; onClicked: Keyboard.moveLayout(lr.index, 1) }
                    PushButton { text: "×"; implicitWidth: 34; enabled: Keyboard.layouts.length > 1; tooltip: "Remove this layout"; onClicked: Keyboard.removeLayout(lr.index) }
                }
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Add a layout"
            note: "Pick a language or keyboard style; type to search."
            Dropdown {
                implicitWidth: 260
                placeholder: "Add…"
                options: Keyboard.choices
                searchable: true
                listWidth: 380
                onPicked: v => Keyboard.addLayout(v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Switch layouts with"
            note: Keyboard.layouts.length > 1 ? "Press these keys together to go to the next layout." : "Add a second layout to use this."
            enabled: Keyboard.layouts.length > 1
            Dropdown {
                implicitWidth: 200
                options: [
                    { value: "grp:win_space_toggle", label: "Super+Space" },
                    { value: "grp:alt_shift_toggle", label: "Alt+Shift" },
                    { value: "grp:ctrl_shift_toggle", label: "Ctrl+Shift" },
                    { value: "grp:shifts_toggle", label: "Both Shift keys" },
                    { value: "grp:menu_toggle", label: "Menu key" },
                    { value: "", label: "No shortcut" }
                ]
                value: Keyboard.cfg.switchKey
                onPicked: v => Keyboard.set("switchKey", v)
            }
        }
    }

    Label { text: "Typing"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "Delay until repeat"
            note: "How long to hold a key before it starts repeating."
            ValueSlider {
                implicitWidth: 300
                from: 150; to: 1000; step: 25; suffix: " ms"
                value: Keyboard.cfg.repeatDelay
                onMoved: v => Keyboard.set("repeatDelay", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Key repeat rate"
            note: "How fast a held key repeats, in characters per second."
            ValueSlider {
                implicitWidth: 300
                from: 5; to: 60; step: 1; suffix: " /s"
                value: Keyboard.cfg.repeatRate
                onMoved: v => Keyboard.set("repeatRate", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Try it here"
            note: "Hold a key to test the repeat settings."
            TextBox { implicitWidth: 300; placeholder: "Type here" }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Num Lock on at startup"
            note: "The number pad types numbers (not arrows) right after you log in."
            Toggle {
                checked: !!Keyboard.cfg.numlock
                onToggled: c => Keyboard.set("numlock", c)
            }
        }
    }

    Label {
        visible: Keyboard.error !== ""
        Layout.fillWidth: true
        text: Keyboard.error
        color: Theme.bad
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        PushButton {
            text: "Use the Defaults"
            enabled: Keyboard.customized
            tooltip: "Forget the keyboard settings made here and use the ones from arbor's config."
            onClicked: Keyboard.reset()
        }
    }
}
