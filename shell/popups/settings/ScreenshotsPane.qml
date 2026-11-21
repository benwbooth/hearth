import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Screenshots (services/Screenshots.qml: the capture overlay,
// the result window and screen recording).
ColumnLayout {
    id: pane
    spacing: 14

    function o(k) { return Screenshots.opt(k); }
    function set(k, v) { Screenshots.setOpt(k, v); }

    Label {
        Layout.fillWidth: true
        text: "Print opens the screenshot tool: pick a region, a window or a screen, then copy, save, mark up or drag the picture into another app. Shift+Print takes the whole screen, Super+Print the active window. Record videos from the same tool; stop them from the menu bar."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    SettingsGroup {
        SettingsRow {
            label: "Print key"
            note: "What pressing Print does."
            Dropdown {
                implicitWidth: 230
                options: [
                    { value: "overlay", label: "Open the screenshot tool" },
                    { value: "region", label: "Pick a region" },
                    { value: "screen", label: "Take the whole screen" },
                    { value: "all", label: "Take all screens" },
                    { value: "activeWindow", label: "Take the active window" }
                ]
                value: pane.o("printAction")
                onPicked: v => pane.set("printAction", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "After taking a screenshot"
            note: "Show it in a window to copy, save or mark up — or just save it and show a notification."
            Dropdown {
                implicitWidth: 230
                options: [
                    { value: "editor", label: "Show the screenshot window" },
                    { value: "save", label: "Save it, no window" }
                ]
                value: pane.o("afterCapture")
                onPicked: v => pane.set("afterCapture", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Copy to the clipboard right away"
            note: "Every screenshot is copied as it's taken, ready to paste."
            Toggle { checked: !!pane.o("copyOnCapture"); onToggled: c => pane.set("copyOnCapture", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Save right away"
            note: "Every screenshot is saved into the folder below as it's taken."
            Toggle { checked: !!pane.o("autoSave"); onToggled: c => pane.set("autoSave", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Close the window after Copy"
            note: "Copy is often all you need: close the screenshot window once it's copied."
            Toggle { checked: !!pane.o("closeAfterCopy"); onToggled: c => pane.set("closeAfterCopy", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Close the window after Save"
            note: "Close the screenshot window once it's saved."
            Toggle { checked: !!pane.o("closeAfterSave"); onToggled: c => pane.set("closeAfterSave", c) }
        }
    }

    SettingsGroup {
        SettingsRow {
            label: "Include the mouse pointer"
            note: "Show the pointer in screenshots. You can also switch it in the tool's toolbar."
            Toggle { checked: !!pane.o("pointer"); onToggled: c => pane.set("pointer", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Window title bar and border"
            note: "Window screenshots include arbor's title bar (the traffic lights) and border."
            Toggle { checked: pane.o("decorations") !== false; onToggled: c => pane.set("decorations", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Window shadow"
            note: "Window screenshots include the soft shadow around the window."
            Toggle { checked: pane.o("shadow") !== false; onToggled: c => pane.set("shadow", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Remember the last region"
            note: "The tool starts with the rectangle you picked last time."
            Toggle { checked: pane.o("rememberRegion") !== false; onToggled: c => pane.set("rememberRegion", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Delay"
            note: "Wait before taking the picture, to open a menu first. Also in the tool's toolbar."
            Dropdown {
                implicitWidth: 160
                options: [0, 3, 5, 10].map(n => ({ value: n, label: n ? n + " seconds" : "No delay" }))
                value: Number(pane.o("delay")) || 0
                onPicked: v => pane.set("delay", v)
            }
        }
    }

    SettingsGroup {
        SettingsRow {
            label: "Save screenshots in"
            note: "Folder for saved screenshots (~ is your home folder)."
            TextBox {
                implicitWidth: 260
                text: pane.o("folder")
                onAccepted: pane.set("folder", text.trim() || Screenshots.defaults.folder)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "File name"
            note: "%Y year, %m month, %d day, %H hour, %M minute, %S second, %T window title."
            tip: "Example: Screenshot_%Y%m%d_%H%M%S gives Screenshot_20261120_211423.png. If the name is taken, _1, _2… is added."
            TextBox {
                implicitWidth: 260
                text: pane.o("fileName")
                onAccepted: pane.set("fileName", text.trim() || Screenshots.defaults.fileName)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Format"
            note: "PNG keeps every pixel; JPEG and WebP make smaller files."
            Segmented {
                options: [{ value: "png", label: "PNG" }, { value: "jpg", label: "JPEG" }, { value: "webp", label: "WebP" }]
                value: pane.o("format")
                onPicked: v => pane.set("format", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Quality"
            note: "For JPEG and WebP: higher looks better and makes bigger files."
            enabled: pane.o("format") !== "png"
            ValueSlider {
                implicitWidth: 220
                from: 50; to: 100; step: 1
                value: Number(pane.o("quality")) || 92
                onMoved: v => pane.set("quality", v)
            }
        }
    }

    SettingsGroup {
        SettingsRow {
            label: "Save recordings in"
            note: "Folder for screen recordings."
            TextBox {
                implicitWidth: 260
                text: pane.o("recordFolder")
                onAccepted: pane.set("recordFolder", text.trim() || Screenshots.defaults.recordFolder)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Video format"
            note: "MP4 (H.264) plays everywhere; WebM (VP9) is smaller and open."
            Segmented {
                options: [{ value: "mp4", label: "MP4" }, { value: "webm", label: "WebM" }]
                value: pane.o("recordFormat")
                onPicked: v => pane.set("recordFormat", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Record sound"
            note: "Also record audio from the microphone (or the source named below)."
            Toggle { checked: !!pane.o("recordAudio"); onToggled: c => pane.set("recordAudio", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Sound source"
            note: "Empty: the default microphone. A name ending in .monitor records what you hear."
            tip: "List the names with: pactl list short sources"
            enabled: !!pane.o("recordAudio")
            TextBox {
                implicitWidth: 260
                placeholder: "Default input"
                text: pane.o("recordAudioSource")
                onAccepted: pane.set("recordAudioSource", text.trim())
            }
        }
    }
}
