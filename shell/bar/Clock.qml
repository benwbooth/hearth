import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../widgets"
import "../services"
import ".."

// Two-line 24h clock with ISO date, like the Plasma panel; click for a
// month calendar with your events from Almanac (services/Calendar.qml):
// dots under days with events, the chosen day's agenda (today and tomorrow
// by default), click an event to open it in Almanac, New Event… for the day.
Indicator {
    id: root
    ipcName: "clock"
    // In the menu bar: one line, macOS style: "Fri Nov 20  4:50 PM" in the
    // locale's date order ("Fri 20 Nov" where the day comes first), two
    // spaces before the time, as set in Settings > Menu Bar.
    readonly property bool compact: !!root.QsWindow.window && root.QsWindow.window.edge === "top"
    readonly property var mb: Settings.menubar
    readonly property string lineText: {
        const d = clock.date;
        const parts = [];
        if (mb.showWeekday) parts.push(Qt.formatDate(d, "ddd"));
        if (mb.showDate) parts.push(Qt.formatDate(d, dayFirst ? "d MMM" : "MMM d"));
        const t = mb.clock24h ? (mb.showSeconds ? "HH:mm:ss" : "HH:mm") : (mb.showSeconds ? "h:mm:ss AP" : "h:mm AP");
        parts.push(" " + Qt.formatTime(d, t));
        return nextText + parts.join(" ");
    }
    // Settings > Menu Bar > "Show the next event": "Standup in 10 min" before
    // the date, from an hour ahead (off by default).
    readonly property string nextText: {
        const e = Calendar.nextEvent, m = Calendar.nextInMinutes;
        if (!mb.showNextEvent || !Calendar.enabled || !e || m > 60) return "";
        const title = e.title.length > 28 ? e.title.substring(0, 27) + "…" : (e.title || "Event");
        return title + (m <= 0 ? " now" : " in " + m + " min") + "   ";
    }
    function fmtTime(d) { return Qt.formatTime(d, mb.clock24h ? "HH:mm" : "h:mm AP"); }
    readonly property bool dayFirst: { const f = Qt.locale().dateFormat(Locale.ShortFormat); return f.indexOf("d") < f.indexOf("M"); }
    implicitWidth: compact ? line.implicitWidth + 2 * Math.round(8 * Theme.pt) : col.implicitWidth + 16

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
        color: Theme.barFg
        // macOS: regular weight, tabular digits so the time doesn't jiggle.
        font.pointSize: Theme.menuBarFontSize
        font.letterSpacing: Theme.menuTracking
        font.features: { "tnum": 1 }
    }

    tooltip: Qt.formatDateTime(clock.date, "dddd, MMMM d, yyyy")
    tooltipSub: Calendar.nextEvent && Calendar.nextInMinutes <= 12 * 60
        ? "Next: " + Calendar.nextEvent.title + " at " + fmtTime(Calendar.parse(Calendar.nextEvent.start))
        : Calendar.enabled ? "Click for your calendar" : ""

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

    // A fixed width (a Layout's own implicitWidth follows its widest line, so
    // the popup grew when a day with long event titles was picked): long
    // titles end in "…" instead.
    popupContent: Item {
        implicitWidth: 360
        implicitHeight: cal.implicitHeight
    ColumnLayout {
        id: cal
        width: parent.width
        property date shown: new Date(clock.date.getFullYear(), clock.date.getMonth(), 1)
        // The day whose events are listed ("" = today, with tomorrow after it).
        property string picked: ""
        readonly property string todayKey: Calendar.iso(clock.date)
        readonly property string dayKey: picked || todayKey
        onShownChanged: Calendar.month = shown
        Component.onCompleted: Calendar.month = shown
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            BarButton {
                implicitHeight: 28
                icon: "go-previous"
                tooltip: "Previous month"
                onClicked: cal.shown = new Date(cal.shown.getFullYear(), cal.shown.getMonth() - 1, 1)
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(cal.shown, "MMMM yyyy")
                font.weight: Font.DemiBold
                MouseArea {
                    id: monthTitle
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { cal.shown = new Date(clock.date.getFullYear(), clock.date.getMonth(), 1); cal.picked = ""; }
                }
                Tooltip { anchorItem: monthTitle; text: "Back to today"; hovered: monthTitle.containsMouse }
            }
            BarButton {
                implicitHeight: 28
                icon: "go-next"
                tooltip: "Next month"
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
            delegate: Item {
                id: dayCell
                required property var model
                readonly property bool today: model.today
                readonly property string key: Calendar.iso(model.date)
                readonly property bool chosen: cal.picked === key && !today
                readonly property var evs: Calendar.dayEvents(key)
                implicitHeight: 32
                Rectangle {
                    anchors.centerIn: parent
                    width: 30; height: 30; radius: 15
                    color: dayCell.today ? Theme.accent : dayCell.chosen ? Theme.accentDim : dayArea.containsMouse ? Theme.hover : "transparent"
                }
                Label {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: dayCell.evs.length ? -2 : 0
                    text: dayCell.model.day
                    color: dayCell.today ? Theme.accentText : dayCell.model.month === cal.shown.getMonth() ? Theme.fg : Theme.fgDim
                    font.weight: dayCell.today ? Font.Bold : Font.Normal
                }
                // Up to three dots in the events' calendar colours.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    spacing: 2
                    Repeater {
                        model: {
                            const seen = [];
                            for (const e of dayCell.evs) if (seen.indexOf(e.color) < 0 && seen.length < 3) seen.push(e.color);
                            return seen;
                        }
                        Rectangle {
                            required property string modelData
                            width: 4; height: 4; radius: 2
                            color: dayCell.today ? Theme.accentText : modelData
                        }
                    }
                }
                MouseArea {
                    id: dayArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        cal.picked = dayCell.today ? "" : dayCell.key;
                        if (dayCell.model.month !== cal.shown.getMonth()) cal.shown = new Date(dayCell.model.year, dayCell.model.month, 1);
                    }
                }
                Tooltip {
                    anchorItem: dayCell
                    hovered: dayArea.containsMouse && Calendar.enabled
                    text: Qt.formatDate(dayCell.model.date, "dddd, MMMM d")
                    subtext: dayCell.evs.length ? dayCell.evs.length + (dayCell.evs.length === 1 ? " event" : " events") : "No events"
                }
            }
        }

        // ---- the agenda (Almanac) ----
        Rectangle {
            visible: Calendar.enabled
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }
        RowLayout {
            visible: Calendar.enabled
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: cal.dayTitle(cal.dayKey)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            BarButton {
                implicitHeight: 26
                icon: "list-add"
                text: "New Event…"
                visible: Calendar.available
                tooltip: "New event in Almanac"
                tooltipSub: Qt.formatDate(Calendar.parse(cal.dayKey), "dddd, MMMM d")
                onClicked: { Calendar.newEvent(cal.dayKey); root.popup.close(); }
            }
        }
        function dayTitle(k) {
            if (k === todayKey) return "Today";
            if (k === Calendar.iso(Calendar.addDays(clock.date, 1))) return "Tomorrow";
            return Qt.formatDate(Calendar.parse(k), "dddd, MMMM d");
        }

        Label {
            visible: Calendar.enabled && !Calendar.available
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.fgDim
            text: Calendar.reason ? Calendar.reason + ": your events from Almanac show here once it's set up." : "Reading your calendar…"
        }
        Label {
            visible: Calendar.enabled && Calendar.available && Calendar.calendars.length === 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.fgDim
            text: "No calendars in Almanac yet. Add one there and its events show here."
        }

        Flickable {
            id: agendaScroll
            visible: Calendar.enabled && Calendar.available && Calendar.calendars.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(agenda.implicitHeight, 280)
            contentHeight: agenda.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: agenda
                width: agendaScroll.width
                spacing: 2
                readonly property var sections: {
                    const out = [{ key: cal.dayKey, title: "", list: Calendar.dayEvents(cal.dayKey) }];
                    if (!cal.picked) {
                        const tk = Calendar.iso(Calendar.addDays(clock.date, 1));
                        out.push({ key: tk, title: "Tomorrow", list: Calendar.dayEvents(tk) });
                    }
                    return out;
                }
                Repeater {
                    model: agenda.sections
                    ColumnLayout {
                        id: section
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            visible: section.index > 0
                            Layout.topMargin: 6
                            text: section.modelData.title
                            font.weight: Font.DemiBold
                        }
                        Label {
                            visible: section.modelData.list.length === 0
                            Layout.fillWidth: true
                            text: "No events"
                            color: Theme.fgDim
                        }
                        Repeater {
                            model: section.modelData.list
                            delegate: MouseArea {
                                id: row
                                required property var modelData
                                readonly property var e: modelData
                                readonly property date s: Calendar.parse(e.start)
                                readonly property date en: Calendar.parse(e.end)
                                readonly property bool past: !e.allDay && en <= clock.date
                                Layout.fillWidth: true
                                implicitHeight: rowCol.implicitHeight + 8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                opacity: past ? 0.55 : 1
                                onClicked: { Calendar.openEvent(e); root.popup.close(); }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radius
                                    color: row.pressed ? Theme.pressed : row.containsMouse ? Theme.hover : "transparent"
                                }
                                Rectangle {
                                    id: bar
                                    x: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3; height: parent.height - 10; radius: 1.5
                                    color: row.e.color || Theme.accent
                                }
                                ColumnLayout {
                                    id: rowCol
                                    anchors.left: bar.right
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label {
                                            Layout.fillWidth: true
                                            text: row.e.title || "(No title)"
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: row.e.allDay ? "All day" : root.fmtTime(row.s)
                                            color: Theme.fgDim
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                    Label {
                                        visible: text !== ""
                                        Layout.fillWidth: true
                                        text: {
                                            const parts = [];
                                            if (!row.e.allDay) parts.push(root.fmtTime(row.s) + " – " + root.fmtTime(row.en));
                                            if (row.e.location) parts.push(row.e.location);
                                            return parts.join("  ·  ");
                                        }
                                        color: Theme.fgDim
                                        font.pointSize: Theme.smallFontSize
                                        elide: Text.ElideRight
                                    }
                                }
                                Tooltip {
                                    anchorItem: row
                                    hovered: row.containsMouse
                                    text: "Open in Almanac"
                                    subtext: row.e.title
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
