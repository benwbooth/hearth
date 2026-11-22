import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../widgets"
import "../.."

// Media player (MPRIS) controls. Shown while any player exists. Middle click
// toggles play/pause, the wheel skips tracks (up = next, down = previous).
Indicator {
    id: root

    readonly property var players: Mpris.players.values
    // The player picked in the switcher, else the one playing, else the first.
    property var chosen: null
    readonly property var player: (chosen && players.indexOf(chosen) >= 0) ? chosen
                                  : (players.find(p => p.isPlaying) ?? players.find(p => p.trackTitle) ?? players[0] ?? null)
    readonly property bool playing: player?.isPlaying ?? false

    function fmt(secs) {
        if (!isFinite(secs) || secs < 0) secs = 0;
        const s = Math.floor(secs % 60), m = Math.floor(secs / 60) % 60, h = Math.floor(secs / 3600);
        const ss = (s < 10 ? "0" : "") + s;
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss;
    }
    function playerIcon(p) {
        if (!p) return "";
        const e = (p.desktopEntry && DesktopEntries.byId(p.desktopEntry))
                  || DesktopEntries.heuristicLookup(p.desktopEntry || p.identity);
        return e?.icon || p.desktopEntry || "";
    }

    shown: player !== null
    icon: playing ? "media-playback-start-symbolic" : "media-playback-pause-symbolic"
    iconFallback: playing ? "media-playback-start" : "media-playback-pause"
    tooltip: player ? (player.trackTitle || player.identity) : ""
    tooltipSub: player ? [player.trackArtist, player.trackAlbum].filter(s => s).join(" — ")
                         + (player.trackTitle ? "\n" + player.identity : "") : ""

    onMiddleClicked: if (player?.canTogglePlaying) player.togglePlaying()
    onScrolled: delta => {
        if (!player) return;
        if (delta > 0 && player.canGoNext) player.next();
        else if (delta < 0 && player.canGoPrevious) player.previous();
    }

    popupContent: ColumnLayout {
        id: pop
        readonly property var p: root.player
        spacing: 10

        // MPRIS position isn't pushed; poll it while the popup is open.
        Timer {
            interval: 1000
            repeat: true
            running: pop.p !== null && pop.p.isPlaying && pop.p.positionSupported
            onTriggered: pop.p.positionChanged()
        }

        // Player switcher when several players exist.
        Flow {
            Layout.fillWidth: true
            Layout.preferredWidth: 400
            visible: root.players.length > 1
            spacing: 4
            Repeater {
                model: root.players
                delegate: BarButton {
                    required property var modelData
                    implicitHeight: 30
                    iconSize: 16
                    icon: root.playerIcon(modelData)
                    iconFallback: "multimedia-player"
                    text: modelData.identity
                    textColor: modelData === pop.p ? Theme.fg : Theme.fgDim
                    active: modelData === pop.p
                    tooltip: modelData.trackTitle
                    onClicked: root.chosen = modelData
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 400
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 112
                Layout.preferredHeight: 112
                radius: Theme.radius
                color: Theme.bgRaised
                clip: true
                Image {
                    id: art
                    anchors.fill: parent
                    source: pop.p?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 224
                    sourceSize.height: 224
                    visible: status === Image.Ready
                }
                Icon {
                    anchors.centerIn: parent
                    visible: !art.visible
                    implicitSize: 56
                    name: root.playerIcon(pop.p)
                    fallback: "media-default-album"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: pop.p?.trackTitle || pop.p?.identity || ""
                    font.weight: Font.DemiBold
                    font.pointSize: Theme.fontSize + 1
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: pop.p?.trackArtist ?? ""
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: pop.p?.trackAlbum ?? ""
                    color: Theme.fgDim
                }
                Label {
                    Layout.fillWidth: true
                    visible: root.players.length === 1
                    text: pop.p?.identity ?? ""
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
            }
        }

        // Seek bar.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 400
            visible: (pop.p?.lengthSupported ?? false) && (pop.p?.length ?? 0) > 0
            spacing: 0
            Item {
                id: seek
                Layout.fillWidth: true
                implicitHeight: 20
                readonly property real frac: pop.p && pop.p.length > 0
                                             ? Math.max(0, Math.min(1, pop.p.position / pop.p.length)) : 0
                readonly property bool canSeek: pop.p?.canSeek ?? false
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    x: 6
                    width: parent.width - 12
                    height: 4
                    radius: 2
                    color: Theme.border
                    Rectangle {
                        width: parent.width * seek.frac
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                    }
                }
                Rectangle {
                    visible: seek.canSeek
                    anchors.verticalCenter: parent.verticalCenter
                    x: track.x + track.width * seek.frac - width / 2
                    width: 12
                    height: 12
                    radius: 6
                    color: seekArea.pressed || seekArea.containsMouse ? Theme.fg : Theme.fgDim
                }
                MouseArea {
                    id: seekArea
                    anchors.fill: parent
                    enabled: seek.canSeek
                    hoverEnabled: true
                    preventStealing: true
                    function set(x) {
                        const f = Math.max(0, Math.min(1, (x - track.x) / track.width));
                        pop.p.position = f * pop.p.length;
                    }
                    onPressed: m => set(m.x)
                    onPositionChanged: m => { if (pressed) set(m.x); }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: root.fmt(pop.p?.position ?? 0)
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: root.fmt(pop.p?.length ?? 0)
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            BarButton {
                implicitHeight: 40
                implicitWidth: 44
                icon: "media-skip-backward"
                enabled: pop.p?.canGoPrevious ?? false
                opacity: enabled ? 1 : 0.4
                tooltip: "Previous"
                onClicked: pop.p.previous()
            }
            BarButton {
                implicitHeight: 48
                implicitWidth: 52
                iconSize: 32
                icon: pop.p?.isPlaying ? "media-playback-pause" : "media-playback-start"
                enabled: pop.p?.canTogglePlaying ?? false
                opacity: enabled ? 1 : 0.4
                tooltip: pop.p?.isPlaying ? "Pause" : "Play"
                onClicked: pop.p.togglePlaying()
            }
            BarButton {
                implicitHeight: 40
                implicitWidth: 44
                icon: "media-skip-forward"
                enabled: pop.p?.canGoNext ?? false
                opacity: enabled ? 1 : 0.4
                tooltip: "Next"
                onClicked: pop.p.next()
            }
        }
    }
}
