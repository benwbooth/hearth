import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Widgets
import "../../widgets"
import "../.."

// Webcam capture for Settings > Users & Accounts: a round mirrored preview,
// a 3-second countdown, then `captured(path)` with the photo (the pane
// opens it in the crop editor). Loaded on demand so a missing Qt
// Multimedia only disables this, not the pane.
ColumnLayout {
    id: root
    signal captured(string path)
    signal cancelled()
    spacing: 12

    readonly property bool hasCamera: devices.videoInputs.length > 0
    property int countdown: 0
    property string error: ""

    MediaDevices { id: devices }

    CaptureSession {
        camera: Camera {
            id: camera
            // HEARTH_USER_TEST_NOCAM: test runs show the UI without the real webcam.
            active: root.hasCamera && Quickshell.env("HEARTH_USER_TEST_NOCAM") === ""
            cameraDevice: devices.defaultVideoInput
            onErrorOccurred: (err, msg) => root.error = "The camera didn't start: " + (msg || "it may be in use by another app") + "."
        }
        imageCapture: ImageCapture {
            id: shot
            onImageSaved: (id, path) => root.captured(path)
            onErrorOccurred: (id, err, msg) => root.error = "Couldn't take the photo: " + msg
        }
        videoOutput: preview
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        text: root.error !== "" ? root.error
            : !root.hasCamera ? "No camera found. Plug one in, or choose a photo instead."
            : "Look at the camera and click Take Photo."
        color: root.error !== "" ? Theme.bad : Theme.fgDim
    }

    ClippingRectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 280
        Layout.preferredHeight: 280
        radius: 140
        color: "black"
        visible: root.hasCamera
        VideoOutput {
            id: preview
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            // A mirror, like Photo Booth.
            transform: Scale { origin.x: 140; xScale: -1 }
        }
        Label {
            anchors.centerIn: parent
            visible: root.countdown > 0
            text: root.countdown
            color: "white"
            font.pointSize: 48
            font.weight: Font.Bold
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.4)
        }
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) {
                stop();
                shot.captureToFile(Quickshell.cachePath("avatars/camera-" + Date.now() + ".jpg"));
            }
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 10
        PushButton { text: "Cancel"; onClicked: root.cancelled() }
        PushButton {
            text: "Take Photo"
            primary: true
            visible: root.hasCamera
            enabled: shot.readyForCapture && root.countdown === 0
            tooltip: "Takes the photo after a 3-second countdown."
            onClicked: { root.countdown = 3; tick.start(); }
        }
    }
}
