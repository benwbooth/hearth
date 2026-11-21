import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../widgets"
import "../../services"
import "../.."

// Settings > Voice Assistant (services/Voice.qml, helpers/hearth-voice):
// how to start it, speech recognition (whisper-typer's Whisper server),
// spoken replies (Piper voices) and the look.
ColumnLayout {
    id: pane
    spacing: 14

    readonly property var cfg: Voice.cfg
    Component.onCompleted: Voice.refreshVoices()

    Label {
        Layout.fillWidth: true
        text: "Press " + Voice.shortcutText + " or click the sparkle in the menu bar and its microphone, then just say what you want: “open the PDF I edited yesterday about taxes”, “set the volume to 50”, “what's the weather?”, “open Kog”. It stops listening when you stop talking. Speech is recognised on this computer and nothing is recorded while it isn't listening."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    SettingsGroup {
        SettingsRow {
            label: "Voice assistant"
            note: "Off: the shortcut and the menu bar button do nothing."
            Toggle { checked: pane.cfg.enabled !== false; onToggled: c => Settings.set("voice.enabled", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Keyboard shortcut"
            note: Voice.shortcutText + " starts listening; press it again to stop early."
            tip: "There is no always-on wake word: the microphone is only used after you press the shortcut or the button."
            PushButton { text: "Change…"; tooltip: "Settings > Keyboard Shortcuts"; onClicked: Settings.openRequested("shortcuts") }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Show in the menu bar"
            note: "The sparkle next to Control Center: ask by voice or typing, and see or unload the AI models."
            Toggle { checked: pane.cfg.menuBarButton !== false; onToggled: c => Settings.set("voice.menuBarButton", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Glowing screen edge"
            note: "The colours around the screen while it listens."
            Toggle { checked: pane.cfg.edgeGlow !== false; onToggled: c => Settings.set("voice.edgeGlow", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Sounds"
            note: "A chime when it starts and stops listening."
            Toggle { checked: pane.cfg.sounds !== false; onToggled: c => Settings.set("voice.sounds", c) }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Assistant model"
            note: (Ai.cfg.assistant.model || "none") + " via " + ((Ai.provider(Ai.cfg.assistant.provider) || {}).label || Ai.cfg.assistant.provider)
            PushButton { text: "AI Settings…"; onClicked: Settings.openRequested("ai") }
        }
    }

    Label { text: "Speech recognition"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "Language"
            Dropdown {
                implicitWidth: 180
                options: [["en", "English"], ["de", "German"], ["fr", "French"], ["es", "Spanish"], ["it", "Italian"], ["pt", "Portuguese"],
                          ["nl", "Dutch"], ["ja", "Japanese"], ["zh", "Chinese"], ["ko", "Korean"]].map(x => ({ value: x[0], label: x[1] }))
                value: pane.cfg.language
                onPicked: v => Settings.set("voice.language", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Whisper model"
            note: "Bigger is more accurate but slower. The server loads it the first time."
            tip: "Speech goes to the Whisper server that whisper-typer runs (services.whisper-typer in NixOS). “small” is what your typer uses, so it's already loaded."
            Dropdown {
                implicitWidth: 180
                options: ["small", "medium", "distil-large-v3", "large-v3-turbo", "large-v3"].map(m => ({ value: m, label: m }))
                value: pane.cfg.whisperModel
                onPicked: v => Settings.set("voice.whisperModel", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Stop after a pause of"
            note: "How long you can pause before it decides you've finished."
            ValueSlider {
                implicitWidth: 240
                from: 500; to: 3000; step: 100; suffix: " ms"
                value: Number(pane.cfg.silenceMs) || 1000
                onMoved: v => Settings.set("voice.silenceMs", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Whisper server"
            note: "Where the speech recognition server listens."
            TextBox {
                implicitWidth: 240
                text: pane.cfg.whisperUrl
                onAccepted: Settings.set("voice.whisperUrl", text.trim())
                input.onEditingFinished: Settings.set("voice.whisperUrl", text.trim())
            }
        }
    }

    Label { text: "Spoken replies"; font.weight: Font.DemiBold }
    SettingsGroup {
        SettingsRow {
            label: "Speak replies"
            note: "Read answers aloud with Piper, a voice that runs on this computer."
            Toggle { checked: !!pane.cfg.speak; onToggled: c => Settings.set("voice.speak", c) }
        }
        SettingsDivider {}
        SettingsRow {
            id: voiceRow
            label: "Voice"
            readonly property bool have: Voice.voices.installed.indexOf(pane.cfg.piperVoice) >= 0
            note: have ? "Downloaded." : Voice.download && Voice.download.voice === pane.cfg.piperVoice
                ? "Downloading… " + (Voice.download.total ? Math.round(100 * Voice.download.done / Voice.download.total) + "%" : "")
                : "Not downloaded yet (about 60 MB from Hugging Face's rhasspy/piper-voices)."
            RowLayout {
                spacing: 6
                Dropdown {
                    implicitWidth: 240
                    options: {
                        const av = Voice.voices.available || [];
                        const extra = (Voice.voices.installed || []).filter(v => !av.some(a => a.id === v)).map(v => ({ id: v, label: v }));
                        return av.concat(extra).map(v => ({ value: v.id, label: v.label + ((Voice.voices.installed || []).indexOf(v.id) >= 0 ? " ✓" : "") }));
                    }
                    value: pane.cfg.piperVoice
                    onPicked: v => Settings.set("voice.piperVoice", v)
                }
                PushButton {
                    visible: !voiceRow.have
                    text: "Download"
                    enabled: !Voice.download
                    tooltip: "Download this voice once; it's kept in ~/.local/share/hearth/piper"
                    onClicked: Voice.downloadVoice(pane.cfg.piperVoice)
                }
                PushButton {
                    visible: voiceRow.have
                    text: "Preview"
                    onClicked: Voice.speak("Hi, I'm your desktop assistant. Ask me to open apps, find files or change settings.")
                }
            }
        }
    }
}
