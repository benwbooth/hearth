pragma Singleton
import QtQuick
import Quickshell

// Breeze Dark colours, matching the Plasma panel this shell replaces.
Singleton {
    readonly property color bg: "#202326"
    readonly property color bgAlt: "#292c30"
    readonly property color bgRaised: "#31363b"
    readonly property color border: "#3f444a"
    readonly property color fg: "#fcfcfc"
    readonly property color fgDim: "#a1a9b1"
    readonly property color accent: "#3daee9"
    readonly property color accentDim: "#1e5774"
    readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
    readonly property color pressed: Qt.rgba(1, 1, 1, 0.14)
    readonly property color good: "#27ae60"
    readonly property color warn: "#f67400"
    readonly property color bad: "#da4453"

    readonly property int barHeight: 44
    readonly property int iconSize: 22
    readonly property int taskIconSize: 32
    readonly property int radius: 6
    readonly property int popupRadius: 8
    readonly property int spacing: 6

    readonly property string fontFamily: "Noto Sans"
    readonly property real fontSize: 10
    readonly property real smallFontSize: 8.5
    readonly property string monoFamily: "Hack"
}
