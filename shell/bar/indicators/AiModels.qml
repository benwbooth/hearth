import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../widgets"
import "../../services"
import "../.."

// AI in the menu bar (services/Ai.qml): GPU memory at a glance, the models
// loaded right now with a button to unload each (or all), and the way to
// Settings > AI to load, download or switch models. The icon fills in
// while a model is loaded.
Indicator {
    id: root
    icon: Ai.loaded.length ? "preferences-system-network-sharing" : "preferences-system-network-sharing"
    tooltip: Ai.loaded.length ? Ai.loaded.length + (Ai.loaded.length === 1 ? " AI model loaded" : " AI models loaded") : "AI models"
    tooltipSub: (Ai.mainGpu ? `GPU memory: ${Ai.mainGpu.usedText} of ${Ai.mainGpu.totalText}\n` : "") + Ai.loaded.map(m => `${m.name} (${m.providerLabel})`).join("\n")

    Connections {
        target: root.popup
        function onOpenChanged() { Ai.watch(root.popup.open); }
    }

    popupContent: ColumnLayout {
        spacing: 10
        width: 380

        Label { text: "AI"; font.weight: Font.DemiBold }

        Repeater {
            model: Ai.gpus.filter(g => !g.integrated)
            VramBar { required property var modelData; gpu: modelData; Layout.fillWidth: true }
        }

        Label {
            text: Ai.loaded.length ? "Loaded models" : "No models loaded: they load when something uses them."
            color: Theme.fgSecondary
            font.pointSize: Theme.smallFontSize
            Layout.fillWidth: true
            wrapMode: Text.Wrap
        }
        Repeater {
            model: Ai.loaded
            RowLayout {
                id: lm
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                Icon { implicitSize: 20; name: "preferences-system-network-sharing" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: lm.modelData.name; Layout.fillWidth: true }
                    Label {
                        text: lm.modelData.providerLabel + (lm.modelData.vramText ? " · " + lm.modelData.vramText + " VRAM" : "") + (lm.modelData.external ? " · started outside hearth" : "")
                        color: Theme.fgSecondary
                        font.pointSize: Theme.smallFontSize
                        Layout.fillWidth: true
                    }
                }
                PushButton {
                    text: lm.modelData.external ? "Stop" : "Unload"
                    tooltip: lm.modelData.external ? "Stops that llama-server process (pid " + lm.modelData.pid + ") to free its memory" : "Frees its memory now; it loads again next time it's used"
                    onClicked: Ai.unload(lm.modelData.provider, lm.modelData.name)
                }
            }
        }
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
                visible: Ai.loaded.some(m => !m.external)
                tooltip: "Unload every model hearth's AI servers have loaded (Ollama, llama.cpp)"
                onClicked: Ai.unloadAll()
            }
            Item { Layout.fillWidth: true }
            PushButton {
                text: "AI Settings…"
                tooltip: "Installed models, which AI each feature uses, downloads, VRAM per app"
                onClicked: { root.popup.close(); Settings.openRequested("ai"); }
            }
        }
    }
}
