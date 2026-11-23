import QtQuick
import QtQuick.Layouts
import Quickshell
import "../widgets"
import "../services"
import ".."

// hearth Help: Keyboard Shortcuts (searchable, grouped), Trackpad Gestures,
// How windows work, and Getting Started (also shown once at first login).
// Opened from the menu bar's Help button, the Help search, or
// `hearth-ipc call help shortcuts|gestures|windows|welcome` (Super+/).
Scope {
    id: root
    property bool open: false
    property string page: "shortcuts"
    property string query: ""
    property int welcomeStep: 0

    Connections {
        target: Help
        function onGuideRequested(page, query) {
            root.page = page;
            root.query = query;
            if (page === "welcome") root.welcomeStep = 0;
            root.open = true;
        }
    }

    // First run: the welcome tour, once.
    Timer {
        interval: 2500
        // arbor gets its own tour once (the Hyprland one was different).
        readonly property string key: Compositor.isArbor ? "welcomeShownArbor" : "welcomeShown"
        running: Settings.loaded && !Settings.get(key)
        onTriggered: {
            Settings.set(key, true);
            Help.guideRequested("welcome", "");
        }
    }

    LazyLoader {
        active: root.open

        FloatingWindow {
            id: win
            title: "hearth Help"
            visible: true
            implicitWidth: 820
            implicitHeight: 600
            minimumSize: Qt.size(640, 440)
            color: Theme.bg
            onVisibleChanged: if (!visible) root.open = false

            Item {
                anchors.fill: parent
                transform: Translate { x: 0.001; y: 0.001 }

                Rectangle {
                    id: side
                    width: 210
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
                                { id: "welcome", label: "Getting Started", icon: "help-about" },
                                { id: "shortcuts", label: "Keyboard Shortcuts", icon: "preferences-desktop-keyboard-shortcut" },
                                { id: "gestures", label: "Trackpad Gestures", icon: "input-touchpad" },
                                { id: "windows", label: "How windows work", icon: "preferences-system-windows" }
                            ]
                            MouseArea {
                                id: nav
                                required property var modelData
                                width: parent.width
                                height: 34
                                hoverEnabled: true
                                onClicked: { root.page = modelData.id; root.welcomeStep = 0; }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radius
                                    color: root.page === nav.modelData.id ? Theme.accent : nav.containsMouse ? Theme.hover : "transparent"
                                }
                                Row {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    Icon { implicitSize: 20; name: nav.modelData.icon; anchors.verticalCenter: parent.verticalCenter }
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: nav.modelData.label
                                        color: root.page === nav.modelData.id ? Theme.accentText : Theme.fg
                                    }
                                }
                            }
                        }
                    }
                }

                Loader {
                    anchors.left: side.right
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 24
                    sourceComponent: ({ shortcuts: shortcutsPage, gestures: gesturesPage, windows: windowsPage, welcome: welcomePage })[root.page]
                }
            }
        }
    }

    component Title: Label {
        font.pointSize: Theme.fontSize + 6
        font.weight: Font.Bold
    }
    component Para: Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        color: Theme.fgDim
        lineHeight: 1.15
    }
    component KeyRow: Item {
        id: kr
        property string title
        property string keys
        property bool hit: false
        width: parent ? parent.width : 400
        height: 30
        Rectangle { anchors.fill: parent; radius: Theme.radius; color: kr.hit ? Theme.accentDim : "transparent" }
        Label { x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.55; text: kr.title }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: keyLabel.implicitWidth + 14
            height: 22
            radius: 5
            color: Theme.bgRaised
            border.color: Theme.border
            Label { id: keyLabel; anchors.centerIn: parent; text: kr.keys; font.family: Theme.fontFamily; font.pointSize: Theme.smallFontSize + 0.5 }
        }
    }
    // A search field with native text.
    component SearchField: Rectangle {
        id: sf
        property alias text: input.text
        property string placeholder: "Search"
        implicitHeight: 34
        radius: Theme.radius
        color: Theme.bgAlt
        border.color: input.activeFocus ? Theme.accent : Theme.border
        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; implicitSize: 16; name: "search" }
        TextInput {
            id: input
            x: 34
            width: parent.width - 44
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pointSize: Theme.fontSize + 1
            renderType: Text.NativeRendering
            selectByMouse: true
            clip: true
            focus: true
            Label {
                visible: input.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: sf.placeholder
                color: Theme.fgDim
                font.pointSize: Theme.fontSize + 1
            }
        }
    }

    Component {
        id: shortcutsPage
        ColumnLayout {
            spacing: 12
            Title { text: "Keyboard Shortcuts" }
            Para { text: Compositor.isArbor ? "Read from your arbor configuration. Super is the Windows (⊞) key." : "Super is the Windows (⊞) key. Press Super+/ any time to open this list." }
            SearchField {
                id: search
                Layout.fillWidth: true
                placeholder: "Type what you want to do, e.g. \"screenshot\" or \"close\""
                text: root.query
                onTextChanged: root.query = text
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            ScrollAssist { flickable: helpFlick }
            Flickable {
                id: helpFlick
                anchors.fill: parent
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: list
                    width: parent.width
                    spacing: 2
                    readonly property var groups: ["Apps & Launcher", "Windows", "Workspaces & Overview", "Menus", "Screenshots", "Accessibility", "System"]
                    readonly property var shown: {
                        const q = root.query.trim().toLowerCase();
                        return Help.shortcuts.filter(s => !q || (s.title + " " + s.keys + " " + s.group).toLowerCase().includes(q));
                    }
                    Repeater {
                        model: list.groups
                        Column {
                            id: grp
                            required property string modelData
                            readonly property var rows: list.shown.filter(s => s.group === grp.modelData)
                            width: list.width
                            visible: rows.length > 0
                            spacing: 2
                            Label { text: grp.modelData; font.weight: Font.DemiBold; height: 30; color: Theme.fg }
                            Repeater {
                                model: grp.rows
                                KeyRow {
                                    required property var modelData
                                    title: modelData.title
                                    keys: modelData.keys
                                }
                            }
                        }
                    }
                    Para {
                        visible: list.shown.length === 0
                        width: list.width
                        text: "Nothing matches \"" + root.query + "\". Try a simpler word, like \"window\", \"close\" or \"workspace\" — or clear the search to see everything."
                    }
                }
            }
            }
        }
    }

    Component {
        id: gesturesPage
        ColumnLayout {
            spacing: 12
            Title { text: "Trackpad Gestures" }
            Para { text: "Use several fingers on the trackpad. Swipes follow your fingers; let go to finish." }
            Column {
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: Help.gestures
                    KeyRow {
                        required property var modelData
                        title: modelData.title
                        keys: modelData.keys
                        hit: root.query !== "" && modelData.title === root.query
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // Small drawings of a screen with windows.
    component Screen_: Rectangle {
        default property alias content: inner.data
        property string caption
        width: 220
        height: 150
        radius: 8
        color: Theme.bgAlt
        border.color: Theme.border
        Rectangle { width: parent.width; height: 10; radius: 8; color: Theme.bgRaised }
        Item { id: inner; anchors.fill: parent; anchors.margins: 8; anchors.topMargin: 16 }
        Label {
            anchors.top: parent.bottom
            anchors.topMargin: 6
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: parent.caption
            color: Theme.fgDim
            font.pointSize: Theme.smallFontSize
        }
    }
    component Win_: Rectangle {
        radius: 4
        color: Theme.accentDim
        border.color: Theme.accent
        Rectangle { width: parent.width; height: 6; radius: 4; color: Theme.accent }
    }

    Component {
        id: windowsPage
        ColumnLayout {
            spacing: 14
            Title { text: "How windows work" }
            Para {
                text: Compositor.isArbor
                    ? "Windows open floating, like sheets of paper on a desk: drag them anywhere by the title bar. To dock a window, drag it to the edge of another window (or of the screen): it snaps in beside it and the two share the space. Docked windows never overlap. Drag the gap between two docked windows to resize both."
                    : "Windows can float freely or be tiled. Drag a window by its title bar to move it; hold Shift while dragging to snap it into a zone. Super+T switches a window between floating and tiled."
            }
            Row {
                spacing: 24
                Layout.topMargin: 4
                Screen_ {
                    caption: "Floating: anywhere, may overlap"
                    Win_ { x: 10; y: 8; width: 110; height: 70 }
                    Win_ { x: 70; y: 40; width: 110; height: 70 }
                }
                Screen_ {
                    caption: "Docked: side by side"
                    Win_ { x: 0; y: 0; width: 98; height: 118 }
                    Win_ { x: 104; y: 0; width: 98; height: 56 }
                    Win_ { x: 104; y: 62; width: 98; height: 56 }
                }
                Screen_ {
                    caption: "Drag to an edge to dock"
                    Win_ { x: 0; y: 0; width: 98; height: 118 }
                    Rectangle { x: 104; y: 0; width: 98; height: 118; radius: 4; color: "transparent"; border.color: Theme.accent; border.width: 2; opacity: 0.6 }
                    Win_ { x: 120; y: 30; width: 70; height: 50; opacity: 0.8 }
                }
            }
            Para {
                Layout.topMargin: 26
                text: "Minimize: the down-arrow button at the right of the title bar or Super+Page Down; the window pours into the Dock (the Genie effect; Settings > Dock can make it shrink instead, or not animate) and waits there (click it to bring it back). Full screen: Super+F. See every window at once: Super+W or swipe up with three fingers."
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: welcomePage
        // The tour: one centred card (picture, title, text, key chips, then
        // Back/Next right under them), so the buttons stay with the page
        // however large the window is. Left/Right arrow keys turn pages.
        Item {
            id: tour
            focus: true
            readonly property var steps: Compositor.isArbor ? arborSteps : hyprSteps
            readonly property int last: steps.length - 1
            readonly property var s: steps[Math.max(0, Math.min(root.welcomeStep, last))]
            Keys.onRightPressed: if (root.welcomeStep < last) root.welcomeStep++
            Keys.onLeftPressed: if (root.welcomeStep > 0) root.welcomeStep--
            Keys.onReturnPressed: next()
            function next() {
                if (root.welcomeStep < last) root.welcomeStep++;
                else root.open = false;
            }

            readonly property var arborSteps: [
                { art: "hello", title: "Welcome to arbor",
                  text: "arbor is your window manager: windows dock beside each other like a tree of panes, a camera zooms out to show them all, and zones snap windows into a layout you choose. hearth is the menu bar, the Dock and Search on top of it. This tour takes a minute; open it again from the ? in the menu bar → Getting Started.",
                  keys: [] },
                { art: "menubar", title: "The menu bar",
                  text: "Left: the logo menu (settings, sleep, restart, shut down), then the app you're in and its menus. Right: status icons, Search, Control Center, the assistant and the clock. Click any of them.",
                  keys: [] },
                { art: "dock", title: "The Dock",
                  text: "Push the pointer against the bottom edge and it slides in. Click an app to open it; a dot means it's running. Right-click for Keep in Dock or Quit; drag icons to reorder, or off the Dock to remove them.",
                  keys: [] },
                { art: "search", title: "Open anything",
                  text: "Search opens apps, documents, folders and settings, and does sums and unit conversions. Or press the voice key and just say it: “open Kog”, “volume to 50”. Everything runs on this computer.",
                  keys: [["Super", "Space"], ["Super", "Alt", "Space"]] },
                { art: "docking", title: "Docking windows",
                  text: "Drag a window by its title bar and drop it on the edge of another one: it docks beside it and they share the space without overlapping. Drop it anywhere else and it floats. Super+D docks or undocks the window you're in.",
                  keys: [["Super", "D"], ["Super", "Q"], ["Super", "F"]] },
                { art: "zones", title: "Zones",
                  text: "Pick a zone layout from the zones icon in the menu bar. Hold Shift while dragging a window and drop it into a zone, or press Super+Ctrl+1…9 to send the window you're in to that zone. Super+Ctrl+Page Down switches to the next layout.",
                  keys: [["Shift", "drag"], ["Super", "Ctrl", "1…9"], ["Super", "Ctrl", "PgDn"]] },
                { art: "camera", title: "Zoom out, see everything",
                  text: "Super+Z zooms the camera out so you can see how your docked windows fit together, Super+X zooms back in, Super+A frames them all. Super+W opens the overview of every window and workspace; click one to go there.",
                  keys: [["Super", "Z"], ["Super", "X"], ["Super", "A"], ["Super", "W"]] },
                { art: "settings", title: "Settings and help",
                  text: "System Settings (logo menu) changes the look, the Dock, zones, Search, the voice assistant and more. Super+/ lists every shortcut, and the ? in the menu bar searches for what you want to do.",
                  keys: [["Super", "/"]] }
            ]
            readonly property var hyprSteps: [
                { art: "hello", title: "Welcome to hearth", text: "This short tour shows where things are. Open it again any time from the ? in the menu bar → Getting Started.", keys: [] },
                arborSteps[1], arborSteps[2], arborSteps[3],
                { art: "docking", title: "Moving windows", text: "Drag a window by its title bar; hold Shift while dragging to snap it into place. Super+Arrow keys move it.", keys: [["Super", "←→↑↓"]] },
                { art: "camera", title: "Seeing all your windows", text: "Super+W shows every window at once; Alt+Tab switches between apps.", keys: [["Super", "W"], ["Alt", "Tab"]] },
                arborSteps[7]
            ]

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, 600)
                spacing: 16

                TourArt {
                    Layout.alignment: Qt.AlignHCenter
                    kind: tour.s.art
                }
                Title {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: tour.s.title
                }
                Para {
                    horizontalAlignment: Text.AlignHCenter
                    text: tour.s.text
                    color: Theme.fg
                    font.pointSize: Theme.fontSize + 1
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    visible: tour.s.keys.length > 0
                    spacing: 14
                    Repeater {
                        model: tour.s.keys
                        Row {
                            required property var modelData
                            spacing: 3
                            Repeater {
                                model: parent.modelData
                                Rectangle {
                                    required property string modelData
                                    width: kc.implicitWidth + 14
                                    height: 24
                                    radius: 5
                                    color: Theme.bgRaised
                                    border.color: Theme.border
                                    Label { id: kc; anchors.centerIn: parent; text: parent.modelData }
                                }
                            }
                        }
                    }
                }
                Item { implicitHeight: 6 }
                RowLayout {
                    Layout.fillWidth: true
                    Row {
                        spacing: 6
                        Repeater {
                            model: tour.steps.length
                            MouseArea {
                                required property int index
                                width: 14
                                height: 14
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.welcomeStep = index
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: parent.index === root.welcomeStep ? Theme.accent : Theme.border
                                }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    PushButton {
                        text: "Back"
                        visible: root.welcomeStep > 0
                        tooltip: "Previous page (←)"
                        onClicked: root.welcomeStep--
                    }
                    PushButton {
                        primary: true
                        text: root.welcomeStep < tour.last ? "Next" : "Done"
                        tooltip: root.welcomeStep < tour.last ? "Next page (→)" : "Close the tour"
                        onClicked: tour.next()
                    }
                }
            }
        }
    }

    // A small drawing of the screen for each tour page: the part the page
    // talks about in the accent colour.
    component TourArt: Rectangle {
        id: art
        property string kind
        readonly property color dim: Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
        readonly property color win: Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14)
        implicitWidth: 360
        implicitHeight: 200
        radius: 10
        color: Theme.bgAlt
        border.color: Theme.border
        clip: true

        // Menu bar and Dock, on every page.
        Rectangle {
            x: 1; y: 1; width: parent.width - 2; height: 12
            radius: 9
            color: art.kind === "menubar" ? Theme.accent : art.dim
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 22
            width: 150; height: 16; radius: 6
            color: art.kind === "dock" ? Theme.accent : art.dim
            Row {
                anchors.centerIn: parent
                spacing: 5
                Repeater {
                    model: 8
                    Rectangle { width: 11; height: 11; radius: 3; color: art.kind === "dock" ? Qt.rgba(1, 1, 1, 0.7) : art.win }
                }
            }
        }

        // Docked panes (hello, docking, settings).
        Item {
            visible: ["hello", "docking", "menubar", "dock", "settings"].indexOf(art.kind) >= 0
            x: 14; y: 22; width: parent.width - 28; height: parent.height - 52
            Rectangle { x: 0; y: 0; width: parent.width * 0.5 - 3; height: parent.height; radius: 5; color: art.win }
            Rectangle { x: parent.width * 0.5 + 3; y: 0; width: parent.width * 0.5 - 3; height: parent.height * 0.5 - 3; radius: 5; color: art.win }
            Rectangle {
                x: parent.width * 0.5 + 3; y: parent.height * 0.5 + 3; width: parent.width * 0.5 - 3; height: parent.height * 0.5 - 3; radius: 5
                color: art.kind === "docking" ? Theme.accentDim : art.win
                border.color: art.kind === "docking" ? Theme.accent : "transparent"
                border.width: 2
            }
        }
        // The window being dragged onto the dock spot.
        Rectangle {
            visible: art.kind === "docking"
            x: 70; y: 95; width: 120; height: 60; radius: 5
            color: Theme.bgRaised
            border.color: Theme.accent
            opacity: 0.95
            Rectangle { width: parent.width; height: 10; radius: 5; color: Theme.accent }
            Label { anchors.centerIn: parent; text: "→"; font.pointSize: Theme.fontSize + 8; color: Theme.accent }
        }

        // Spotlight field + microphone.
        Rectangle {
            visible: art.kind === "search"
            anchors.centerIn: parent
            width: 240; height: 36; radius: 9
            color: Theme.bgRaised
            border.color: Theme.accent
            border.width: 2
            Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; implicitSize: 18; name: "search" }
            Label { x: 36; anchors.verticalCenter: parent.verticalCenter; text: "open Kog"; color: Theme.fgDim }
            Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; implicitSize: 18; name: "audio-input-microphone" }
        }

        // Zones: three columns, the middle one taking a window.
        Row {
            visible: art.kind === "zones"
            x: 14; y: 22; spacing: 6
            Repeater {
                model: [0.28, 0.44, 0.28]
                Rectangle {
                    required property real modelData
                    required property int index
                    width: (art.width - 28 - 12) * modelData
                    height: art.height - 52
                    radius: 5
                    color: index === 1 ? Theme.accentDim : "transparent"
                    border.color: index === 1 ? Theme.accent : art.win
                    border.width: 2
                    Label { anchors.centerIn: parent; text: String(parent.index + 1); font.pointSize: Theme.fontSize + 8; color: parent.index === 1 ? Theme.accent : Theme.fgDim }
                }
            }
        }

        // Camera: groups of panes, zoomed out, with the view frame.
        Item {
            visible: art.kind === "camera"
            anchors.fill: parent
            Repeater {
                model: [[30, 30], [140, 40], [250, 26], [80, 110], [200, 112]]
                Item {
                    required property var modelData
                    x: modelData[0]; y: modelData[1]; width: 80; height: 50
                    Rectangle { width: 38; height: 50; radius: 3; color: art.win }
                    Rectangle { x: 42; width: 38; height: 23; radius: 3; color: art.win }
                    Rectangle { x: 42; y: 27; width: 38; height: 23; radius: 3; color: art.win }
                }
            }
            Rectangle {
                x: 130; y: 32; width: 104; height: 66; radius: 6
                color: "transparent"
                border.color: Theme.accent
                border.width: 2
            }
        }

        // Big icon over the panes for the first and last pages.
        Rectangle {
            visible: art.kind === "hello" || art.kind === "settings"
            anchors.centerIn: parent
            width: 76; height: 76; radius: 18
            color: Theme.bgRaised
            border.color: Theme.border
            Icon { anchors.centerIn: parent; implicitSize: 52; name: art.kind === "hello" ? "preferences-system-windows" : "configure" }
        }
    }
}
