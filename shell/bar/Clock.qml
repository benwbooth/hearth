import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../widgets"
import "../services"
import ".."

// Two-line 24h clock with ISO date, like the Plasma panel; click for a
// month calendar.
Indicator {
    id: root
    ipcName: "clock"
    // In the menu bar: one line, macOS style ("Thu 19 Nov  21:40"), as set in
    // Settings > Menu Bar.
    readonly property bool compact: !!root.QsWindow.window && root.QsWindow.window.edge === "top"
    readonly property var mb: Settings.menubar
    readonly property string lineText: {
        const d = clock.date;
        const parts = [];
        if (mb.showWeekday) parts.push(Qt.formatDate(d, "ddd"));
        if (mb.showDate) parts.push(Qt.formatDate(d, "d MMM"));
        const t = mb.clock24h ? (mb.showSeconds ? "HH:mm:ss" : "HH:mm") : (mb.showSeconds ? "h:mm:ss AP" : "h:mm AP");
        parts.push(" " + Qt.formatTime(d, t));
        return parts.join(" ");
    }
    implicitWidth: (compact ? line.implicitWidth : col.implicitWidth) + 16

    SystemClock {
        id: clock
        precision: root.compact && root.mb.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Label {
        id: line
        parent: root
        visible: root.compact
        anchors.centerIn: parent
        text: root.lineText
        // macOS: regular weight, tabular digits so the time doesn't jiggle.
        font.pointSize: Theme.menuBarFontSize
        font.features: { "tnum": 1 }
        style: Text.Raised
        styleColor: Theme.textHalo
    }

    tooltip: Qt.formatDateTime(clock.date, "dddd, MMMM d, yyyy")

    Column {
        id: col
        parent: root
        visible: !root.compact
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
                    color: parent.today ? Theme.accentText : parent.model.month === cal.shown.getMonth() ? Theme.fg : Theme.fgDim
                    font.weight: parent.today ? Font.Bold : Font.Normal
                }
            }
        }
    }
}
