import QtQuick
import QtQuick.Effects
import ".."

// A liquid-glass pane (menus, popups, previews), macOS 26 style: tinted
// glass over whatever the compositor blurs behind it, a soft sheen in its
// top half, a dark outline, and a thin specular rim that is brightest at the
// top-left corner and fades towards the bottom-right. Carries the 0.001 px
// text nudge for its surface.
Rectangle {
    id: root
    property color tint: Theme.glassMenu
    property bool rimVisible: true
    color: tint
    radius: Theme.popupRadius
    border.color: Theme.glassEdge
    border.width: 1
    transform: Translate { x: 0.001; y: 0.001 }

    // Sheen: light caught in the upper part of the glass.
    Rectangle {
        visible: root.rimVisible
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.07 : 0.22) }
            GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.015 : 0.05) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
        }
    }

    // Specular rim: a 1 px inner outline, masked by a light falloff from
    // the top-left.
    Item {
        id: rimArea
        visible: root.rimVisible
        anchors.fill: parent
        anchors.margins: 1

        Rectangle {
            id: rimLine
            anchors.fill: parent
            radius: Math.max(0, root.radius - 1)
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, Math.min(1, Theme.specular * 2.2))
            border.width: 1
            visible: false
            layer.enabled: true
        }
        Item {
            id: falloff
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 1) }
                    GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.45) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.22) }
                }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
        }
        MultiEffect {
            anchors.fill: parent
            source: rimLine
            maskEnabled: true
            maskSource: falloff
            maskThresholdMin: 0
            maskSpreadAtMin: 1
        }
    }
}
