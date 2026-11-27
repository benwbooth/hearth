import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import "../../widgets"
import "../../services"
import "../.."
import "../../bar"

// Settings > AI (services/Ai.qml, helpers/hearth-ai): GPU memory and who
// uses it, when models unload, which model the assistant uses, every model
// on this computer in one list (bar/AiModels, the AI menu's browser), the
// servers that run them, extra model folders, and whether cloud AI may be
// used. Everything listed comes from what hearth-ai finds; no model,
// server or app is named here.
ColumnLayout {
    id: pane
    spacing: 14

    readonly property var cfg: Ai.cfg
    Component.onCompleted: Ai.watch(true)
    Component.onDestruction: Ai.watch(false)
    function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")); }
    property string confirmStop: ""

    Label {
        Layout.fillWidth: true
        text: "Everything that uses AI on this desktop (the voice assistant, Search's Ask) goes through the models here. Local models run on your graphics card and nothing leaves the computer."
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
            label: "Unload when something is full screen"
            note: "Free graphics memory for games and videos."
            tip: "When any window goes full screen, hearth unloads every model it can (models pinned in the list below stay)."
            Toggle { checked: !!pane.cfg.unloadOnFullscreen; onToggled: c => Settings.set("ai.unloadOnFullscreen", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Unload unused models"
            note: "Free graphics memory as soon as a model sits unused."
            tip: "Every model server's models count, whatever runs them: hearth watches when each one last used the GPU. A model that takes long to load waits longer (ten times its load time, up to an hour). Pin a model in the list below to keep it loaded."
            Toggle { checked: pane.cfg.autoUnload !== false; onToggled: c => Settings.set("ai.autoUnload", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Unused for"
            note: "The shortest a model stays loaded after its last use."
            enabled: pane.cfg.autoUnload !== false
            Dropdown {
                implicitWidth: 160
                options: [1, 2, 5, 10, 15, 30].map(n => ({ value: n, label: n + (n === 1 ? " minute" : " minutes") }))
                value: Number(pane.cfg.idleMinutes) || 5
                onPicked: v => Settings.set("ai.idleMinutes", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Make room for new requests"
            note: "When graphics memory runs out, unload the models idle longest."
            tip: "When the card is nearly full, a model spills into system RAM, or a model is about to load without room, hearth unloads idle models first: the ones unused longest and quickest to load again go first. A model using the GPU right now is never unloaded."
            Toggle { checked: pane.cfg.evictOnPressure !== false; onToggled: c => Settings.set("ai.evictOnPressure", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Context window"
            note: "How much text a model hearth starts can keep in mind. Automatic uses as much as fits in graphics memory."
            tip: "For models hearth runs itself (its llama.cpp server, and model files that run in their own server). Automatic starts from the model's own maximum and shrinks it until the model fits in the free graphics memory, keeping a margin; a loaded model shows what it got. Bigger windows use more memory and read long prompts slower. A model can have its own size in the list below. Takes effect the next time a model loads."
            Dropdown {
                implicitWidth: 160
                options: Ai.contextOptions.map(n => ({ value: n, label: Ai.contextLabel(n) + (n ? " tokens" : "") }))
                value: Number(pane.cfg.contextSize) || 0
                onPicked: v => Settings.set("ai.contextSize", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Show GPU use in the menu bar"
            note: "GPU busy % and graphics memory % next to the AI icon."
            Toggle { checked: pane.cfg.menuBarStats !== false; onToggled: c => Settings.set("ai.menuBarStats", c) }
        }
    }

    // --- assistant ---
    Label { text: "Assistant"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "AI"
            note: "Which server or app answers the voice assistant and Search's Ask."
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
            note: "Pick one that can use tools: smaller models answer sooner, larger ones understand more."
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
            label: "Quick model"
            note: "A small model that answers simple requests in seconds while the assistant's model isn't loaded, and hands harder ones to it."
            tip: "Quick commands (open an app, the volume, what's open) don't need a big model, and a small one loads in a couple of seconds. It passes anything that needs reasoning, writing or several steps to the assistant's model. Once that model is loaded, it answers everything itself."
            readonly property var fast: pane.cfg.fastAssistant || { enabled: true, provider: "ollama", model: "qwen3.5:4b" }
            Dropdown {
                implicitWidth: 220
                options: [{ value: "", label: "Off" }].concat(Ai.providers.filter(p => p.kind === "local").flatMap(p =>
                    (p.installed || []).filter(m => !m.category || m.category === "llm").map(m => ({ value: p.id + "|" + m.name, label: m.name + " · " + p.label }))))
                value: parent.fast.enabled === false ? "" : (parent.fast.provider + "|" + parent.fast.model)
                onPicked: v => {
                    if (!v) { Settings.set("ai.fastAssistant", Object.assign({}, parent.fast, { enabled: false })); return; }
                    const i = v.indexOf("|");
                    Settings.set("ai.fastAssistant", { enabled: true, provider: v.slice(0, i), model: v.slice(i + 1) });
                }
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Use the computer"
            note: "Let the assistant read your windows and click and type in apps to do what you ask."
            tip: "It uses the same computer-use tools as Codex (codex-computer-use-linux). Ask: a card asks you once per request before it clicks or types (reading windows needs no OK). Always: it acts without asking. Off: it can't see or touch your apps."
            Dropdown {
                implicitWidth: 160
                options: [{ value: "ask", label: "Ask first" }, { value: "allow", label: "Always" }, { value: "off", label: "Off" }]
                value: pane.cfg.computerUse || "ask"
                onPicked: v => Settings.set("ai.computerUse", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Run commands"
            note: "Let the assistant run terminal commands to answer questions and get things done."
            tip: "Ask: a card shows each command with Allow and Deny before it runs. Always: commands run without asking (they can change or delete anything you can). Off: no commands."
            Dropdown {
                implicitWidth: 160
                options: [{ value: "ask", label: "Ask each time" }, { value: "allow", label: "Always" }, { value: "off", label: "Off" }]
                value: pane.cfg.runCommands || "ask"
                onPicked: v => Settings.set("ai.runCommands", v)
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

    // --- models ---
    // Every model on this computer, whatever installed it, in one list (the
    // AI menu's own browser): what's loaded, what's installed, and what can
    // be downloaded, by category. Nothing here names a model, so new ones
    // (a new Ollama tag, a GGUF in a model folder, a new model unit, a
    // Magnitude download) simply show up.
    Label { text: "Models"; font.weight: Font.DemiBold }
    SettingsGroup {
        Item {
            width: parent ? parent.width : 0
            height: models.implicitHeight + 24
            AiModels {
                id: models
                x: 12
                y: 12
                width: parent.width - 24
                listHeight: 460
            }
        }
    }

    // --- servers ---
    // The programs that run several models (Ollama, hearth's llama.cpp,
    // Magnitude, a llama-server started by hand), each from what hearth-ai
    // finds. One-model units (Inkling and the like) start from their model
    // in the list above.
    Label { text: "Model servers"; font.weight: Font.DemiBold }
    SettingsGroup {
        Repeater {
            model: Ai.providers.filter(p => p.kind === "local" && !p.service)
            Column {
                id: sr
                required property var modelData
                required property int index
                readonly property var p: modelData
                width: parent ? parent.width : 0
                spacing: 0
                SettingsDivider { visible: sr.index > 0 }
                SettingsRow {
                    label: sr.p.label
                    note: {
                        const p = sr.p;
                        const parts = [p.running ? "Running" + (p.url ? " at " + p.url.replace(/^https?:\/\//, "") : "")
                                                 : (p.available === false ? "Not installed" : p.error || "Not running")];
                        if (p.installed && p.installed.length) parts.push(p.installed.length + (p.installed.length === 1 ? " model" : " models"));
                        if (p.external) parts.push("started outside hearth (process " + p.pid + ")");
                        if (p.modelsDir) parts.push("serves " + p.modelsDir);
                        return parts.join(" · ");
                    }
                    tip: sr.p.controlUnit ? "Runs as " + sr.p.controlUnit + ". Stopping it frees every model it has loaded."
                         : sr.p.external ? "hearth can use it and stop it."
                         : "Runs as a system service: start or stop it outside hearth."
                    RowLayout {
                        spacing: 6
                        PushButton {
                            visible: sr.p.modelsDir !== undefined
                            text: "Folder…"
                            tooltip: "Choose the folder this server loads its models from"
                            onClicked: { dirDialog.target = "ai.providers." + sr.p.id + ".modelsDir"; dirDialog.open(); }
                        }
                        PushButton {
                            visible: !!sr.p.controlUnit
                            text: sr.p.running ? "Stop" : "Start"
                            tooltip: sr.p.running ? "Stop it (frees all its memory)" : "Start it (idle models are unloaded first if there isn't room)"
                            onClicked: Ai.server(sr.p.id, !sr.p.running)
                        }
                        PushButton {
                            visible: !!sr.p.external
                            text: pane.confirmStop === sr.p.id ? "Really stop?" : "Stop"
                            destructive: true
                            tooltip: "Ends that process; its model's memory is freed"
                            onClicked: {
                                if (pane.confirmStop === sr.p.id) { Ai.unload(sr.p.id, sr.p.installed[0].name); pane.confirmStop = ""; }
                                else pane.confirmStop = sr.p.id;
                            }
                        }
                    }
                }
            }
        }
    }

    // --- folders ---
    Label { text: "Model folders"; font.weight: Font.DemiBold }
    SettingsGroup {
        Repeater {
            model: pane.cfg.modelDirs || []
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
                        tooltip: "Stop looking in this folder (its files stay)"
                        onClicked: Settings.set("ai.modelDirs", (pane.cfg.modelDirs || []).filter(d => d !== fr.modelData))
                    }
                }
            }
        }
        SettingsDivider { visible: (pane.cfg.modelDirs || []).length > 0 }
        SettingsRow {
            label: "Add a folder"
            note: "Model files you downloaded yourself. hearth also looks in the usual places (Hugging Face's cache, Ollama, Magnitude, ComfyUI and every model server's own folder)."
            PushButton {
                text: "Add…"
                onClicked: { dirDialog.target = "ai.modelDirs"; dirDialog.open(); }
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

    // --- apps (hearth-ai's OpenAI-compatible server, README "AI" > Apps) ---
    // A provider + model picker for ai.apps / ai.appsFast; empty = the fallback.
    component AppModelRows: Column {
        id: amr
        property string key
        property string label
        property string note
        property string fallback
        readonly property var f: pane.cfg[key] || ({})
        readonly property var prov: f.provider ? Ai.provider(f.provider) : null
        width: parent ? parent.width : 0
        spacing: 0
        SettingsRow {
            label: amr.label
            note: amr.note
            Dropdown {
                implicitWidth: 220
                options: [{ value: "", label: amr.fallback }].concat(Ai.providers.filter(p => p.kind === "local" || pane.cfg.allowCloud).map(p => ({ value: p.id, label: p.label + (p.kind === "cloud" ? " (cloud)" : "") })))
                value: amr.f.provider || ""
                onPicked: v => {
                    const p = v ? Ai.provider(v) : null;
                    Settings.set("ai." + amr.key, { provider: v, model: p && p.installed.length ? p.installed[0].name : "" });
                }
            }
        }
        SettingsDivider { visible: !!amr.f.provider }
        SettingsRow {
            visible: !!amr.f.provider
            label: "Model"
            Dropdown {
                implicitWidth: 220
                options: (amr.prov ? amr.prov.installed : []).map(m => ({ value: m.name, label: m.name + (m.params ? " · " + m.params : "") }))
                value: amr.f.model || ""
                placeholder: "No models installed"
                onPicked: v => Settings.set("ai." + amr.key + ".model", v)
            }
        }
    }
    Label { text: "Apps"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "Let apps use these models"
            note: "Apps such as Tessera ask hearth instead of running their own: one set of models, unloaded when idle."
            tip: "An OpenAI-compatible server on 127.0.0.1 port 18380 (ai.api.port). Only your apps can use it: they read its address and key from $XDG_RUNTIME_DIR/hearth/ai-api.json, readable only by you. Apps ask for \"default\" or \"fast\" (below), or a model by name. Cloud AI answers only while Allow cloud AI is on."
            Toggle { checked: (pane.cfg.api || {}).enabled !== false; onToggled: c => Settings.set("ai.api.enabled", c) }
        }
        SettingsDivider {}
        AppModelRows {
            key: "apps"
            label: "Default"
            note: "For apps' assistants and requests (Tessera's sidebar, # commands, fixes)."
            fallback: "Same as the assistant"
        }
        SettingsDivider {}
        AppModelRows {
            key: "appsFast"
            label: "Fast"
            note: "For answers as you type (Tessera's suggestions and checks): pick a small model that doesn't think out loud."
            fallback: "Same as Default"
        }
    }

    // --- cloud ---
    // The coding-agent apps hearth-ai knows how to drive (Ai.clis).
    Label { text: "Cloud AI"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "Allow cloud AI"
            note: "Let the assistant use coding-agent apps that send what you say to their company's servers."
            tip: "Off by default. With this on you can pick one of the apps below as the assistant's AI. They use your own accounts and their own usage limits."
            Toggle { checked: !!pane.cfg.allowCloud; onToggled: c => Settings.set("ai.allowCloud", c) }
        }
        Repeater {
            model: Ai.clis
            Column {
                id: cr
                required property var modelData
                width: parent ? parent.width : 0
                spacing: 0
                SettingsDivider {}
                SettingsRow {
                    enabled: !!pane.cfg.allowCloud
                    label: cr.modelData.label
                    note: cr.modelData.installed ? "Installed." : "Not installed on this computer."
                    Toggle {
                        enabled: cr.modelData.installed
                        checked: !!(pane.cfg.providers[cr.modelData.id] || {}).enabled
                        onToggled: c => Settings.set("ai.providers." + cr.modelData.id + ".enabled", c)
                    }
                }
            }
        }
    }

    FolderDialog {
        id: dirDialog
        property string target: "ai.modelDirs"   // the setting the chosen folder goes to
        title: "Choose a folder with AI models"
        onAccepted: {
            const dir = pane.localPath(selectedFolder);
            if (target === "ai.modelDirs") {
                const dirs = pane.cfg.modelDirs || [];
                if (dirs.indexOf(dir) < 0) Settings.set("ai.modelDirs", dirs.concat([dir]));
            } else Settings.set(target, dir);
        }
    }
}
