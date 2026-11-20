import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../widgets"
import "../services"
import ".."

// hearth Settings: a normal floating window (System Settings style, a
// sidebar of panes) for everything in services/Settings.qml plus
// wallpaper, night light and notifications. Every change applies at once
// and is saved to ~/.config/hearth/settings.json.
// Opened from the menu bar's system menu or `hearth-ipc call settings open`.
Scope {
    id: root
    property bool open: false
    property string pane: "appearance"

    Connections {
        target: Settings
        function onOpenRequested(pane) { if (pane) root.pane = pane; root.open = true; }
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: "hearth Settings"
            visible: true
            implicitWidth: 920
            implicitHeight: 640
            minimumSize: Qt.size(760, 480)
            color: Theme.bg
            onVisibleChanged: if (!visible) root.open = false

            Item {
                anchors.fill: parent
                transform: Translate { x: 0.001; y: 0.001 }

                // Sidebar.
                Rectangle {
                    id: side
                    width: 220
                    height: parent.height
                    color: Theme.bgAlt
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }

                    Column {
                        x: 10
                        y: 14
                        width: parent.width - 20
                        spacing: 2
                        Repeater {
                            model: [
                                { id: "appearance", label: "Appearance", icon: "preferences-desktop-theme-global" },
                                { id: "menubar", label: "Menu Bar", icon: "preferences-desktop" },
                                { id: "dock", label: "Desktop & Dock", icon: "preferences-system-windows" },
                                { id: "layout", label: "Layout", icon: "view-split-top-bottom" },
                                { id: "wallpaper", label: "Wallpaper", icon: "preferences-desktop-wallpaper" },
                                { id: "night", label: "Night Light", icon: "redshift-status-on" },
                                { id: "notifications", label: "Notifications", icon: "preferences-desktop-notification" }
                            ]
                            MouseArea {
                                id: navItem
                                required property var modelData
                                width: parent.width
                                height: 34
                                hoverEnabled: true
                                onClicked: root.pane = modelData.id
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radius
                                    color: root.pane === navItem.modelData.id ? Theme.accent
                                         : navItem.containsMouse ? Theme.hover : "transparent"
                                }
                                Row {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    Icon { implicitSize: 20; name: navItem.modelData.icon; anchors.verticalCenter: parent.verticalCenter }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: navItem.modelData.label
                                        color: root.pane === navItem.modelData.id ? Theme.accentText : Theme.fg
                                    }
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: flick
                    anchors.left: side.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    contentHeight: paneCol.implicitHeight + 48
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: paneCol
                        x: 28
                        y: 22
                        width: flick.width - 56
                        spacing: 14

                        Label {
                            text: ({ appearance: "Appearance", menubar: "Menu Bar", dock: "Desktop & Dock", layout: "Layout",
                                     wallpaper: "Wallpaper", night: "Night Light", notifications: "Notifications" })[root.pane]
                            font.pointSize: Theme.fontSize + 6
                            font.weight: Font.Bold
                        }

                        Loader {
                            Layout.fillWidth: true
                            sourceComponent: ({ appearance: appearancePane, menubar: menubarPane, dock: dockPane, layout: layoutPane,
                                                wallpaper: wallpaperPane, night: nightPane, notifications: notificationsPane })[root.pane]
                        }
                    }
                }
            }
        }
    }

    // --- building blocks ---

    // A rounded group of rows, like macOS settings.
    component Group: Rectangle {
        default property alias rows: col.data
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + 8
        radius: Theme.popupRadius
        color: Theme.bgAlt
        border.color: Theme.border
        Column {
            id: col
            x: 14
            y: 4
            width: parent.width - 28
        }
    }
    component Row_: Item {
        id: r
        property string label
        property string note: ""
        default property alias control: holder.data
        width: parent ? parent.width : 400
        implicitHeight: Math.max(44, texts.implicitHeight + 16)
        Column {
            id: texts
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - holder.width - 16
            Label { text: r.label; width: parent.width }
            Label {
                visible: r.note !== ""
                text: r.note
                width: parent.width
                color: Theme.fgDim
                font.pointSize: Theme.smallFontSize
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
        }
        Item {
            id: holder
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }
    component SwitchRow: Row_ {
        id: sr
        property string key
        Toggle {
            checked: !!Settings.get(sr.key)
            onToggled: c => Settings.set(sr.key, c)
        }
    }
    component SliderRow: Row_ {
        id: slr
        property string key
        property real from: 0
        property real to: 100
        property real step: 1
        property string suffix: ""
        property int decimals: 0
        property real scale: 1
        ValueSlider {
            implicitWidth: 300
            from: slr.from
            to: slr.to
            step: slr.step
            suffix: slr.suffix
            decimals: slr.decimals
            value: { void Settings.data; return Settings.get(slr.key) * slr.scale; }
            onMoved: v => Settings.set(slr.key, v / slr.scale)
        }
    }
    component ChoiceRow: Row_ {
        id: cr
        property string key
        property var options: []
        Segmented {
            options: cr.options
            value: { void Settings.data; return Settings.get(cr.key); }
            onPicked: v => Settings.set(cr.key, v)
        }
    }
    component Divider: Rectangle {
        width: parent ? parent.width : 100
        height: 1
        color: Theme.border
    }

    // --- panes ---

    Component {
        id: appearancePane
        ColumnLayout {
            spacing: 14
            Group {
                ChoiceRow {
                    label: "Appearance"
                    key: "appearance.mode"
                    options: [{ value: "light", label: "Light" }, { value: "dark", label: "Dark" }, { value: "auto", label: "Auto" }]
                    note: "Auto is light from 7:00 to 19:00."
                }
                Divider {}
                Row_ {
                    label: "Accent colour"
                    Row {
                        spacing: 8
                        Repeater {
                            model: ["#3daee9", "#007aff", "#a550a7", "#f74f9e", "#da4453", "#f67400", "#fdbc4b", "#27ae60", "#8e8e93"]
                            MouseArea {
                                id: sw
                                required property var modelData
                                width: 22
                                height: 22
                                onClicked: Settings.set("appearance.accent", modelData)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 11
                                    color: sw.modelData
                                    border.width: Settings.appearance.accent === sw.modelData ? 3 : 0
                                    border.color: Theme.fg
                                }
                            }
                        }
                    }
                }
            }
            Group {
                SliderRow {
                    label: "Glass transparency"
                    note: "How much of the blurred background shows through the menu bar, dock and menus."
                    key: "appearance.glass"
                    from: 0; to: 100; step: 5; scale: 100; suffix: "%"
                    enabled: !Settings.appearance.reduceTransparency
                }
                Divider {}
                SwitchRow {
                    label: "Reduce transparency"
                    note: "Solid menu bar, dock and menus."
                    key: "appearance.reduceTransparency"
                }
            }
        }
    }

    Component {
        id: menubarPane
        ColumnLayout {
            spacing: 14
            Group {
                SwitchRow { label: "Automatically hide and show the menu bar"; note: "Hidden until you move the pointer to the top edge."; key: "menubar.autohide" }
                Divider {}
                SwitchRow { label: "Show the app name"; note: "The bold name of the app you are using, next to the logo."; key: "menubar.showAppName" }
                Divider {}
                ChoiceRow {
                    label: "Menu logo"
                    note: "The button at the far left that opens the system menu."
                    key: "menubar.logo"
                    options: [{ value: "nixos", label: "NixOS" }, { value: "penguin", label: "Penguin" }, { value: "none", label: "None" }]
                }
            }
            Label { text: "Clock"; font.weight: Font.DemiBold }
            Group {
                SwitchRow { label: "24-hour time"; note: "13:00 instead of 1:00 PM."; key: "menubar.clock24h" }
                Divider {}
                SwitchRow { label: "Show the date"; key: "menubar.showDate" }
                Divider {}
                SwitchRow { label: "Show the day of the week"; key: "menubar.showWeekday" }
                Divider {}
                SwitchRow { label: "Show seconds"; key: "menubar.showSeconds" }
            }
            Label { text: "Menu bar items"; font.weight: Font.DemiBold }
            Group {
                Repeater {
                    model: [
                        { id: "media", label: "Now Playing" }, { id: "zones", label: "Window zones (Hyprland)" },
                        { id: "network", label: "Network" }, { id: "rdp", label: "Remote desktop" },
                        { id: "camera", label: "Camera in use" }, { id: "printers", label: "Printers" },
                        { id: "drives", label: "Drives" }, { id: "weather", label: "Weather" },
                        { id: "keyboard", label: "Keyboard" }, { id: "battery", label: "Battery" },
                        { id: "bluetooth", label: "Bluetooth" }, { id: "brightness", label: "Brightness" },
                        { id: "volume", label: "Sound" }
                    ]
                    Row_ {
                        id: ind
                        required property var modelData
                        label: modelData.label
                        Toggle {
                            readonly property var hidden: Settings.menubar.hiddenIndicators || []
                            checked: hidden.indexOf(ind.modelData.id) < 0
                            onToggled: c => {
                                const h = hidden.filter(x => x !== ind.modelData.id);
                                if (!c) h.push(ind.modelData.id);
                                Settings.set("menubar.hiddenIndicators", h);
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: dockPane
        ColumnLayout {
            spacing: 14
            Group {
                SliderRow { label: "Size"; note: "How big the app icons in the Dock are."; key: "dock.size"; from: 24; to: 96; step: 2; suffix: " px" }
                Divider {}
                SwitchRow { label: "Magnification"; note: "Icons grow as the pointer moves over them."; key: "dock.magnify" }
                SliderRow {
                    label: "Magnified size"
                    key: "dock.magnifySize"; from: Settings.dock.size; to: 128; step: 2; suffix: " px"
                    enabled: Settings.dock.magnify
                }
                Divider {}
                ChoiceRow {
                    label: "Position on screen"
                    key: "dock.position"
                    options: [{ value: "left", label: "Left" }, { value: "bottom", label: "Bottom" }, { value: "right", label: "Right" }]
                }
            }
            Group {
                SwitchRow { label: "Automatically hide and show the Dock"; note: "Hidden until you move the pointer to the screen edge under it."; key: "dock.autohide" }
                SliderRow {
                    label: "Hide delay"; key: "dock.autohideDelay"; from: 0; to: 2000; step: 50; suffix: " ms"
                    enabled: Settings.dock.autohide
                }
                SliderRow {
                    label: "Animation"; note: "How long the Dock takes to slide in and out."
                    key: "dock.animationMs"; from: 0; to: 800; step: 20; suffix: " ms"
                }
            }
            Group {
                SwitchRow { label: "Show indicators for open applications"; note: "A small dot under each app that is running."; key: "dock.showIndicators" }
                Divider {}
                SwitchRow { label: "Show suggested and recent apps in the Dock"; note: "Up to three apps you used lately, after the divider."; key: "dock.showRecents" }
            }
            Group {
                ChoiceRow {
                    label: "Minimize windows using"
                    note: "Drawn by the compositor (arbor); Hyprland has no minimize animation."
                    key: "dock.minimizeEffect"
                    options: [{ value: "genie", label: "Genie" }, { value: "scale", label: "Scale" }]
                }
                Divider {}
                SwitchRow {
                    label: "Minimize windows into application icon"
                    note: "Off: minimized windows get their own tiles at the end of the Dock."
                    key: "dock.minimizeIntoApp"
                }
            }
            Label {
                Layout.fillWidth: true
                text: "Drag an app to reorder it, drag it out of the Dock to remove it, or right-click it for Keep in Dock."
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
        }
    }

    Component {
        id: layoutPane
        ColumnLayout {
            spacing: 14
            Group {
                ChoiceRow {
                    label: "Desktop layout"
                    note: "Mac: menu bar on top with the app's menus, Dock at the bottom. Classic: one Plasma-style panel at the bottom with the task manager and pager."
                    key: "layout"
                    options: [{ value: "mac", label: "Mac" }, { value: "panel", label: "Classic panel" }]
                }
            }
        }
    }

    Component {
        id: wallpaperPane
        ColumnLayout {
            spacing: 14
            Rectangle {
                Layout.preferredWidth: 480
                Layout.preferredHeight: 270
                radius: Theme.popupRadius
                color: Theme.bgAlt
                clip: true
                Image {
                    anchors.fill: parent
                    source: Wallpaper.file ? "file://" + Wallpaper.file : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 960
                }
            }
            Label { text: Wallpaper.title; font.weight: Font.DemiBold; Layout.fillWidth: true }
            Label { text: Wallpaper.copyright; color: Theme.fgDim; Layout.fillWidth: true; visible: text !== "" }
            Group {
                Row_ {
                    label: "Bing picture of the day"
                    note: "A new image every day."
                    Toggle {
                        checked: Wallpaper.mode === "potd"
                        onToggled: c => { if (c) { Wallpaper.setMode("potd", Wallpaper.image); Wallpaper.refresh(false); } }
                    }
                }
                Divider {}
                Row_ {
                    label: "Picture file"
                    note: Wallpaper.mode === "image" ? Wallpaper.image : "Pick an image to use instead."
                    BarButton {
                        implicitHeight: 30
                        text: "Choose…"
                        onClicked: picker.running = true
                    }
                }
            }
            Process {
                id: picker
                command: ["sh", "-c", "kdialog --getopenfilename \"$HOME/Pictures\" 'Images (*.jpg *.jpeg *.png *.webp)' 2>/dev/null || zenity --file-selection --file-filter='*.jpg *.jpeg *.png *.webp' 2>/dev/null"]
                stdout: StdioCollector {
                    onStreamFinished: { const p = text.trim(); if (p) Wallpaper.setMode("image", p); }
                }
            }
        }
    }

    Component {
        id: nightPane
        ColumnLayout {
            spacing: 14
            Group {
                Row_ {
                    label: "Night Light"
                    note: Compositor.isHyprland ? `On by schedule from ${Brightness.nightStartHour}:00 to ${Brightness.nightEndHour}:00 (hyprsunset); this overrides it until the next change.`
                                                : "Needs hyprsunset (Hyprland)."
                    Toggle {
                        enabled: Compositor.isHyprland
                        checked: Brightness.nightLight
                        onToggled: c => Brightness.setNightLight(c)
                    }
                }
                Divider {}
                Row_ {
                    label: "Colour temperature"
                    ValueSlider {
                        implicitWidth: 300
                        enabled: Compositor.isHyprland
                        from: Brightness.minTemperature
                        to: Brightness.maxTemperature
                        step: 100
                        suffix: " K"
                        value: Brightness.temperature
                        onMoved: v => Brightness.setTemperature(v)
                    }
                }
            }
        }
    }

    Component {
        id: notificationsPane
        ColumnLayout {
            spacing: 14
            Group {
                Row_ {
                    label: "Do Not Disturb"
                    Toggle {
                        id: dnd
                        checked: false
                        onToggled: c => { checked = c; Swaync.setDnd(c); }
                        Process {
                            running: true
                            command: ["swaync-client", "-D", "-sw"]
                            stdout: StdioCollector { onStreamFinished: dnd.checked = text.trim() === "true" }
                        }
                    }
                }
                Divider {}
                SliderRow {
                    label: "Show notifications for"
                    key: "notifications.timeout"; from: 2; to: 30; step: 1; suffix: " s"
                }
            }
            Label {
                Layout.fillWidth: true
                text: Settings.mac ? "Notifications appear at the top right, under the menu bar." : "Notifications appear at the bottom right, above the panel."
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
        }
    }
}
