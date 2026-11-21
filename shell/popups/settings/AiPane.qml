import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import "../../widgets"
import "../../services"
import "../.."

// Settings > AI (services/Ai.qml, helpers/hearth-ai): one place for every
// model on this computer. GPU memory and who uses it, the models each AI
// server has installed and loaded (load, unload, download, delete), which
// model the assistant uses, and whether cloud AI (Claude Code, Codex,
// Gemini CLI) may be used at all.
ColumnLayout {
    id: pane
    spacing: 14

    readonly property var cfg: Ai.cfg
    Component.onCompleted: Ai.watch(true)
    Component.onDestruction: Ai.watch(false)
    function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")); }
    property string confirmDelete: ""   // "provider/model" asking for confirmation
    property string confirmStop: ""

    Label {
        Layout.fillWidth: true
        text: "Everything that uses AI on this desktop (the voice assistant, Spotlight's Ask) goes through the models here. Local models run on your graphics card and nothing leaves the computer."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    // --- GPU memory ---
    Label { text: "Graphics memory"; font.weight: Font.DemiBold }
    SettingsGroup {
        Repeater {
            model: Ai.gpus
            Item {
                required property var modelData
                width: parent ? parent.width : 0
                height: vb.implicitHeight + 20
                VramBar { id: vb; y: 10; width: parent.width; gpu: parent.modelData }
            }
        }
        SettingsDivider {}
        Column {
            width: parent ? parent.width : 0
            topPadding: 10
            bottomPadding: 10
            spacing: 4
            Label { text: "Using the most graphics memory"; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize }
            Repeater {
                model: Ai.processes.slice(0, 8)
                Item {
                    required property var modelData
                    width: parent ? parent.width : 0
                    height: pn.implicitHeight
                    Label { id: pn; text: parent.modelData.name; width: parent.width - pv.implicitWidth - 10 }
                    Label { id: pv; anchors.right: parent.right; text: parent.modelData.vramText; color: Theme.fgSecondary; font.pointSize: Theme.smallFontSize }
                }
            }
            Label {
                visible: Ai.processes.length === 0
                text: "Reading…"
                color: Theme.fgSecondary
                font.pointSize: Theme.smallFontSize
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Unload all models"
            note: "Free the memory every hearth-managed model is using now. They load again when needed."
            PushButton { text: "Unload All"; onClicked: Ai.unloadAll() }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Keep models loaded for"
            note: "How long an unused model stays in memory. Loading again takes a few seconds."
            Dropdown {
                implicitWidth: 160
                options: [1, 5, 10, 30, 60, 240].map(n => ({ value: n, label: n < 60 ? n + " minutes" : (n / 60) + (n === 60 ? " hour" : " hours") }))
                value: Number(pane.cfg.keepAlive) || 10
                onPicked: v => Settings.set("ai.keepAlive", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Unload when something is full screen"
            note: "Free graphics memory for games and videos."
            tip: "When any window goes full screen, hearth unloads the models it manages (Ollama, llama.cpp). Models other apps loaded through Ollama are unloaded too."
            Toggle { checked: !!pane.cfg.unloadOnFullscreen; onToggled: c => Settings.set("ai.unloadOnFullscreen", c) }
        }
    }

    // --- assistant ---
    Label { text: "Assistant"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "AI"
            note: "Which server or app answers the voice assistant and Spotlight's Ask."
            Dropdown {
                implicitWidth: 220
                options: Ai.providers.filter(p => p.kind === "local" || pane.cfg.allowCloud).map(p => ({ value: p.id, label: p.label + (p.kind === "cloud" ? " (cloud)" : "") }))
                value: pane.cfg.assistant.provider
                onPicked: v => {
                    const p = Ai.provider(v);
                    const first = p && p.installed.length ? p.installed[0].name : "";
                    Settings.set("ai.assistant", { provider: v, model: first });
                }
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Model"
            note: "Pick one that can use tools (Qwen 3.5 4B is quick; 9B understands more)."
            readonly property var prov: Ai.provider(pane.cfg.assistant.provider)
            Dropdown {
                implicitWidth: 220
                options: (parent.prov ? parent.prov.installed : []).map(m => ({ value: m.name, label: m.name + (m.params ? " · " + m.params : "") + ((m.capabilities || []).indexOf("tools") >= 0 ? "" : (parent.prov && parent.prov.id === "ollama" ? " (no tools)" : "")) }))
                value: pane.cfg.assistant.model
                placeholder: "No models installed"
                onPicked: v => Settings.set("ai.assistant.model", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Try it"
            note: "Ask something to check the model answers."
            PushButton {
                text: "Ask “What time is it?”"
                onClicked: Voice.ask("What time is it?")
            }
        }
    }

    // --- servers and models ---
    Repeater {
        model: Ai.providers.filter(p => p.kind === "local")
        ColumnLayout {
            id: prov
            required property var modelData
            Layout.fillWidth: true
            spacing: 8
            readonly property var p: modelData

            RowLayout {
                Layout.fillWidth: true
                Label { text: prov.p.label; font.weight: Font.DemiBold }
                Label {
                    Layout.fillWidth: true
                    text: prov.p.running ? "running" + (prov.p.url ? " at " + prov.p.url.replace(/^https?:\/\//, "") : "") : (prov.p.error || "not running")
                    color: prov.p.running ? Theme.good : Theme.fgSecondary
                    font.pointSize: Theme.smallFontSize
                }
            }
            SettingsGroup {
                // llama.cpp: hearth's server and its models folder.
                SettingsRow {
                    visible: prov.p.id === "llamacpp"
                    label: "llama.cpp server"
                    note: "Serves every .gguf in " + (prov.p.modelsDir || "the models folder") + ", loading each on first use."
                    tip: "hearth-llama-server.service runs llama-server in router mode. Put GGUF files (from Hugging Face) in the folder; they appear here."
                    RowLayout {
                        PushButton { text: "Folder…"; tooltip: "Choose the folder with your .gguf models"; onClicked: dirDialog.open() }
                        PushButton {
                            text: prov.p.running ? "Stop" : "Start"
                            tooltip: prov.p.running ? "Stop the server (frees all its memory)" : "Start the server"
                            onClicked: Ai.server("llamacpp", !prov.p.running)
                        }
                    }
                }
                SettingsRow {
                    visible: !!prov.p.external
                    label: "Started outside hearth"
                    note: "A llama-server you started yourself (process " + prov.p.pid + "). hearth can use it and stop it."
                    PushButton {
                        text: pane.confirmStop === prov.p.id ? "Really stop?" : "Stop"
                        destructive: true
                        tooltip: "Ends that process; its model's memory is freed"
                        onClicked: {
                            if (pane.confirmStop === prov.p.id) { Ai.unload(prov.p.id, prov.p.installed[0].name); pane.confirmStop = ""; }
                            else pane.confirmStop = prov.p.id;
                        }
                    }
                }
                SettingsDivider { visible: prov.p.id === "llamacpp" || !!prov.p.external }
                Repeater {
                    model: prov.p.installed
                    Column {
                        id: mr
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 0
                        spacing: 0
                        readonly property bool isLoaded: Ai.isLoaded(prov.p.id, modelData.name)
                        readonly property string key: prov.p.id + "/" + modelData.name
                        SettingsDivider { visible: mr.index > 0 }
                        SettingsRow {
                            label: mr.modelData.name
                            note: [mr.modelData.params, mr.modelData.quant, mr.modelData.sizeText,
                                   (mr.modelData.capabilities || []).filter(c => c !== "completion").join(", "),
                                   mr.isLoaded ? "loaded" + (Ai.loaded.find(m => m.provider === prov.p.id && m.name === mr.modelData.name).vramText ? " (" + Ai.loaded.find(m => m.provider === prov.p.id && m.name === mr.modelData.name).vramText + " of graphics memory)" : "") : ""]
                                  .filter(s => s).join(" · ")
                            RowLayout {
                                spacing: 6
                                PushButton {
                                    visible: !prov.p.external
                                    text: Ai.busy === mr.key ? "Loading…" : mr.isLoaded ? "Unload" : "Load"
                                    enabled: Ai.busy !== mr.key && prov.p.running
                                    primary: !mr.isLoaded
                                    tooltip: mr.isLoaded ? "Free its memory now" : "Load it into memory now so the first answer is quick"
                                    onClicked: mr.isLoaded ? Ai.unload(prov.p.id, mr.modelData.name) : Ai.load(prov.p.id, mr.modelData.name)
                                }
                                PushButton {
                                    visible: prov.p.id === "ollama"
                                    text: pane.confirmDelete === mr.key ? "Really delete?" : "Delete"
                                    destructive: true
                                    tooltip: "Remove the model from disk (" + mr.modelData.sizeText + "). Asks first."
                                    onClicked: {
                                        if (pane.confirmDelete === mr.key) { Ai.remove(prov.p.id, mr.modelData.name); pane.confirmDelete = ""; }
                                        else pane.confirmDelete = mr.key;
                                    }
                                }
                            }
                        }
                    }
                }
                Label {
                    visible: prov.p.installed.length === 0
                    height: 36
                    text: prov.p.id === "ollama" ? "No models yet: download one below." : "No models in this folder yet."
                    color: Theme.fgSecondary
                }
                // Ollama: download by name.
                SettingsDivider { visible: prov.p.id === "ollama" }
                SettingsRow {
                    visible: prov.p.id === "ollama"
                    label: "Download a model"
                    note: "A name from ollama.com/library, e.g. qwen3.5:4b, qwen3.5:9b, gemma3:4b, llama3.2:3b."
                    RowLayout {
                        TextBox { id: pullName; implicitWidth: 180; placeholder: "qwen3.5:4b"; onAccepted: if (text.trim()) Ai.pull("ollama", text.trim()) }
                        PushButton { text: "Download"; enabled: pullName.text.trim() !== "" && prov.p.running; onClicked: Ai.pull("ollama", pullName.text.trim()) }
                    }
                }
                Repeater {
                    model: prov.p.id === "ollama" ? Object.keys(Ai.pulls).filter(k => k.startsWith("ollama/")) : []
                    Label {
                        required property var modelData
                        height: 30
                        readonly property var pr: Ai.pulls[modelData]
                        text: "Downloading " + modelData.slice(7) + ": " + (pr.total ? Math.round(100 * pr.completed / pr.total) + "%" : pr.status)
                        color: Theme.fgSecondary
                    }
                }
            }
        }
    }
    Label {
        visible: Ai.lastError !== ""
        Layout.fillWidth: true
        text: Ai.lastError
        color: Theme.warn
        wrapMode: Text.Wrap
    }

    // --- cloud ---
    Label { text: "Cloud AI"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "Allow cloud AI"
            note: "Let the assistant use coding-agent apps that send what you say to their company's servers."
            tip: "Off by default. With this on you can pick Claude Code, Codex or Gemini CLI as the assistant's AI above. They use your own accounts and their own usage limits."
            Toggle { checked: !!pane.cfg.allowCloud; onToggled: c => Settings.set("ai.allowCloud", c) }
        }
        Repeater {
            model: [{ id: "claude", label: "Claude Code", bin: "claude" }, { id: "codex", label: "Codex", bin: "codex" }, { id: "gemini", label: "Gemini CLI", bin: "gemini" }]
            Column {
                id: cr
                required property var modelData
                width: parent ? parent.width : 0
                spacing: 0
                readonly property bool installedCli: Ai.clis.some(x => x.id === modelData.id && x.installed)
                SettingsDivider {}
                SettingsRow {
                    enabled: !!pane.cfg.allowCloud
                    label: cr.modelData.label
                    note: cr.installedCli ? "Installed (" + cr.modelData.bin + ")." : "Not installed: the " + cr.modelData.bin + " command isn't on this computer."
                    Toggle {
                        enabled: cr.installedCli
                        checked: !!(pane.cfg.providers[cr.modelData.id] || {}).enabled
                        onToggled: c => Settings.set("ai.providers." + cr.modelData.id + ".enabled", c)
                    }
                }
            }
        }
    }

    FolderDialog {
        id: dirDialog
        title: "Choose the folder with your .gguf models"
        onAccepted: Settings.set("ai.providers.llamacpp.modelsDir", pane.localPath(selectedFolder))
    }
}
