import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Settings > Sound. The output device and its volume are in the menu bar's
// volume item and Control Center; this pane holds how sound behaves.
ColumnLayout {
    id: pane
    spacing: 14

    Label {
        Layout.fillWidth: true
        text: "Choose your speakers and set their volume from the volume icon in the menu bar, or from Control Center."
        color: Theme.fgDim
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    SettingsGroup {
        SettingsRow {
            label: "Play feedback when volume is changed"
            note: "A short pop each time the volume goes up or down (volume keys, scrolling on the volume icon, the sliders), so you hear the new level, like macOS."
            Toggle {
                checked: Settings.sound.volumeFeedback !== false
                onToggled: c => Settings.set("sound.volumeFeedback", c)
            }
        }
    }
}
