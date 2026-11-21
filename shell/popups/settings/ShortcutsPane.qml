import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../widgets"
import "../../services"
import "../.."

// Settings > Keyboard Shortcuts (services/Binds.qml): arbor's shortcuts,
// grouped and searchable; change the keys, turn one off, add your own; plus
// the shortcuts apps registered (when arbor has that IPC).
ColumnLayout {
    id: pane
    spacing: 14
    Component.onCompleted: Binds.refreshGlobals()

    property string query: ""
    // A pending change that clashes with another shortcut.
    property var clash: null      // { entry, combo, other }
    readonly property var groupOrder: ["Apps & Launcher", "Windows", "Workspaces & Overview", "Screenshots", "Sound, Media & Brightness", "System"]
    readonly property var shown: {
        const q = pane.query.trim().toLowerCase();
        const words = q ? q.split(/\s+/) : [];
        return Binds.effective.filter(e => words.every(w => (e.title + " " + Binds.pretty(e.key) + " " + e.key + " " + e.group + " " + e.action).toLowerCase().includes(w)));
    }
    readonly property var groups: {
        const out = [];
        for (const g of groupOrder) {
            const items = shown.filter(e => e.group === g);
            if (items.length) out.push({ name: g, items: items });
        }
        return out;
    }

    function tryKeys(entry, combo) {
        const other = Binds.conflict(combo, entry ? entry.key : "");
        if (other) { pane.clash = { entry: entry, combo: combo, other: other }; return; }
        pane.clash = null;
        if (entry) Binds.changeKeys(entry, combo);
        else addForm.combo = combo;
    }

    Label {
        visible: !Compositor.isArbor
        Layout.fillWidth: true
        text: "Shortcuts can be changed here under the arbor compositor."
        color: Theme.warn
    }
    Label {
        Layout.fillWidth: true
        text: "Click a shortcut's keys, then press the new ones. Changes work right away."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        TextBox {
            Layout.fillWidth: true
            placeholder: "Search shortcuts (name or keys)"
            onTextChanged: pane.query = text
        }
        PushButton {
            text: addForm.visible ? "Cancel" : "Add Shortcut…"
            tooltip: "Make a new shortcut: pick what it does, then press its keys."
            onClicked: { addForm.visible = !addForm.visible; addForm.combo = ""; }
        }
    }

    // A clash: ask before taking keys another shortcut uses.
    Rectangle {
        visible: pane.clash !== null
        Layout.fillWidth: true
        implicitHeight: clashCol.implicitHeight + 20
        radius: Theme.popupRadius
        color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.15)
        border.color: Theme.warn
        ColumnLayout {
            id: clashCol
            x: 12; y: 10
            width: parent.width - 24
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                text: pane.clash ? `${Binds.pretty(pane.clash.combo)} is already used for “${pane.clash.other.title}”.`
                    + (pane.clash.other.kind === "app" ? " Your shortcut will win over the app's." : " Using it here turns that one off.") : ""
            }
            RowLayout {
                Item { Layout.fillWidth: true }
                PushButton { text: "Cancel"; onClicked: pane.clash = null }
                PushButton {
                    text: "Use It Here"
                    primary: true
                    tooltip: "Give these keys to this shortcut."
                    onClicked: {
                        const c = pane.clash;
                        pane.clash = null;
                        if (c.entry) Binds.changeKeys(c.entry, c.combo);
                        else addForm.combo = c.combo;
                    }
                }
            }
        }
    }

    // --- add a shortcut ---
    SettingsGroup {
        id: addForm
        visible: false
        property string combo: ""
        property string kind: "action"     // "action" | "app" | "command"
        property string action: ""
        property string app: ""
        readonly property var appEntry: DesktopEntries.applications.values.find(e => e.id === app) || null
        readonly property string finalAction: kind === "action" ? action
            : kind === "app" ? (appEntry ? "spawn " + appEntry.command.map(a => ArborConfig.str(a)).join(" ") : "")
            : (cmd.text.trim() ? "spawn-sh " + ArborConfig.str(cmd.text.trim()) : "")
        SettingsRow {
            label: "What it does"
            note: "A built-in action, opening an app, or running a command."
            Segmented {
                options: [{ value: "action", label: "Action" }, { value: "app", label: "Open an app" }, { value: "command", label: "Command" }]
                value: addForm.kind
                onPicked: v => addForm.kind = v
            }
        }
        SettingsDivider {}
        SettingsRow {
            visible: addForm.kind === "action"
            label: "Action"
            Dropdown {
                implicitWidth: 300
                options: Binds.actionChoices.map(a => ({ value: a.value, label: a.label, note: a.group }))
                value: addForm.action
                searchable: true
                listWidth: 360
                onPicked: v => addForm.action = v
            }
        }
        SettingsRow {
            visible: addForm.kind === "app"
            label: "App"
            Dropdown {
                implicitWidth: 300
                options: DesktopEntries.applications.values.filter(e => !e.noDisplay)
                    .map(e => ({ value: e.id, label: e.name, icon: e.icon })).sort((a, b) => a.label.localeCompare(b.label))
                value: addForm.app
                searchable: true
                listWidth: 360
                onPicked: v => addForm.app = v
            }
        }
        SettingsRow {
            visible: addForm.kind === "command"
            label: "Command"
            note: "Run as in a terminal, e.g. notify-send hello"
            TextBox { id: cmd; implicitWidth: 300; placeholder: "command to run" }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Name (optional)"
            note: "Shown in Help's shortcut list."
            TextBox { id: title; implicitWidth: 300; placeholder: "e.g. Open my notes" }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Keys"
            KeyCapture {
                keys: addForm.combo
                emptyText: "Click to set"
                onCaptured: c => pane.tryKeys(null, c)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: ""
            PushButton {
                text: "Add"
                primary: true
                enabled: addForm.combo !== "" && addForm.finalAction !== ""
                onClicked: {
                    Binds.addBind(addForm.combo, addForm.finalAction, title.text.trim());
                    addForm.visible = false;
                    addForm.combo = "";
                    title.text = "";
                    cmd.text = "";
                }
            }
        }
    }

    // --- the list ---
    Repeater {
        model: pane.groups
        ColumnLayout {
            id: grp
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            Label { text: grp.modelData.name; font.weight: Font.DemiBold }
            SettingsGroup {
                Repeater {
                    model: grp.modelData.items
                    SettingsRow {
                        id: br
                        required property var modelData
                        required property int index
                        label: modelData.off ? modelData.title + " (off)" : modelData.title
                        note: modelData.source === "added" ? "Added by you"
                            : modelData.source === "changed" ? (modelData.off ? `Turned off (was ${Binds.pretty(modelData.key)})` : "Changed by you") : ""
                        tip: modelData.action
                        Row {
                            spacing: 6
                            KeyCapture {
                                visible: !br.modelData.off
                                keys: br.modelData.key
                                onCaptured: c => pane.tryKeys(br.modelData, c)
                            }
                            PushButton {
                                visible: !br.modelData.off
                                text: br.modelData.source === "added" ? "Remove" : "Turn Off"
                                tooltip: br.modelData.source === "added" ? "Delete this shortcut." : "These keys will do nothing (Reset brings it back)."
                                onClicked: Binds.turnOff(br.modelData)
                            }
                            PushButton {
                                visible: br.modelData.source === "changed"
                                text: "Reset"
                                tooltip: "Back to arbor's default for " + Binds.pretty(br.modelData.key) + "."
                                onClicked: Binds.resetBind(br.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
    Label {
        visible: pane.groups.length === 0 && Compositor.isArbor
        text: pane.query ? "No shortcut matches “" + pane.query + "”." : "Reading arbor's shortcuts…"
        color: Theme.fgDim
    }

    // --- app shortcuts ---
    Label { visible: Binds.globalSupported; text: "App shortcuts"; font.weight: Font.DemiBold }
    Label {
        visible: Binds.globalSupported
        Layout.fillWidth: true
        text: Binds.globals.length ? "Shortcuts apps asked for. They work everywhere, even when the app isn't in front. The shortcuts above win if both use the same keys."
                                   : "No app has asked for a shortcut yet. Apps such as OBS or Discord can, and theirs show up here."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        visible: Binds.globalSupported && Binds.globals.length > 0
        Repeater {
            model: Binds.globals
            SettingsRow {
                id: gr
                required property var modelData
                label: modelData.description || modelData.id
                note: (modelData.app_id || "Unknown app") + (modelData.active ? "" : " · not running")
                tip: "Shortcut \"" + modelData.id + "\" of " + (modelData.app_id || "an app")
                     + (modelData.preferred_trigger ? ". The app suggested " + modelData.preferred_trigger + "." : ".")
                Row {
                    spacing: 6
                    KeyCapture {
                        keys: gr.modelData.trigger || ""
                        onCaptured: c => {
                            const other = Binds.conflict(c, gr.modelData.trigger || "");
                            if (other) Binds.globalError = `${Binds.pretty(c)} is already used for “${other.title}”. Pick other keys.`;
                            else Binds.setGlobal(gr.modelData, c);
                        }
                    }
                    PushButton {
                        text: "Clear"
                        enabled: !!gr.modelData.trigger
                        tooltip: "Take the keys away from this app shortcut."
                        onClicked: Binds.setGlobal(gr.modelData, null)
                    }
                }
            }
        }
    }
    Label {
        visible: Binds.globalError !== ""
        Layout.fillWidth: true
        text: Binds.globalError
        color: Theme.bad
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    Label {
        visible: Binds.error !== ""
        Layout.fillWidth: true
        text: Binds.error
        color: Theme.bad
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    RowLayout {
        Layout.fillWidth: true
        Item { Layout.fillWidth: true }
        PushButton {
            text: "Reset All Shortcuts"
            enabled: Object.keys(Binds.overrides).length > 0
            tooltip: "Forget every change made here and use arbor's default shortcuts."
            onClicked: Binds.resetAll()
        }
    }
}
