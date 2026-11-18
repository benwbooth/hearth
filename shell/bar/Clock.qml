import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../widgets"
import ".."

// Two-line 24h clock with ISO date, like the Plasma panel; click for a
// month calendar.
Indicator {
    id: root
    ipcName: "clock"
    implicitWidth: col.implicitWidth + 16

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    tooltip: Qt.formatDateTime(clock.date, "dddd, MMMM d, yyyy")

    Column {
        id: col
        parent: root
        anchors.centerIn: parent
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            font.pointSize: Theme.fontSize + 1
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.date, "yyyy-MM-dd")
        }
    }

    popupContent: ColumnLayout {
        id: cal
        property date shown: new Date(clock.date.getFullYear(), clock.date.getMonth(), 1)
        implicitWidth: 300
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            BarButton {
                implicitHeight: 28
                icon: "go-previous"
                onClicked: cal.shown = new Date(cal.shown.getFullYear(), cal.shown.getMonth() - 1, 1)
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(cal.shown, "MMMM yyyy")
                font.weight: Font.DemiBold
                MouseArea {
                    anchors.fill: parent
                    onClicked: cal.shown = new Date(clock.date.getFullYear(), clock.date.getMonth(), 1)
                }
            }
            BarButton {
                implicitHeight: 28
                icon: "go-next"
                onClicked: cal.shown = new Date(cal.shown.getFullYear(), cal.shown.getMonth() + 1, 1)
            }
        }

        DayOfWeekRow {
            Layout.fillWidth: true
            locale: Qt.locale("en_GB")
            delegate: Label {
                required property string shortName
                horizontalAlignment: Text.AlignHCenter
                text: shortName.substring(0, 2)
                elide: Text.ElideNone
                color: Theme.fgDim
                font.pointSize: Theme.smallFontSize
            }
        }

        MonthGrid {
            Layout.fillWidth: true
            Layout.preferredHeight: 6 * 34
            month: cal.shown.getMonth()
            year: cal.shown.getFullYear()
            locale: Qt.locale("en_GB")
            delegate: Rectangle {
                required property var model
                readonly property bool today: model.today
                implicitHeight: 32
                radius: 16
                color: today ? Theme.accent : "transparent"
                Label {
                    anchors.centerIn: parent
                    text: parent.model.day
                    color: parent.today ? Theme.bg : parent.model.month === cal.shown.getMonth() ? Theme.fg : Theme.fgDim
                    font.weight: parent.today ? Font.Bold : Font.Normal
                }
            }
        }
    }
}
