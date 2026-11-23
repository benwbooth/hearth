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
    readonly property var paneFiles: ({
        hotcorners: "settings/HotCornersPane.qml", displays: "settings/DisplaysPane.qml",
        keyboard: "settings/KeyboardPane.qml", shortcuts: "settings/ShortcutsPane.qml",
        windowrules: "settings/WindowRulesPane.qml", power: "settings/PowerPane.qml",
        clipboard: "settings/ClipboardPane.qml", screenshots: "settings/ScreenshotsPane.qml",
        wallpaper: "settings/WallpaperPane.qml", lockscreen: "settings/LockScreenPane.qml",
        users: "settings/UsersPane.qml", spotlight: "settings/SpotlightPane.qml",
        ai: "settings/AiPane.qml", voice: "settings/VoicePane.qml",
        bluetooth: "settings/BluetoothPane.qml"
    })

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

                    ScrollAssist { flickable: sideFlick }
                    Flickable {
                        id: sideFlick
                        anchors.fill: parent
                        contentHeight: navCol.implicitHeight + 28
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: navCol
                        x: 10
                        y: 14
                        width: parent.width - 20
                        spacing: 2
                        Repeater {
                            model: [
                                { id: "users", label: "Users & Accounts", icon: "system-users" },
                                { id: "appearance", label: "Appearance", icon: "preferences-desktop-theme-global" },
                                { id: "menubar", label: "Menu Bar", icon: "preferences-desktop" },
                                { id: "dock", label: "Desktop & Dock", icon: "preferences-system-windows" },
                                { id: "layout", label: "Layout", icon: "view-split-top-bottom" },
                                { id: "wallpaper", label: "Wallpaper", icon: "preferences-desktop-wallpaper" },
                                { id: "lockscreen", label: "Lock Screen", icon: "system-lock-screen" },
                                { id: "hotcorners", label: "Hot Corners", icon: "preferences-desktop-screensaver" },
                                { id: "bluetooth", label: "Bluetooth", icon: "preferences-system-bluetooth" },
                                { id: "displays", label: "Displays", icon: "preferences-desktop-display" },
                                { id: "keyboard", label: "Keyboard", icon: "preferences-desktop-keyboard" },
                                { id: "shortcuts", label: "Keyboard Shortcuts", icon: "preferences-desktop-keyboard-shortcut" },
                                { id: "mouse", label: "Mouse & Touchpad", icon: "preferences-desktop-mouse" },
                                { id: "windowrules", label: "Window Rules", icon: "preferences-system-windows-actions" },
                                { id: "power", label: "Sleep & Power", icon: "preferences-system-power-management" },
                                { id: "night", label: "Night Light", icon: "redshift-status-on" },
                                { id: "notifications", label: "Notifications", icon: "preferences-desktop-notification" },
                                { id: "spotlight", label: "Search", icon: "search" },
                                { id: "ai", label: "AI", icon: Quickshell.shellDir + "/assets/ai.svg" },
                                { id: "voice", label: "Voice Assistant", icon: "audio-input-microphone" },
                                { id: "clipboard", label: "Clipboard", icon: "klipper-symbolic" },
                                { id: "screenshots", label: "Screenshots", icon: "camera-photo" }
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
                }

                ScrollAssist { flickable: flick }
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
                                     wallpaper: "Wallpaper", mouse: "Mouse & Touchpad", night: "Night Light", notifications: "Notifications",
                                     hotcorners: "Hot Corners", displays: "Displays", keyboard: "Keyboard", shortcuts: "Keyboard Shortcuts",
                                     windowrules: "Window Rules", power: "Sleep & Power", lockscreen: "Lock Screen", clipboard: "Clipboard", screenshots: "Screenshots",
                                     users: "Users & Accounts", spotlight: "Search", bluetooth: "Bluetooth", ai: "AI", voice: "Voice Assistant" })[root.pane] || ""
                            font.pointSize: Theme.fontSize + 6
                            font.weight: Font.Bold
                        }

                        // Larger panes live in popups/settings/.
                        Loader {
                            Layout.fillWidth: true
                            visible: !!root.paneFiles[root.pane]
                            active: visible
                            source: root.paneFiles[root.pane] || ""
                        }
                        Loader {
                            Layout.fillWidth: true
                            visible: !root.paneFiles[root.pane]
                            active: visible
                            sourceComponent: ({ appearance: appearancePane, menubar: menubarPane, dock: dockPane, layout: layoutPane,
                                                mouse: mousePane, night: nightPane, notifications: notificationsPane })[root.pane]
                        }
                    }
                }
            }
        }
    }

    // --- building blocks ---

    // Shared with the panes in popups/settings/ (widgets/Settings*.qml).
    component Group: SettingsGroup {}
    component Row_: SettingsRow {}
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
    component Divider: SettingsDivider {}

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
                    note: "Apps follow it too (KDE, GTK, browsers). Auto is light from 7:00 to 19:00."
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
                    note: "How much of the blurred background shows through the dock and menus (the menu bar has its own under Menu Bar)."
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
                Divider {}
                SwitchRow {
                    label: "Real glass (arbor)"
                    note: RealGlass.supported
                        ? "arbor draws the dock, menus and tooltips as real liquid glass: what's behind bends at their edges, like macOS 26."
                        : "Needs the arbor compositor with liquid glass; elsewhere the shell's own glass look is used."
                    key: "appearance.realGlass"
                    enabled: !Settings.appearance.reduceTransparency
                }
                Divider {}
                SliderRow {
                    label: "Glass strength"
                    note: "How strongly real glass bends, blurs and lights what's behind it."
                    key: "appearance.realGlassStrength"
                    from: 0; to: 100; step: 5; scale: 100; suffix: "%"
                    enabled: RealGlass.supported && Settings.appearance.realGlass !== false && !Settings.appearance.reduceTransparency
                }
            }
            Group {
                ChoiceRow {
                    label: "Font"
                    note: "Automatic uses Apple's SF Pro when it is installed, otherwise Inter (the closest free look-alike, built in). Now: " + Theme.fontFamily + "."
                    key: "appearance.font"
                    options: [{ value: "auto", label: "Automatic" }, { value: "sf", label: "SF Pro" },
                              { value: "inter", label: "Inter" }, { value: "noto", label: "Noto Sans" }]
                }
                Divider {}
                ChoiceRow {
                    label: "Pointer"
                    note: "Adwaita: a clean black arrow (the default). macOS-style: a black arrow with a white outline, sized like a Mac's. Breeze: KDE's pointer."
                    key: "appearance.cursor"
                    options: [{ value: "adwaita", label: "Adwaita" }, { value: "macos", label: "macOS-style" }, { value: "breeze", label: "Breeze" }]
                }
            }
        }
    }

    Component {
        id: menubarPane
        ColumnLayout {
            spacing: 14
            Group {
                ChoiceRow {
                    label: "Menu bar style"
                    note: "Transparent: items float on the wallpaper, like macOS 26. Glass: a frosted strip (macOS's \"Show menu bar background\"). Solid: no see-through."
                    key: "menubar.style"
                    enabled: !Settings.appearance.reduceTransparency
                    options: [{ value: "transparent", label: "Transparent" }, { value: "glass", label: "Glass" }, { value: "solid", label: "Solid" }]
                }
                Divider {}
                SliderRow {
                    label: "Glass opacity"
                    note: "How strongly the glass menu bar is tinted. Lower shows more of the blurred wallpaper."
                    key: "menubar.opacity"
                    from: 32; to: 95; step: 1; scale: 100; suffix: "%"
                    enabled: Theme.menuBarStyle === "glass"
                }
                Divider {}
                SwitchRow { label: "Show the workspace map"; note: "A small map of each workspace and its windows. Click one to go there; drag a window's box onto another to move it."; key: "menubar.showWorkspaces" }
                SwitchRow { label: "Show the system monitor"; note: "treetop's CPU, memory and GPU graphs in the menu bar. Click them to open treetop."; key: "menubar.showSysMonitor" }
                Divider {}
                SwitchRow { label: "Monochrome icons"; note: "Menu bar icons in the text colour, like macOS's symbols. Apps' full-colour tray pictures keep their colours."; key: "menubar.monochromeIcons" }
                Divider {}
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
            Label { text: "When the menu bar is full"; font.weight: Font.DemiBold }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.fgDim
                text: "On a small screen, items that don't fit next to the app's menus move into the ⌃ menu at the right of the menu bar. Switch an item off to keep it in the bar."
            }
            Group {
                Repeater {
                    model: [
                        { id: "trayicons", label: "App icons (Slack, Teams…)", def: true },
                        { id: "sysmonitor", label: "System monitor", def: true },
                        { id: "workspaces", label: "Workspace map", def: true },
                        { id: "weather", label: "Weather", def: true },
                        { id: "devapps", label: "Dev apps", def: true },
                        { id: "ai", label: "Assistant", def: true },
                        { id: "help", label: "Help", def: true },
                        { id: "media", label: "Now Playing", def: true }, { id: "clipboard", label: "Clipboard", def: true },
                        { id: "zones", label: "Window zones", def: true }, { id: "rdp", label: "Remote desktop", def: true },
                        { id: "printers", label: "Printers", def: true }, { id: "drives", label: "Drives", def: true },
                        { id: "keyboard", label: "Keyboard", def: true }, { id: "brightness", label: "Brightness", def: true },
                        { id: "bluetooth", label: "Bluetooth", def: true }, { id: "camera", label: "Camera in use", def: true },
                        { id: "recording", label: "Screen recording", def: true },
                        { id: "volume", label: "Sound", def: false }, { id: "network", label: "Network", def: false },
                        { id: "battery", label: "Battery", def: false }
                    ]
                    Row_ {
                        id: ovf
                        required property var modelData
                        label: modelData.label
                        note: modelData.id === "trayicons" ? "Moved first, starting from the left." : ""
                        Toggle {
                            readonly property var rules: Settings.menubar.overflow || {}
                            checked: rules[ovf.modelData.id] !== undefined ? !!rules[ovf.modelData.id] : ovf.modelData.def
                            onToggled: c => {
                                const r = Object.assign({}, rules);
                                if (c === ovf.modelData.def) delete r[ovf.modelData.id];
                                else r[ovf.modelData.id] = c;
                                Settings.set("menubar.overflow", r);
                            }
                        }
                    }
                }
            }
            Label { text: "Menu bar items"; font.weight: Font.DemiBold }
            Group {
                Repeater {
                    model: [
                        { id: "media", label: "Now Playing" }, { id: "zones", label: "Window zones" },
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
                    label: "Show delay"; note: "How long the pointer rests at the screen edge before the Dock comes out (macOS: 500 ms)."
                    key: "dock.showDelay"; from: 0; to: 2000; step: 50; suffix: " ms"
                    enabled: Settings.dock.autohide
                }
                SliderRow {
                    label: "Hide delay"; note: "How long the Dock stays after the pointer leaves it."
                    key: "dock.autohideDelay"; from: 0; to: 2000; step: 50; suffix: " ms"
                    enabled: Settings.dock.autohide
                }
                SliderRow {
                    label: "Animation"; note: "How long the Dock takes to slide in and out (macOS: about 300 ms)."
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
                    note: "Genie: the window bends into a funnel and pours into its place in the Dock (and back out when you restore it). Scale: it shrinks into the Dock. None: it disappears at once. Drawn by arbor; Hyprland has no minimize animation."
                    key: "dock.minimizeEffect"
                    options: [{ value: "genie", label: "Genie" }, { value: "scale", label: "Scale" }, { value: "none", label: "None" }]
                }
                Divider {}
                SwitchRow {
                    label: "Minimize windows into application icon"
                    note: "On: every minimized window goes into its app's icon. Off: windows of apps kept in the Dock still go into their icon; other apps' windows get their own tiles at the right end of the Dock."
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
        id: mousePane
        ColumnLayout {
            spacing: 14
            Group {
                Row_ {
                    label: "Pointer speed"
                    note: "How far the pointer moves for the same hand movement. Changes apply right away."
                    ValueSlider {
                        implicitWidth: 300
                        from: -100
                        to: 100
                        step: 5
                        value: Math.round(Mouse.speed * 100)
                        onMoved: v => Mouse.set("speed", v / 100)
                    }
                }
                Divider {}
                Row_ {
                    label: "Acceleration"
                    note: "On: quick movements go further than slow ones (like Plasma and macOS). Off: the same distance at any speed (some gamers prefer this)."
                    Toggle {
                        checked: Mouse.acceleration
                        onToggled: c => Mouse.set("acceleration", c)
                    }
                }
                Divider {}
                Row_ {
                    label: "Natural scrolling (touchpad)"
                    note: "On: the page follows your fingers, like a phone or macOS. Off: fingers move the scroll bar."
                    Toggle {
                        checked: Mouse.naturalScroll
                        onToggled: c => Mouse.set("naturalScroll", c)
                    }
                }
                Divider {}
                Row_ {
                    label: "Tap to click (touchpad)"
                    note: "On: a light tap clicks, a two-finger tap right-clicks, like macOS's Tap to click. Off: press the touchpad down to click."
                    Toggle {
                        checked: Mouse.tapToClick
                        onToggled: c => Mouse.set("tapToClick", c)
                    }
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
                    note: `Warmer colours in the evening: on automatically from ${Brightness.nightStartHour}:00 to ${Brightness.nightEndHour}:00. Switching it here lasts until the next scheduled change, even if the desktop restarts.`
                    Toggle {
                        checked: Brightness.nightLight
                        onToggled: c => Brightness.setNightLight(c)
                    }
                }
                Divider {}
                Row_ {
                    label: "Colour temperature"
                    ValueSlider {
                        implicitWidth: 300
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
                SwitchRow {
                    label: "Do Not Disturb"
                    note: "No banners pop up; notifications still collect in Notification Center. Middle-click the bell to switch it."
                    key: "notifications.dnd"
                }
                Divider {}
                SwitchRow {
                    label: "Let urgent notifications through"
                    note: "Urgent ones (low battery, a failed backup…) still show a banner during Do Not Disturb."
                    key: "notifications.urgentInDnd"
                }
                Divider {}
                SliderRow {
                    label: "Show banners for"
                    note: "How long a banner stays before it slides away. Hovering one keeps it; urgent ones stay until you clear them."
                    key: "notifications.timeout"; from: 2; to: 30; step: 1; suffix: " s"
                }
                Divider {}
                SwitchRow {
                    label: "Group by app"
                    note: "Notification Center stacks each app's notifications; click a stack to see them all."
                    key: "notifications.group"
                }
            }
            Group {
                Row_ {
                    label: "Notification Center"
                    note: "Click the bell in the menu bar, or use a hot corner. Click a notification to open it, ✕ clears it."
                    PushButton { text: "Open"; onClicked: Notifications.openCenter() }
                }
                Divider {}
                Row_ {
                    label: "Try it"
                    note: "Sends a notification so you can see how banners look."
                    PushButton { text: "Send a Test"; onClicked: Notifications.sendTest() }
                }
            }
            Label {
                Layout.fillWidth: true
                text: (Settings.mac ? "Banners appear at the top right, under the menu bar." : "Banners appear at the bottom right, above the panel.")
                    + " Drag a banner to the right to put it away."
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
        }
    }
}
