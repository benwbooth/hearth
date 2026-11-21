import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Lock Screen (services/Lock.qml, lock/LockSurface.qml).
ColumnLayout {
    id: pane
    spacing: 14

    function set(key, v) { Settings.set("lockScreen." + key, v); }
    readonly property var c: Settings.lockScreen

    Label {
        Layout.fillWidth: true
        text: "The lock screen shows your wallpaper, the time and what's playing. Unlock it with your password or a fingerprint. When to lock is set in Sleep & Power."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    RowLayout {
        spacing: 10
        PushButton {
            text: "Lock Screen Now"
            onClicked: Lock.lock("manual")
        }
        PushButton {
            text: "Sleep & Power…"
            onClicked: Settings.openRequested("power")
        }
    }

    SettingsGroup {
        SettingsRow {
            label: "Require password after"
            note: "How long after the screen locks by itself (when you're away) a touch still opens it without your password."
            tip: "Locking with Super+L, the menu or before sleep always asks for the password at once."
            Dropdown {
                implicitWidth: 200
                options: [
                    { value: 0, label: "Immediately" },
                    { value: 5, label: "5 seconds" },
                    { value: 60, label: "1 minute" },
                    { value: 300, label: "5 minutes" },
                    { value: 900, label: "15 minutes" },
                    { value: 3600, label: "1 hour" }
                ]
                value: pane.c.grace
                onPicked: v => pane.set("grace", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Use the fingerprint reader"
            note: "Touch the reader to unlock; typing your password always works too."
            tip: "Needs the hearth-lock-fingerprint PAM service (or KDE's kde-fingerprint) and an enrolled finger (fprintd-enroll)."
            Toggle {
                checked: !!pane.c.fingerprint
                onToggled: c => pane.set("fingerprint", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Turn the screen off after"
            note: "While locked and nobody touches anything, the screens go dark; any key or mouse movement wakes them."
            Dropdown {
                implicitWidth: 200
                options: [
                    { value: 0, label: "Never" },
                    { value: 15, label: "15 seconds" },
                    { value: 30, label: "30 seconds" },
                    { value: 60, label: "1 minute" },
                    { value: 120, label: "2 minutes" },
                    { value: 300, label: "5 minutes" }
                ]
                value: pane.c.screenOff
                onPicked: v => pane.set("screenOff", v)
            }
        }
    }

    SettingsGroup {
        SettingsRow {
            label: "Clock"
            note: "Like the menu bar, or always 12- or 24-hour."
            Segmented {
                options: [{ value: "auto", label: "Like menu bar" }, { value: "12", label: "12-hour" }, { value: "24", label: "24-hour" }]
                value: pane.c.clock
                onPicked: v => pane.set("clock", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Date"
            note: "The date above the clock."
            Segmented {
                options: [{ value: "long", label: "Friday, November 20" }, { value: "short", label: "Fri Nov 20" }, { value: "none", label: "None" }]
                value: pane.c.dateFormat
                onPicked: v => pane.set("dateFormat", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Show what's playing"
            note: "Music and video controls under the clock (play, pause, skip) without unlocking."
            Toggle {
                checked: !!pane.c.showMedia
                onToggled: c => pane.set("showMedia", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Show how many notifications came in"
            note: "Only the count: what they say stays hidden until you unlock."
            Toggle {
                checked: !!pane.c.showNotifications
                onToggled: c => pane.set("showNotifications", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Show Sleep, Restart and Shut Down"
            note: "Buttons at the bottom; Restart and Shut Down ask first."
            Toggle {
                checked: !!pane.c.showPower
                onToggled: c => pane.set("showPower", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Animated wallpaper on the lock screen"
            note: "Videos and shaders keep moving behind the clock and settle to a still when you start typing. Off: a still picture."
            Toggle {
                checked: !!pane.c.animated
                onToggled: c => pane.set("animated", c)
            }
        }
    }
    Label {
        Layout.fillWidth: true
        text: "If the lock screen ever gets stuck: press Ctrl+Alt+F2, log in and run hearth-recover-lock: hearth restarts and shows the lock screen again (the session stays locked meanwhile)."
        color: Theme.fgDim
        font.pointSize: Theme.smallFontSize
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
}
