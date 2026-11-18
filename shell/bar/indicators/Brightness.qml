import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Display brightness (DDC/CI or backlight) and night light. Scroll for
// +-5%, click for a slider per display and the night light controls.
Indicator {
    id: root
    shown: Brightness.available
    icon: Brightness.percent >= 50 ? "brightness-high" : "brightness-low"
    tooltip: "Brightness " + Brightness.percent + "%"
    tooltipSub: Brightness.nightLight ? `Night light on (${Brightness.temperature} K)` : ""

    onScrolled: delta => Brightness.step(delta > 0 ? 5 : -5, true)
    onMiddleClicked: Brightness.setNightLight(!Brightness.nightLight)

    // Pick up changes made with the monitor's own buttons.
    Connections {
        target: root.popup
        function onOpenChanged() { if (root.popup.open) Brightness.refresh(); }
    }

    popupContent: ColumnLayout {
        spacing: 8

        Repeater {
            model: Brightness.displays
            delegate: ColumnLayout {
                id: disp
                required property var modelData
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: disp.modelData.model ? `${disp.modelData.model} (${disp.modelData.name})` : disp.modelData.name
                    font.weight: Font.DemiBold
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Icon {
                        implicitSize: 16
                        name: "brightness-low"
                    }
                    HSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        stepSize: 1
                        enabled: disp.modelData.ready
                        value: disp.modelData.value
                        onMoved: Brightness.set(disp.modelData, value, false)
                    }
                    Label {
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: disp.modelData.ready ? disp.modelData.value + "%" : "…"
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: disp.modelData.error !== "" && !disp.modelData.ready
                    text: disp.modelData.error
                    color: Theme.warn
                    font.pointSize: Theme.smallFontSize
                    wrapMode: Text.Wrap
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.minimumWidth: 320
            Layout.preferredHeight: 1
            color: Theme.border
        }

        MouseArea {
            id: nightRow
            Layout.fillWidth: true
            implicitHeight: 30
            hoverEnabled: true
            onClicked: Brightness.setNightLight(!Brightness.nightLight)
            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: nightRow.pressed ? Theme.pressed : nightRow.containsMouse ? Theme.hover : "transparent"
            }
            Icon {
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 16
                name: Brightness.nightLight ? "redshift-status-on" : "redshift-status-off"
            }
            Label {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                text: "Night light"
            }
            Rectangle {
                id: sw
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 18
                radius: 9
                color: Brightness.nightLight ? Theme.accent : Theme.border
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    y: 2
                    x: Brightness.nightLight ? sw.width - width - 2 : 2
                    color: Theme.fg
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            opacity: Brightness.nightLight ? 1 : 0.5
            Icon {
                implicitSize: 16
                name: "color-temperature"
                fallback: "redshift-status-on"
            }
            HSlider {
                Layout.fillWidth: true
                from: Brightness.minTemperature
                to: Brightness.maxTemperature
                stepSize: 100
                value: Brightness.temperature
                onMoved: Brightness.setTemperature(value)
            }
            Label {
                Layout.preferredWidth: 52
                horizontalAlignment: Text.AlignRight
                text: Brightness.temperature + " K"
            }
        }
    }

    component HSlider: Slider {
        id: s
        implicitHeight: 24
        background: Rectangle {
            x: s.leftPadding
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: s.availableWidth
            height: 4
            radius: 2
            color: Theme.border
            Rectangle {
                width: s.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: s.enabled ? Theme.accent : Theme.fgDim
            }
        }
        handle: Rectangle {
            x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: 16
            height: 16
            radius: 8
            color: s.pressed ? Theme.fg : Theme.bgRaised
            border.color: s.enabled ? Theme.accent : Theme.fgDim
            border.width: 2
        }
    }
}
