import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Sleep & Power (services/Power.qml runs swayidle with these).
ColumnLayout {
    id: pane
    spacing: 14

    function after(list) {
        return [{ value: 0, label: "Never" }].concat(list.map(m => ({ value: m * 60, label: m < 60 ? `After ${m} minute${m === 1 ? "" : "s"}` : `After ${m / 60} hour${m === 60 ? "" : "s"}` })));
    }
    readonly property var times: after([1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 120, 180])

    Label {
        visible: !Compositor.isArbor
        Layout.fillWidth: true
        text: "These settings work under the arbor compositor (on Hyprland, hypridle handles them)."
        color: Theme.warn
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    Label {
        Layout.fillWidth: true
        text: "When you haven't touched the mouse or keyboard for a while. Videos, games and presentations that ask to keep the screen on are respected."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        SettingsRow {
            label: "Turn the display off"
            note: "The screens go dark to save power; moving the mouse wakes them."
            Dropdown {
                implicitWidth: 200
                options: pane.times
                value: Settings.power.displayOff
                onPicked: v => Settings.set("power.displayOff", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Lock the screen"
            note: "Ask for your password after this long without use."
            Dropdown {
                implicitWidth: 200
                options: pane.times
                value: Settings.power.lock
                onPicked: v => Settings.set("power.lock", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Put the computer to sleep"
            note: "Sleep uses almost no power; press a key or the power button to wake it."
            Dropdown {
                implicitWidth: 200
                options: pane.times
                value: Settings.power.sleep
                onPicked: v => Settings.set("power.sleep", v)
            }
        }
    }
    SettingsGroup {
        SettingsRow {
            label: "Ask for the password after sleep"
            note: "Lock the screen as the computer goes to sleep, so waking it needs your password."
            Toggle {
                checked: !!Settings.power.lockOnSleep
                onToggled: c => Settings.set("power.lockOnSleep", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "When I press the power button"
            note: "What a short press of the computer's power button does."
            Dropdown {
                implicitWidth: 200
                options: [
                    { value: "menu", label: "Ask what to do", note: "Sleep, restart, shut down or log out." },
                    { value: "sleep", label: "Sleep" },
                    { value: "lock", label: "Lock the screen" },
                    { value: "displayoff", label: "Turn the display off" },
                    { value: "poweroff", label: "Shut down" },
                    { value: "nothing", label: "Do nothing" }
                ]
                value: Settings.power.powerButton
                onPicked: v => Settings.set("power.powerButton", v)
            }
        }
    }
    Label {
        Layout.fillWidth: true
        visible: Settings.power.lock > 0 && Settings.power.displayOff > 0 && Settings.power.displayOff < Settings.power.lock
        text: "The display turns off before the screen locks, so it will still be unlocked when you wake it until the lock time passes."
        color: Theme.fgDim
        font.pointSize: Theme.smallFontSize
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
}
