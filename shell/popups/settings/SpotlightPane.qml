import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import "../../widgets"
import "../../services"
import "../.."

// Settings > Spotlight (services/Spotlight.qml): what Spotlight shows, which
// folders the indexer (recoll, hearth-indexer.service) reads, and what it
// leaves out.
ColumnLayout {
    id: pane
    spacing: 14

    readonly property var cfg: Spotlight.cfg
    readonly property string home: Quickshell.env("HOME")
    function tilde(p) { return p.startsWith(home) ? "~" + p.slice(home.length) : p; }
    function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")); }

    Component.onCompleted: Spotlight.requestStatus()
    Timer { interval: 3000; running: true; repeat: true; onTriggered: Spotlight.requestStatus() }
    readonly property var st: Spotlight.status

    Label {
        Layout.fillWidth: true
        text: "Spotlight finds apps, documents, folders, pictures and settings, and does sums and conversions as you type. Press " + Spotlight.shortcutText + " or click the magnifier in the menu bar."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    SettingsGroup {
        SettingsRow {
            label: "Index"
            note: {
                if (pane.st.indexer === "active" && pane.st.phase && pane.st.phase !== "idle" && pane.st.phase !== "done" && pane.st.total)
                    return `Indexing: ${pane.st.files} of ${pane.st.total} files…`;
                if (pane.st.indexer === "active") return pane.st.hasIndex ? "Up to date, and watching for changes." : "Starting: the first pass begins a minute after login.";
                if (pane.st.indexer === "inactive" || pane.st.indexer === "failed")
                    return "The indexer isn't running, so only apps and settings are found. Turn on services.hearth-ai in the NixOS config, or start it below.";
                return "Checking…";
            }
            tip: "hearth uses recoll to index files. It reads new and changed files at low priority and then only reacts when files change, so it costs nearly nothing while you work."
            PushButton {
                text: pane.st.indexer === "active" ? "Rebuild" : "Start"
                tooltip: pane.st.indexer === "active" ? "Read every file again (takes a while for big folders)" : "Start the indexer now (hearth-indexer.service)"
                onClicked: Spotlight.reindex()
            }
        }
    }

    Label { text: "Search results"; font.weight: Font.DemiBold }
    SettingsGroup {
        Repeater {
            model: [
                { key: "apps", label: "Applications", note: "Apps installed on this computer." },
                { key: "documents", label: "Documents", note: "Text, PDFs, office files: by name and by what's inside." },
                { key: "folders", label: "Folders", note: "Folders whose names match." },
                { key: "images", label: "Images", note: "Pictures and photos, with thumbnails." },
                { key: "settings", label: "System Settings", note: "hearth Settings panes, like Wallpaper or Displays." },
                { key: "actions", label: "Actions", note: "Things hearth can do right away: lock, screenshot, next wallpaper…" },
                { key: "calculator", label: "Calculator and conversions", note: "Type 2^10, 15% of 80, 5 ft to m, 72F in C or 100 USD in EUR." },
                { key: "other", label: "Other files", note: "Music, videos and everything else." }
            ]
            Column {
                id: cat
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                spacing: 0
                SettingsDivider { visible: cat.index > 0 }
                SettingsRow {
                    label: cat.modelData.label
                    note: cat.modelData.note
                    Toggle {
                        checked: pane.cfg.categories[cat.modelData.key] !== false
                        onToggled: c => Settings.set("spotlight.categories." + cat.modelData.key, c)
                    }
                }
            }
        }
    }
    SettingsGroup {
        SettingsRow {
            label: "Ask hearth"
            note: "Offer to hand what you typed to the assistant (Settings > AI chooses the model)."
            Toggle { checked: pane.cfg.ask !== false; onToggled: c => Settings.set("spotlight.ask", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Web suggestions"
            note: "Show search suggestions from the web as you type."
            tip: "Off by default: with this on, what you type in Spotlight is sent to DuckDuckGo's suggestion service. Nothing else leaves your computer."
            Toggle { checked: !!pane.cfg.web; onToggled: c => Settings.set("spotlight.web", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Keyboard shortcut"
            note: Spotlight.shortcutText + " opens Spotlight."
            PushButton { text: "Change…"; tooltip: "Settings > Keyboard Shortcuts"; onClicked: Settings.openRequested("shortcuts") }
        }
    }

    Label { text: "Folders to search"; font.weight: Font.DemiBold }
    SettingsGroup {
        Repeater {
            model: pane.cfg.folders
            Column {
                id: fr
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                spacing: 0
                SettingsDivider { visible: fr.index > 0 }
                SettingsRow {
                    label: fr.modelData
                    PushButton {
                        text: "Remove"
                        tooltip: "Stop indexing this folder (its files disappear from Spotlight)"
                        onClicked: Settings.set("spotlight.folders", pane.cfg.folders.filter(f => f !== fr.modelData))
                    }
                }
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Add a folder"
            note: "Everything inside it, including subfolders, becomes searchable."
            PushButton { text: "Add Folder…"; onClicked: addDialog.open() }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Search inside files"
            note: "Index the text in documents, not just their names. Off: smaller index, names only."
            Toggle { checked: pane.cfg.contents !== false; onToggled: c => Settings.set("spotlight.contents", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Include hidden files"
            note: "Files and folders whose names start with a dot (settings of apps, mostly)."
            Toggle { checked: !!pane.cfg.hidden; onToggled: c => Settings.set("spotlight.hidden", c) }
        }
    }

    Label { text: "Privacy"; font.weight: Font.DemiBold }
    Label {
        Layout.fillWidth: true
        text: "Spotlight never shows or indexes these, even inside the folders above."
        color: Theme.fgDim
        wrapMode: Text.Wrap
    }
    SettingsGroup {
        Repeater {
            model: pane.cfg.excludePaths
            Column {
                id: xr
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                spacing: 0
                SettingsDivider { visible: xr.index > 0 }
                SettingsRow {
                    label: xr.modelData
                    PushButton {
                        text: "Remove"
                        onClicked: Settings.set("spotlight.excludePaths", pane.cfg.excludePaths.filter(f => f !== xr.modelData))
                    }
                }
            }
        }
        SettingsDivider { visible: pane.cfg.excludePaths.length > 0 }
        SettingsRow {
            label: "Leave out a folder"
            PushButton { text: "Add Folder…"; onClicked: excludeDialog.open() }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Leave out names"
            note: "Files or folders with these names anywhere, separated by spaces (wildcards like *.tmp work)."
            TextBox {
                implicitWidth: 320
                text: pane.cfg.excludeNames.join(" ")
                onAccepted: Settings.set("spotlight.excludeNames", text.split(/\s+/).filter(s => s))
                input.onEditingFinished: Settings.set("spotlight.excludeNames", text.split(/\s+/).filter(s => s))
            }
        }
    }

    FolderDialog {
        id: addDialog
        title: "Choose a folder for Spotlight to search"
        currentFolder: "file://" + pane.home
        onAccepted: {
            const p = pane.tilde(pane.localPath(selectedFolder));
            if (pane.cfg.folders.indexOf(p) < 0) Settings.set("spotlight.folders", pane.cfg.folders.concat([p]));
        }
    }
    FolderDialog {
        id: excludeDialog
        title: "Choose a folder Spotlight should leave out"
        currentFolder: "file://" + pane.home
        onAccepted: {
            const p = pane.tilde(pane.localPath(selectedFolder));
            if (pane.cfg.excludePaths.indexOf(p) < 0) Settings.set("spotlight.excludePaths", pane.cfg.excludePaths.concat([p]));
        }
    }
}
