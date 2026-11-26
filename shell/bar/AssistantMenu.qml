import QtQuick
import QtQuick.Layouts
import Quickshell
import "../widgets"
import "../services"
import ".."

// The assistant in the menu bar, where Siri sits on macOS (next to Control
// Center): one menu for asking by voice or by typing, the last answer, the
// assistant's model, and the AI models on this computer: graphics memory,
// what's loaded (Unload / Stop), Load, Unload All. Super+Alt+Space still
// starts listening straight away; right-click opens Settings > AI.
// Services: services/Voice.qml, services/Ai.qml. Spotlight (the magnifier)
// stays separate.
//
//   hearth-ipc call indicator-ai toggle
Indicator {
    id: root
    ipcName: "ai"
    icon: Quickshell.shellDir + "/assets/ai.svg"
    shown: Voice.cfg.menuBarButton !== false
    active: popup.open || Voice.visible
    tooltip: Voice.phase === "listening" ? "Listening…" : "Assistant and AI models"
    tooltipSub: Voice.shortcutText + " asks by voice"
        + (Ai.mainGpu ? `\nGPU ${Ai.mainGpu.busy}% busy · graphics memory ${Ai.mainGpu.percent}% (${Ai.mainGpu.usedText} of ${Ai.mainGpu.totalText})` : "")
        + (Ai.loaded.length ? "\n" + Ai.loaded.map(m => `${m.name} loaded` + (m.vramText ? ` (${m.vramText})` : "")).join("\n") : "")
    // GPU busy % and graphics memory % next to the icon (Settings > AI).
    text: Ai.cfg.menuBarStats !== false && Ai.mainGpu && Ai.mainGpu.busy !== null && Ai.mainGpu.busy !== undefined
          ? `${Ai.mainGpu.busy}% · ${Ai.mainGpu.percent}%` : ""
    onRightClicked: Settings.openRequested("ai")

    Connections {
        target: root.popup
        function onOpenChanged() { Ai.watch(root.popup.open); }
    }

    readonly property var assistantProvider: Ai.provider(Ai.cfg.assistant.provider)
    readonly property bool assistantLoaded: Ai.isLoaded(Ai.cfg.assistant.provider, Ai.cfg.assistant.model)

    function askTyped(text) {
        text = (text || "").trim();
        if (!text) return;
        root.popup.close();
        Voice.ask(text);
    }

    popupContent: ColumnLayout {
        spacing: 10
        width: 470

        // --- ask ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            MouseArea {
                id: orb
                implicitWidth: 40
                implicitHeight: 40
                hoverEnabled: true
                onClicked: { root.popup.close(); Voice.toggle(); }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: orb.containsMouse ? Theme.accent : Theme.accentDim
                }
                Icon {
                    anchors.centerIn: parent
                    implicitSize: 20
                    name: "audio-input-microphone-symbolic"
                    fallback: "audio-input-microphone"
                }
                Tooltip { anchorItem: orb; hovered: orb.containsMouse; text: "Ask by voice"; subtext: Voice.shortcutText }
            }
            TextBox {
                id: ask
                Layout.fillWidth: true
                placeholder: Voice.cfg.enabled ? "Ask anything, or click the microphone…" : "The assistant is off (Settings > Voice Assistant)"
                enabled: Voice.cfg.enabled
                onAccepted: { root.askTyped(text); text = ""; }
            }
        }
        // The last exchange.
        ColumnLayout {
            visible: Voice.heard !== "" || Voice.reply !== ""
            Layout.fillWidth: true
            spacing: 2
            Label {
                Layout.fillWidth: true
                text: Voice.heard ? "“" + Voice.heard + "”" : ""
                visible: text !== ""
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                maximumLineCount: 2
            }
            Label {
                Layout.fillWidth: true
                text: Voice.phase === "thinking" ? Voice.thinkingText : Voice.reply
                visible: text !== ""
                color: Voice.replyError ? Theme.warn : Theme.fg
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                maximumLineCount: 4
                textFormat: Text.PlainText
            }
        }

        MenuSeparator { Layout.fillWidth: true }

        // --- the assistant's model ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { text: "Model"; color: Theme.fgSecondary }
            Dropdown {
                Layout.fillWidth: true
                // Every installed model of every local server (and the cloud
                // CLIs when allowed), as "provider|model".
                options: {
                    const out = [];
                    for (const p of Ai.providers) {
                        if (p.kind === "cloud" && !Ai.cfg.allowCloud) continue;
                        for (const m of p.installed || [])
                            out.push({ value: p.id + "|" + m.name, label: m.name + " · " + p.label + (m.params ? " · " + m.params : "") });
                    }
                    return out;
                }
                value: Ai.cfg.assistant.provider + "|" + Ai.cfg.assistant.model
                placeholder: "No models installed"
                onPicked: v => {
                    const i = v.indexOf("|");
                    Settings.set("ai.assistant", { provider: v.slice(0, i), model: v.slice(i + 1) });
                }
            }
            PushButton {
                visible: !!root.assistantProvider && root.assistantProvider.kind === "local" && !root.assistantLoaded && !root.assistantProvider.external
                text: Ai.busy === Ai.cfg.assistant.provider + "/" + Ai.cfg.assistant.model ? "Loading…" : "Load"
                tooltip: "Load it into graphics memory now so the first answer is quick"
                onClicked: Ai.load(Ai.cfg.assistant.provider, Ai.cfg.assistant.model)
            }
        }

        // --- GPU, graphics memory, models ---
        GpuMeters {
            Layout.fillWidth: true
            gpu: Ai.mainGpu
            loaded: Ai.loaded
            apps: Ai.apps
        }
        AiModels { Layout.fillWidth: true }
        Label {
            visible: Ai.lastError !== ""
            text: Ai.lastError
            color: Theme.warn
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        RowLayout {
            Layout.fillWidth: true
            PushButton {
                text: "Unload All"
                visible: Ai.loaded.some(m => m.auto && !m.pinned)
                tooltip: "Unload every model the AI servers have loaded (Ollama, llama.cpp, Magnitude, model services), except kept ones"
                onClicked: Ai.unloadAll()
            }
            Item { Layout.fillWidth: true }
            PushButton {
                text: "Voice…"
                tooltip: "Shortcut, language, spoken replies (Settings > Voice Assistant)"
                onClicked: { root.popup.close(); Settings.openRequested("voice"); }
            }
            PushButton {
                text: "AI Settings…"
                tooltip: "Installed models, downloads, cloud AI, graphics memory per app"
                onClicked: { root.popup.close(); Settings.openRequested("ai"); }
            }
        }
    }
}
