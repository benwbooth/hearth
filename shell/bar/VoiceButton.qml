import QtQuick
import "../widgets"
import "../services"
import ".."

// The voice assistant's button in the menu bar (Siri's place on macOS):
// click and speak. Right-click opens Settings > Voice.
BarButton {
    icon: "audio-input-microphone-symbolic"
    iconFallback: "audio-input-microphone"
    tooltip: Voice.phase === "listening" ? "Listening… (click to stop)" : "Ask hearth by voice"
    tooltipSub: Voice.shortcutText + " · right-click for settings"
    active: Voice.visible
    visible: Voice.cfg.enabled && Voice.cfg.menuBarButton !== false
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) Settings.openRequested("voice");
        else if (mouse.button === Qt.LeftButton) Voice.toggle();
    }
}
