import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../widgets"
import "../services"
import ".."

// Now playing on the lock screen, like macOS: a glass card with the
// artwork, title and artist, previous / play-pause / next and the progress.
LockGlass {
    id: root
    property real k: 1
    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.isPlaying) ?? players.find(p => p.trackTitle) ?? null
    width: Math.round(380 * k)
    height: Math.round(96 * k)
    radius: Math.round(22 * k)
    tint: Qt.rgba(1, 1, 1, 0.12)

    function fmt(secs) {
        if (!isFinite(secs) || secs < 0) secs = 0;
        const s = Math.floor(secs % 60), m = Math.floor(secs / 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.player !== null && root.player.isPlaying && root.player.positionSupported
        onTriggered: root.player.positionChanged()
    }

    ClippingRectangle {
        id: art
        x: Math.round(14 * root.k)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(66 * root.k)
        height: width
        radius: Math.round(10 * root.k)
        color: Qt.rgba(1, 1, 1, 0.15)
        Image {
            anchors.fill: parent
            source: root.player ? root.player.trackArtUrl || "" : ""
            sourceSize: Qt.size(parent.width * 2, parent.height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
        Icon {
            anchors.centerIn: parent
            visible: !(root.player && root.player.trackArtUrl)
            name: "media-optical-audio"
            implicitSize: Math.round(30 * root.k)
        }
    }
    Column {
        anchors.left: art.right
        anchors.leftMargin: 12 * root.k
        anchors.right: controls.left
        anchors.rightMargin: 8 * root.k
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2 * root.k
        Label {
            width: parent.width
            text: root.player ? root.player.trackTitle || root.player.identity : ""
            color: "white"
            font.pointSize: 0.75 * Math.round(14 * root.k)
            font.weight: Font.DemiBold
        }
        Label {
            width: parent.width
            text: root.player ? root.player.trackArtist || root.player.identity : ""
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pointSize: 0.75 * Math.round(13 * root.k)
        }
        Item {
            width: parent.width
            height: 18 * root.k
            visible: root.player !== null && root.player.lengthSupported && root.player.length > 0
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Math.max(3, 4 * root.k)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.22)
                Rectangle {
                    height: parent.height
                    radius: height / 2
                    width: root.player && root.player.length > 0
                           ? parent.width * Math.max(0, Math.min(1, root.player.position / root.player.length)) : 0
                    color: Qt.rgba(1, 1, 1, 0.85)
                }
            }
        }
    }
    Row {
        id: controls
        anchors.right: parent.right
        anchors.rightMargin: 10 * root.k
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        LockButton {
            k: root.k; flat: true
            icon: "media-skip-backward-symbolic"
            tip: "Previous"
            opacity: root.player && root.player.canGoPrevious ? 1 : 0.4
            onClicked: { Lock.activity(); if (root.player && root.player.canGoPrevious) root.player.previous(); }
        }
        LockButton {
            k: root.k; flat: true
            icon: root.player && root.player.isPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
            tip: root.player && root.player.isPlaying ? "Pause" : "Play"
            onClicked: { Lock.activity(); if (root.player && root.player.canTogglePlaying) root.player.togglePlaying(); }
        }
        LockButton {
            k: root.k; flat: true
            icon: "media-skip-forward-symbolic"
            tip: "Next"
            opacity: root.player && root.player.canGoNext ? 1 : 0.4
            onClicked: { Lock.activity(); if (root.player && root.player.canGoNext) root.player.next(); }
        }
    }
}
