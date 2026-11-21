import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Clipboard (services/Clipboard.qml keeps the history with
// cliphist; the menu bar's clipboard icon and Super+V show it).
ColumnLayout {
    id: pane
    spacing: 14

    readonly property var ignored: [].concat(Settings.clipboard.ignoreApps || [])
    function addApp(id) {
        id = (id || "").trim();
        if (!id || pane.ignored.some(a => a.toLowerCase() === id.toLowerCase())) return;
        Settings.set("clipboard.ignoreApps", pane.ignored.concat([id]));
    }
    function removeApp(id) { Settings.set("clipboard.ignoreApps", pane.ignored.filter(a => a !== id)); }
    // Open apps not ignored yet, for the "Add an open app" list.
    readonly property var openApps: {
        const seen = new Set();
        const out = [];
        for (const w of Compositor.windows) {
            const id = w.appId || "";
            if (!id || seen.has(id) || pane.ignored.indexOf(id) >= 0) continue;
            seen.add(id);
            out.push({ value: id, label: id });
        }
        return out.sort((a, b) => a.label.localeCompare(b.label));
    }

    Label {
        Layout.fillWidth: true
        text: "hearth remembers what you copy, like KDE's Klipper. Click the clipboard icon in the menu bar or press Super+V to copy something again."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        SettingsRow {
            label: "Keep a clipboard history"
            note: "Remember the text and pictures you copy. Off: nothing is recorded and the menu bar icon hides."
            Toggle {
                checked: Settings.clipboard.enabled !== false
                onToggled: c => Settings.set("clipboard.enabled", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "History size"
            note: "How many copied items to keep; the oldest go first. Pinned items are kept on top of these."
            enabled: Settings.clipboard.enabled !== false
            Dropdown {
                implicitWidth: 160
                options: [25, 50, 100, 200, 500, 1000].map(n => ({ value: n, label: n + " items" }))
                value: Number(Settings.clipboard.historySize) || 100
                onPicked: v => Settings.set("clipboard.historySize", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Include pictures"
            note: "Also keep copied images and screenshots (shown as thumbnails)."
            enabled: Settings.clipboard.enabled !== false
            Toggle {
                checked: Settings.clipboard.images !== false
                onToggled: c => Settings.set("clipboard.images", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Include selected text"
            note: "Also keep text you only select (the middle-click paste), not just what you copy."
            tip: "Linux has a second clipboard: selecting text puts it there, and a middle click pastes it. With this on, every selection is added to the history too, which can fill it quickly."
            enabled: Settings.clipboard.enabled !== false
            Toggle {
                checked: !!Settings.clipboard.primary
                onToggled: c => Settings.set("clipboard.primary", c)
            }
        }
    }
    SettingsGroup {
        SettingsRow {
            label: "Ignore passwords"
            note: "Don't keep what password managers (KeePassXC, KDE apps) mark as secret."
            enabled: Settings.clipboard.enabled !== false
            Toggle {
                checked: Settings.clipboard.ignoreSecrets !== false
                onToggled: c => Settings.set("clipboard.ignoreSecrets", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Clear when I log out"
            note: "Forget the history at the end of each session. Pinned items are always kept."
            tip: "The history is then kept in memory-backed storage that the system empties when you log out. Turning this on or off starts a fresh history."
            enabled: Settings.clipboard.enabled !== false
            Toggle {
                checked: !!Settings.clipboard.clearOnLogout
                onToggled: c => Settings.set("clipboard.clearOnLogout", c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Clear the history now"
            note: "Forget everything you copied; pinned items stay."
            PushButton {
                text: "Clear…"
                destructive: true
                tooltip: "Asks first"
                onClicked: confirm.visible = true
            }
        }
        RowLayout {
            id: confirm
            visible: false
            width: parent.width
            spacing: 8
            Label {
                Layout.fillWidth: true
                text: "Clear the clipboard history? This can't be undone."
                color: Theme.warn
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            PushButton { text: "Cancel"; onClicked: confirm.visible = false }
            PushButton {
                text: "Clear History"
                destructive: true
                onClicked: { Clipboard.clear(); confirm.visible = false; }
            }
        }
        Item { width: 1; height: confirm.visible ? 8 : 0 }
    }

    Label {
        Layout.fillWidth: true
        text: "Ignore these apps"
        font.weight: Font.DemiBold
    }
    Label {
        Layout.fillWidth: true
        Layout.topMargin: -10
        text: "What you copy while one of these apps is in front isn't kept (password managers, banking apps)."
        color: Theme.fgDim
        font.pointSize: Theme.smallFontSize
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        Repeater {
            model: pane.ignored
            delegate: SettingsRow {
                id: ign
                required property string modelData
                label: modelData
                PushButton {
                    text: "Remove"
                    tooltip: "Keep what you copy in " + ign.modelData + " again"
                    onClicked: pane.removeApp(ign.modelData)
                }
            }
        }
        SettingsRow {
            visible: pane.ignored.length === 0
            label: "No apps ignored"
            note: "Add one below: pick an open app, or type its app id."
        }
        SettingsDivider {}
        SettingsRow {
            label: "Add an open app"
            note: "Apps with a window open right now."
            Dropdown {
                implicitWidth: 220
                placeholder: pane.openApps.length ? "Choose…" : "No other apps open"
                enabled: pane.openApps.length > 0
                options: pane.openApps
                value: undefined
                onPicked: v => pane.addApp(v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Add by app id"
            note: "For example org.keepassxc.KeePassXC."
            RowLayout {
                spacing: 6
                TextBox {
                    id: appField
                    implicitWidth: 200
                    placeholder: "App id"
                    onAccepted: { pane.addApp(text); text = ""; }
                }
                PushButton {
                    text: "Add"
                    enabled: appField.text.trim() !== ""
                    onClicked: { pane.addApp(appField.text); appField.text = ""; }
                }
            }
        }
    }
}
