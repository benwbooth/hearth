import QtQuick
import "indicators"

// hearth's indicators for the classic panel (bar/Bar.qml), in the menu
// bar's default order. The macOS menu bar places each one itself, by
// Settings > Menu Bar's item list (bar/MenuBar.qml).
Row {
    spacing: 0
    Recording { ipcName: "recording" }
    Media { ipcName: "media" }
    Clipboard { ipcName: "clipboard" }
    Zones { ipcName: "zones" }
    Network { ipcName: "network" }
    Rdp { ipcName: "rdp" }
    Camera { ipcName: "camera" }
    Printers { ipcName: "printers" }
    Drives { ipcName: "drives" }
    Weather { ipcName: "weather" }
    Keyboard { ipcName: "keyboard" }
    Battery { ipcName: "battery" }
    Bluetooth { ipcName: "bluetooth" }
    Brightness { ipcName: "brightness" }
    Volume { ipcName: "volume" }
    NotificationBell {}
}
