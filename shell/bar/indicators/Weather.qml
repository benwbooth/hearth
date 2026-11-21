import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../widgets"
import "../../services"
import "../.."

// Weather (Open-Meteo): condition icon and temperature in the bar; the
// popup has current details, the next 12 hours and 7 days, a units toggle
// and a place search to set the location.
Indicator {
    id: root
    // Monochrome menu bar: Breeze's symbolic weather glyphs, not silhouettes.
    icon: Weather.icon + (root.menuBarItem && root.monochrome ? "-symbolic" : "")
    text: Weather.current ? Math.round(Weather.current.temp) + "°" : ""
    tooltip: !Weather.hasLocation ? "Weather: set location"
           : Weather.current ? `${Weather.locationName}: ${Math.round(Weather.current.temp)}${Weather.tempUnit}, ${Weather.current.text}`
           : Weather.error ? "Weather unavailable" : "Weather loading…"
    tooltipSub: Weather.current
        ? `High ${Math.round(Weather.current.high)}° · Low ${Math.round(Weather.current.low)}°`
        : Weather.error

    function deg(t) { return Math.round(t) + "°"; }
    function dayName(iso, i) {
        if (i === 0) return "Today";
        const p = iso.split("-");
        return Qt.formatDate(new Date(+p[0], +p[1] - 1, +p[2]), "ddd");
    }
    function clock(iso) { return iso.length >= 16 ? iso.substring(11, 16) : ""; }

    popupContent: ColumnLayout {
        id: pop
        // Search mode until a location is set, or while changing it.
        property bool searching: !Weather.hasLocation
        spacing: 10

        // --- Header: place, units, change location ---
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 460
            spacing: 4
            Label {
                Layout.fillWidth: true
                text: Weather.hasLocation
                    ? Weather.location.name + (Weather.location.admin1 ? ", " + Weather.location.admin1 : "")
                      + (Weather.location.country ? ", " + Weather.location.country : "")
                    : "Weather"
                font.weight: Font.DemiBold
            }
            BarButton {
                implicitHeight: 28
                text: Weather.imperial ? "°F" : "°C"
                tooltip: Weather.imperial ? "Switch to metric" : "Switch to °F / mph"
                onClicked: Weather.setImperial(!Weather.imperial)
            }
            BarButton {
                implicitHeight: 28
                visible: Weather.hasLocation
                icon: pop.searching ? "go-previous" : "find-location"
                iconFallback: "edit-find"
                tooltip: pop.searching ? "Back" : "Change location"
                onClicked: pop.searching = !pop.searching
            }
            BarButton {
                implicitHeight: 28
                visible: Weather.hasLocation && !pop.searching
                icon: "view-refresh"
                tooltip: "Refresh"
                onClicked: Weather.refresh()
            }
        }

        // --- Location search ---
        ColumnLayout {
            id: search
            Layout.fillWidth: true
            visible: pop.searching
            spacing: 6
            property var results: []
            property string status: Weather.hasLocation ? "" : "Search for your town or city to show the weather."

            function run() {
                search.status = "Searching…";
                Weather.search(field.text, (res, err) => {
                    search.results = res;
                    search.status = err ? err : res.length === 0 ? "No places found." : "";
                });
            }

            TextField {
                id: field
                Layout.fillWidth: true
                placeholderText: "Place name"
                renderType: Text.NativeRendering
                font.family: Theme.fontFamily
                font.pointSize: Theme.fontSize
                color: Theme.fg
                placeholderTextColor: Theme.fgDim
                selectByMouse: true
                leftPadding: 8
                background: Rectangle {
                    implicitHeight: 30
                    radius: Theme.radius
                    color: Theme.bg
                    border.color: field.activeFocus ? Theme.accent : Theme.border
                }
                onAccepted: search.run()
                onTextChanged: searchDebounce.restart()
                // Focus once the popup surface is up and has the keyboard.
                Timer {
                    running: pop.searching
                    interval: 150
                    onTriggered: field.forceActiveFocus()
                }
                Connections {
                    target: pop
                    function onSearchingChanged() { if (pop.searching) field.forceActiveFocus(); }
                }
                Keys.onEscapePressed: root.popup.close()
            }
            Timer {
                id: searchDebounce
                interval: 400
                onTriggered: if (field.text.trim().length >= 2) search.run()
            }
            Label {
                Layout.fillWidth: true
                visible: search.status !== ""
                text: search.status
                color: Theme.fgDim
                wrapMode: Text.Wrap
            }
            Repeater {
                model: search.results
                delegate: MenuItem {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: "mark-location"
                    text: modelData.name + (modelData.admin1 ? ", " + modelData.admin1 : "")
                          + (modelData.country ? ", " + modelData.country : "")
                    onTriggered: {
                        Weather.setLocation(modelData);
                        pop.searching = false;
                    }
                }
            }
        }

        // --- Current conditions ---
        Label {
            visible: !pop.searching && !Weather.current
            text: Weather.error ? "Couldn't load the weather: " + Weather.error : "Loading…"
            color: Weather.error ? Theme.warn : Theme.fgDim
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !pop.searching && Weather.current !== null
            spacing: 14
            Icon {
                implicitSize: 64
                name: Weather.current ? Weather.current.icon : ""
            }
            ColumnLayout {
                spacing: 0
                Label {
                    text: Weather.current ? root.deg(Weather.current.temp) : ""
                    font.pointSize: 24
                    font.weight: Font.Light
                }
                Label {
                    text: Weather.current ? Weather.current.text : ""
                    color: Theme.fgDim
                }
            }
            Item { Layout.fillWidth: true }
            Column {
                spacing: 2
                Repeater {
                    model: Weather.current ? [
                        ["Feels like", root.deg(Weather.current.feels)],
                        ["High / low", root.deg(Weather.current.high) + " / " + root.deg(Weather.current.low)],
                        ["Humidity", Math.round(Weather.current.humidity) + "%"],
                        ["Wind", Math.round(Weather.current.wind) + " " + Weather.windUnit + " " + Weather.current.windDir],
                        ["Sunrise / set", Weather.daily.length > 0 ? root.clock(Weather.daily[0].sunrise) + " / " + root.clock(Weather.daily[0].sunset) : ""]
                    ] : []
                    delegate: Row {
                        required property var modelData
                        spacing: 10
                        Label {
                            width: 80
                            text: modelData[0]
                            color: Theme.fgDim
                            font.pointSize: Theme.smallFontSize
                        }
                        Label {
                            text: modelData[1]
                            font.pointSize: Theme.smallFontSize
                        }
                    }
                }
            }
        }

        // --- Next 12 hours ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: !pop.searching && Weather.hourly.length > 0
            color: Theme.border
        }
        Row {
            id: hours
            Layout.fillWidth: true
            visible: !pop.searching && Weather.hourly.length > 0
            Repeater {
                model: Weather.hourly.slice(0, 12)
                delegate: Column {
                    required property var modelData
                    required property int index
                    width: hours.width / 12
                    spacing: 2
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: index === 0 ? "Now" : root.clock(modelData.time).substring(0, 2)
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                    }
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitSize: 22
                        name: modelData.icon
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.deg(modelData.temp)
                        font.pointSize: Theme.smallFontSize
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.pop > 0 ? modelData.pop + "%" : " "
                        color: Theme.accent
                        font.pointSize: Theme.smallFontSize - 1
                    }
                }
            }
        }

        // --- 7 days ---
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: !pop.searching && Weather.daily.length > 0
            color: Theme.border
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: !pop.searching && Weather.daily.length > 0
            spacing: 2
            Repeater {
                model: Weather.daily
                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 10
                    Label {
                        Layout.preferredWidth: 48
                        text: root.dayName(modelData.date, index)
                    }
                    Icon {
                        implicitSize: 22
                        name: modelData.icon
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.text
                        color: Theme.fgDim
                    }
                    Label {
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                        text: modelData.pop > 0 ? modelData.pop + "%" : ""
                        color: Theme.accent
                        font.pointSize: Theme.smallFontSize
                    }
                    Label {
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: root.deg(modelData.min)
                        color: Theme.fgDim
                    }
                    Label {
                        Layout.preferredWidth: 36
                        horizontalAlignment: Text.AlignRight
                        text: root.deg(modelData.max)
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !pop.searching && Weather.current !== null
            text: "Open-Meteo · updated " + Qt.formatTime(Weather.updated, "HH:mm")
                  + (Weather.error ? " · " + Weather.error : "")
            color: Theme.fgDim
            font.pointSize: Theme.smallFontSize - 1
            horizontalAlignment: Text.AlignRight
        }
    }
}
