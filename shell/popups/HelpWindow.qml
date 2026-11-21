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
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
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
                text: "Minimize: the yellow button or Super+Page Down; the window waits in the Dock (click it to bring it back). Full screen: Super+F. See every window at once: Super+W or swipe up with three fingers."
            }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: welcomePage
        ColumnLayout {
            spacing: 14
            readonly property var steps: [
                { title: "Welcome to hearth", text: "This short tour shows where things are. It takes a minute. You can open it again any time from Help (the ? at the top right) → Getting Started.", icon: "help-about" },
                { title: "The menu bar", text: "Along the top. On the left: the logo menu (About This Computer, System Settings, sleep, restart, shut down), then the app you are using and its menus. On the right: status icons (sound, network, AI models…), Spotlight's magnifier, Control Center, the microphone and the clock: click any of them for more.", icon: "preferences-desktop" },
                { title: "The Dock", text: "Along the bottom; it slides in when you push the pointer against the bottom edge. Click an app to open it. A dot under an icon means it is running. Right-click an app for its options (Keep in Dock, Quit…); drag icons to rearrange them, or drag one off the Dock to remove it.", icon: "preferences-system-windows" },
                { title: "Opening apps and finding things", text: "Press Super+Space (or click the magnifier) for Spotlight: type an app's name and press Return. It also finds documents, folders and pictures, opens settings, does sums and converts units.", icon: "search" },
                { title: "Asking by voice", text: "Press Super+Alt+Space (or click the microphone) and just say it: “open Kog”, “set the volume to 50”, “find the PDF I edited yesterday”. It stops listening when you stop talking. Everything runs on this computer.", icon: "audio-input-microphone" },
                { title: "Windows: floating and docked", text: Compositor.isArbor
                    ? "Drag a window by its title bar. Drop it on the edge of another window to dock it beside that one (they share the space and never overlap); drop it anywhere else to let it float. Super+D docks or undocks the window you're in; Super+Q closes it; Super+F makes it full screen."
                    : "Drag a window by its title bar; hold Shift while dragging to snap it into place. Super+Arrow keys move it.", icon: "transform-move" },
                { title: "Seeing all your windows", text: Compositor.isArbor
                    ? "Super+W shows every window and workspace (the overview); click one to go there. Super+Z zooms out to see how your docked windows fit together, Super+X zooms back in and Super+A shows them all. Super+Tab or Alt+Tab switches between apps."
                    : "Super+W shows every window at once; Alt+Tab switches between apps.", icon: "view-grid" },
                { title: "Settings and Help", text: "Everything can be changed in System Settings (logo menu): dark or light, the Dock, Spotlight, AI models, the voice assistant and more. Super+/ lists every keyboard shortcut. Lost? Click the ? in the menu bar and type what you want to do.", icon: "configure" }
            ]
            readonly property var s: steps[Math.min(root.welcomeStep, steps.length - 1)]
            Icon { implicitSize: 64; name: parent.s.icon }
            Title { text: parent.s.title }
            Para { text: parent.s.text; color: Theme.fg; font.pointSize: Theme.fontSize + 1 }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Row {
                    spacing: 6
                    Repeater {
                        model: parent.parent.parent.steps.length
                        Rectangle {
                            required property int index
                            width: 8
                            height: 8
                            radius: 4
                            color: index === root.welcomeStep ? Theme.accent : Theme.border
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                BarButton {
                    implicitHeight: 34
                    text: "Back"
                    visible: root.welcomeStep > 0
                    tooltip: "Previous page"
                    onClicked: root.welcomeStep--
                }
                BarButton {
                    implicitHeight: 34
                    text: root.welcomeStep < 5 ? "Next" : "Done"
                    tooltip: root.welcomeStep < 5 ? "Next page" : "Close the tour"
                    onClicked: {
                        if (root.welcomeStep < 5) root.welcomeStep++;
                        else root.open = false;
                    }
                }
            }
        }
    }
}
