import QtQuick
import "../widgets"
import ".."

// A button on the lock screen: a status glyph (`flat`), a round glass
// button with a caption under it (`round`: Sleep / Restart / Shut Down)
// or a capsule (`pill`). Hovering shows `tip` as a help tag drawn on the
// lock surface itself (lock surfaces can't open pop-up windows).
Item {
    id: root
    property real k: 1
    property string icon: ""
    property string text: ""
    property string caption: ""
    property string tip: ""
    property bool flat: false
    property bool round: false
    property bool pill: false
    property bool accent: false
    property Item backdrop: null
    signal clicked()

    readonly property real face: round ? Math.round(46 * k) : pill ? Math.round(32 * k) : Math.round(26 * k)
    implicitWidth: round ? Math.max(face, cap.implicitWidth) : pill ? Math.max(Math.round(96 * k), txt.implicitWidth + 32 * k)
                   : row.implicitWidth + 12 * k
    implicitHeight: round ? face + 8 * k + cap.implicitHeight : face
    width: implicitWidth
    height: implicitHeight

    Loader {
        id: glass
        x: (root.width - width) / 2
        width: root.round ? root.face : root.width
        height: root.face
        active: (root.round || root.pill) && root.backdrop !== null && !root.accent
        sourceComponent: LockGlass {
            backdrop: root.backdrop
            tint: Qt.rgba(1, 1, 1, ma.pressed ? 0.30 : ma.containsMouse ? 0.22 : 0.14)
        }
    }
    Rectangle {
        x: (root.width - width) / 2
        width: root.round ? root.face : root.width
        height: root.face
        radius: height / 2
        visible: !glass.active && (root.round || root.pill || ma.containsMouse)
        color: root.accent ? Qt.lighter(Theme.accent, ma.pressed ? 0.85 : ma.containsMouse ? 1.1 : 1)
             : Qt.rgba(1, 1, 1, ma.pressed ? 0.26 : ma.containsMouse ? 0.16 : (root.flat ? 0 : 0.14))
    }
    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        y: (root.face - height) / 2
        height: root.face
        spacing: 5 * root.k
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            name: root.icon
            implicitSize: Math.round((root.round ? 20 : 16) * root.k)
        }
        Label {
            id: txt
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""
            text: root.text
            color: "white"
            font.pointSize: 0.75 * Math.round((root.pill ? 13.5 : 13) * root.k)
            font.weight: root.pill ? Font.DemiBold : Font.Medium
        }
    }
    Label {
        id: cap
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.face + 8 * root.k
        visible: root.caption !== ""
        text: root.caption
        color: Qt.rgba(1, 1, 1, 0.85)
        font.pointSize: 0.75 * Math.round(12 * root.k)
        font.weight: Font.Medium
    }
    MouseArea {
        id: ma
        x: (root.width - width) / 2
        width: root.round ? root.face : root.width
        height: root.face
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    // Help tag (macOS: after about a second of hovering).
    Rectangle {
        id: tag
        visible: opacity > 0
        opacity: tipTimer.shown && ma.containsMouse && root.tip !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: opacity > 0 ? 160 : 110 } }
        z: 10
        x: Math.round((root.width - width) / 2)
        y: root.round || root.pill ? -height - 8 * root.k : root.face + 6 * root.k
        width: tipText.implicitWidth + 16 * root.k
        height: tipText.implicitHeight + 8 * root.k
        radius: 6 * root.k
        color: Qt.rgba(0.12, 0.12, 0.13, 0.86)
        border.color: Qt.rgba(1, 1, 1, 0.14)
        Label {
            id: tipText
            anchors.centerIn: parent
            text: root.tip
            color: "white"
            font.pointSize: 0.75 * Math.round(12 * root.k)
        }
    }
    Timer {
        id: tipTimer
        property bool shown: false
        interval: Theme.tooltipDelayMs
        running: ma.containsMouse
        onRunningChanged: if (!running) shown = false
        onTriggered: shown = true
    }
}
