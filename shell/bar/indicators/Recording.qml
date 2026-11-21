import QtQuick
import "../../widgets"
import "../../services"
import "../.."

// Shown while a screen recording runs (Screenshot overlay > Record): a red
// dot and the time; click it to stop and save the video.
Indicator {
    id: root
    shown: Screenshots.recording
    icon: "media-playback-stop"
    text: Screenshots.formatDuration(Screenshots.recordSeconds)
    textColor: Theme.bad
    monochrome: false
    tooltip: "Stop recording"
    tooltipSub: (Screenshots.recordWhat ? Screenshots.recordWhat + " · " : "") + "saved to " + Screenshots.opt("recordFolder")
    onClicked: mouse => { if (mouse.button === Qt.LeftButton) Screenshots.stopRecording(); }
}
