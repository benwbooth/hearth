import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../widgets"
import "../../services"
import "../.."

// Settings > Menu Bar: the bar's look, then every item on its right side
// (services/BarItems.qml), like macOS's Menu Bar and Control Center
// settings: drag the ≡ handle to reorder, choose where each shows, and open
// an item (›) for its options. The bar itself takes Super-drag and a right
// click for the same (bar/MenuBar.qml).
ColumnLayout {
    id: pane
    spacing: 14

    function setMb(key, v) { Settings.set("menubar." + key, v); }
    readonly property var mb: Settings.menubar

    // ---- look ----
    SettingsGroup {
        SettingsRow {
            label: "Menu bar style"
            note: "Transparent: items float on the wallpaper, like macOS 26. Glass: a frosted strip (macOS's \"Show menu bar background\"). Solid: no see-through."
            enabled: !Settings.appearance.reduceTransparency
            Segmented {
                options: [{ value: "transparent", label: "Transparent" }, { value: "glass", label: "Glass" }, { value: "solid", label: "Solid" }]
                value: pane.mb.style
                onPicked: v => pane.setMb("style", v)
            }
        }
        SettingsDivider {}
        SettingsRow {
            label: "Glass opacity"
            note: "How strongly the glass menu bar is tinted. Lower shows more of the blurred wallpaper."
            enabled: Theme.menuBarStyle === "glass"
            ValueSlider {
                implicitWidth: 300
                from: 32; to: 95; step: 1; suffix: "%"
                value: pane.mb.opacity * 100
                onMoved: v => pane.setMb("opacity", v / 100)
            }
        }
        SettingsDivider {}
        SwitchRow { label: "Monochrome icons"; note: "Menu bar icons in the text colour, like macOS's symbols. Apps' full-colour tray pictures keep their colours."; key: "monochromeIcons" }
        SettingsDivider {}
        SwitchRow { label: "Automatically hide and show the menu bar"; note: "Hidden until you move the pointer to the top edge."; key: "autohide" }
        SettingsDivider {}
        SwitchRow { label: "Show the app name"; note: "The bold name of the app you are using, next to the logo."; key: "showAppName" }
        SettingsDivider {}
        SwitchRow { label: "Icons beside menu names"; note: "An app's icons next to File, Edit, View and its other menus in the bar. The items inside the menus keep their icons either way."; key: "menuTitleIcons" }
        SettingsDivider {}
        SettingsRow {
            label: "Menu logo"
            note: "The button at the far left that opens the system menu."
            Segmented {
                options: [{ value: "nixos", label: "NixOS" }, { value: "penguin", label: "Penguin" }, { value: "none", label: "None" }]
                value: pane.mb.logo
                onPicked: v => pane.setMb("logo", v)
            }
        }
    }

    // ---- items ----
    RowLayout {
        Layout.fillWidth: true
        Label { text: "Menu bar items"; font.weight: Font.DemiBold; Layout.fillWidth: true }
        PushButton {
            text: BarItems.editing ? "Done Editing" : "Edit in the Menu Bar"
            tooltip: "Drag items in the menu bar itself to rearrange them, or below it to hide them"
            onClicked: BarItems.editing = !BarItems.editing
        }
        PushButton {
            text: "Reset"
            tooltip: "Every item back where it started, shown, with its default options"
            onClicked: BarItems.resetAll()
        }
    }
    Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        color: Theme.fgDim
        text: "Left to right as in the menu bar. Drag ≡ to move an item. Menu Bar: always there (when the bar is too full, items that may move go into the ⌃ menu at its right). ⌃ Only: just in the ⌃ menu. Hidden: nowhere. Click › for an item's options. In the menu bar, Super-drag an item to move it, drag it below the bar to hide it, or right-click it."
    }

    SettingsGroup {
        id: listGroup
        Column {
            id: list
            width: parent.width

            // Dragging a row by its handle: where it would go.
            property string dragId: ""
            property real dragY: 0
            readonly property int dropIndex: {
                if (!dragId) return -1;
                const rows = [];
                for (let i = 0; i < rep.count; i++) { const r = rep.itemAt(i); if (r) rows.push(r); }
                let k = 0;
                for (const r of rows) {
                    if (r.entryId === dragId) continue;
                    if (dragY > r.y + r.height / 2) k++;
                }
                return k;
            }
            readonly property real dropMarkY: {
                if (!dragId) return 0;
                let k = 0, y = 0;
                for (let i = 0; i < rep.count; i++) {
                    const r = rep.itemAt(i);
                    if (!r || r.entryId === dragId) continue;
                    if (k === dropIndex) return r.y;
                    k++;
                    y = r.y + r.height;
                }
                return y;
            }

            Repeater {
                id: rep
                model: BarItems.list
                ItemRow {}
            }
            Rectangle {
                visible: list.dragId !== ""
                y: list.dropMarkY - 1
                width: list.width
                height: 2
                radius: 1
                color: Theme.accent
                z: 5
            }
        }
    }

    // ---- building blocks ----
    component SwitchRow: SettingsRow {
        id: sw
        property string key
        Toggle {
            checked: !!pane.mb[sw.key]
            onToggled: c => pane.setMb(sw.key, c)
        }
    }

    // One item: handle, icon, name and note, where it shows, › options.
    component ItemRow: Item {
        id: row
        required property var modelData
        required property int index
        readonly property string entryId: modelData.id
        readonly property var cat: BarItems.byId[entryId] || {}
        readonly property string where: BarItems.show(entryId)
        property bool expanded: false
        readonly property bool hasOptions: !cat.fixed
        readonly property bool dragging: list.dragId === entryId
        readonly property bool focused: BarItems.focusId === entryId
        width: list.width
        implicitHeight: head.height + (expanded ? opts.implicitHeight + 8 : 0)
        height: implicitHeight
        z: dragging ? 10 : 0
        transform: Translate { y: row.dragging ? list.dragY - row.grabY - row.y : 0 }
        property real grabY: 0
        clip: true

        // Settings opened from an item's right-click menu: that item, open.
        Component.onCompleted: if (focused) focusSoon.start()
        onFocusedChanged: if (focused) focusSoon.start()
        Timer {
            id: focusSoon
            interval: 120
            onTriggered: {
                row.expanded = true;
                let f = row.parent;
                while (f && f.contentY === undefined) f = f.parent;
                if (f) {
                    const p = row.mapToItem(f.contentItem, 0, 0);
                    f.contentY = Math.max(0, Math.min(p.y - 80, f.contentHeight - f.height));
                }
                flash.start();
                BarItems.focusId = "";
            }
        }

        Rectangle {
            id: hl
            anchors.fill: parent
            anchors.leftMargin: -10
            anchors.rightMargin: -10
            radius: Theme.radius
            color: row.dragging ? Theme.bgRaised : Theme.accent
            opacity: row.dragging ? 1 : 0
            SequentialAnimation {
                id: flash
                NumberAnimation { target: hl; property: "opacity"; to: 0.25; duration: 200 }
                PauseAnimation { duration: 700 }
                NumberAnimation { target: hl; property: "opacity"; to: 0; duration: 500 }
            }
        }
        Rectangle {
            visible: row.index > 0
            width: parent.width
            height: 1
            color: Theme.border
            opacity: 0.6
        }

        Item {
            id: head
            width: parent.width
            height: Math.max(46, texts.implicitHeight + 14)

            // ≡ drag handle.
            MouseArea {
                id: handle
                width: 22
                height: parent.height
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                hoverEnabled: true
                preventStealing: true
                onPressed: mouse => {
                    const p = mapToItem(list, mouse.x, mouse.y);
                    row.grabY = p.y - row.y;
                    list.dragY = p.y;
                    list.dragId = row.entryId;
                }
                onPositionChanged: mouse => { if (pressed) list.dragY = mapToItem(list, mouse.x, mouse.y).y; }
                onReleased: {
                    const id = list.dragId, to = list.dropIndex;
                    list.dragId = "";
                    if (id && to >= 0) BarItems.move(id, to);
                }
                onCanceled: list.dragId = ""
                Label {
                    anchors.centerIn: parent
                    text: "≡"
                    color: handle.containsMouse ? Theme.fg : Theme.fgDim
                    font.pointSize: Theme.fontSize + 3
                }
                Tooltip { anchorItem: handle; text: "Drag to move this item left or right in the menu bar"; hovered: handle.containsMouse && !handle.pressed }
            }
            Icon {
                id: icon
                x: 28
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 20
                name: row.cat.icon || ""
                fallback: "application-x-executable"
                opacity: row.where === "hidden" ? 0.45 : 1
            }
            Column {
                id: texts
                x: 58
                anchors.verticalCenter: parent.verticalCenter
                width: place.x - x - 12
                Label {
                    text: (row.cat.group === "treetop" ? "treetop: " : "") + (row.cat.label || row.entryId)
                    width: parent.width
                    color: row.where === "hidden" ? Theme.fgDim : Theme.fg
                }
                Label {
                    text: (row.cat.note || "") + (row.cat.when ? " Shows only when " + row.cat.when + "." : "")
                    width: parent.width
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    maximumLineCount: row.expanded ? 6 : 2
                }
            }
            Segmented {
                id: place
                visible: !row.cat.fixed
                anchors.right: more.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                options: row.cat.dropdown
                    ? [{ value: "bar", label: "Menu Bar" }, { value: "overflow", label: "⌃ Only" }, { value: "hidden", label: "Hidden" }]
                    : [{ value: "bar", label: "Menu Bar" }, { value: "hidden", label: "Hidden" }]
                value: row.where
                onPicked: v => BarItems.setShow(row.entryId, v)
            }
            Label {
                visible: !!row.cat.fixed
                anchors.right: more.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Always there"
                color: Theme.fgDim
            }
            MouseArea {
                id: more
                anchors.right: parent.right
                width: 26
                height: parent.height
                hoverEnabled: true
                enabled: row.hasOptions
                onClicked: row.expanded = !row.expanded
                Label {
                    anchors.centerIn: parent
                    visible: row.hasOptions
                    text: "›"
                    rotation: row.expanded ? 90 : 0
                    color: more.containsMouse ? Theme.fg : Theme.fgDim
                    font.pointSize: Theme.fontSize + 4
                    Behavior on rotation { NumberAnimation { duration: 120 } }
                }
                Tooltip { anchorItem: more; text: row.expanded ? "Hide options" : "Options"; hovered: more.containsMouse }
            }
        }

        // Options.
        Column {
            id: opts
            visible: row.expanded
            y: head.height
            x: 58
            width: parent.width - x - 30

            OptRow {
                visible: !!row.cat.dropdown
                label: "Can move into ⌃ when the menu bar is full"
                note: row.entryId === "trayicons" ? "App icons go first, starting from the left." : "Off: it always stays in the bar, and other items make room."
                Toggle {
                    checked: BarItems.canMove(row.entryId)
                    onToggled: c => BarItems.setCanMove(row.entryId, c)
                }
            }
            OptRow {
                visible: BarItems.opt(row.entryId, "style") !== undefined
                label: "Show as"
                note: "Graph: the value with a minute of history. Number: just the value, narrower."
                Segmented {
                    options: [{ value: "graph", label: "Graph" }, { value: "number", label: "Number" }]
                    value: BarItems.opt(row.entryId, "style")
                    onPicked: v => BarItems.setOpt(row.entryId, "style", v)
                }
            }
            OptRow {
                visible: row.entryId === "workspaces"
                label: "Size"
                note: "How tall each workspace's box is in the menu bar."
                Segmented {
                    options: [{ value: "small", label: "Small" }, { value: "medium", label: "Medium" }, { value: "full", label: "Full height" }]
                    value: BarItems.opt("workspaces", "size") || "full"
                    onPicked: v => BarItems.setOpt("workspaces", "size", v)
                }
            }
            // The clock's options (most are older menubar.* settings).
            Column {
                visible: row.entryId === "clock"
                width: parent.width
                readonly property bool custom: String(BarItems.opt("clock", "format") || "").trim() !== ""
                OptRow {
                    label: "24-hour time"
                    note: "13:00 instead of 1:00 PM."
                    enabled: !parent.custom
                    Toggle { checked: !!pane.mb.clock24h; onToggled: c => pane.setMb("clock24h", c) }
                }
                OptRow {
                    label: "Show the day of the week"
                    enabled: !parent.custom
                    Toggle { checked: !!pane.mb.showWeekday; onToggled: c => pane.setMb("showWeekday", c) }
                }
                OptRow {
                    label: "Show the date"
                    enabled: !parent.custom
                    Toggle { checked: !!pane.mb.showDate; onToggled: c => pane.setMb("showDate", c) }
                }
                OptRow {
                    label: "Date style"
                    note: "Short: Fri Nov 20. Long: Friday, November 20. Numeric: your region's short date. ISO: 2026-11-20."
                    enabled: !parent.custom && !!pane.mb.showDate
                    Segmented {
                        options: [{ value: "short", label: "Short" }, { value: "long", label: "Long" }, { value: "numeric", label: "Numeric" }, { value: "iso", label: "ISO" }]
                        value: BarItems.opt("clock", "dateStyle") || "short"
                        onPicked: v => BarItems.setOpt("clock", "dateStyle", v)
                    }
                }
                OptRow {
                    label: "Show seconds"
                    enabled: !parent.custom
                    Toggle { checked: !!pane.mb.showSeconds; onToggled: c => pane.setMb("showSeconds", c) }
                }
                OptRow {
                    label: "Custom format"
                    note: "Write your own instead of the switches above, e.g. ddd d MMM  HH:mm. Letters: d day, ddd Fri, dddd Friday, M/MM/MMM/MMMM month, yy/yyyy year, H/HH 24-hour, h 12-hour, mm minutes, ss seconds, AP AM/PM, 'text' as is. Empty: use the switches."
                    tip: "Now: " + Qt.formatDateTime(new Date(), fmt.text || "ddd MMM d  HH:mm")
                    TextBox {
                        id: fmt
                        implicitWidth: 200
                        placeholder: "ddd MMM d  HH:mm"
                        text: BarItems.opt("clock", "format") || ""
                        onAccepted: BarItems.setOpt("clock", "format", text.trim())
                        input.onActiveFocusChanged: if (!input.activeFocus && text.trim() !== (BarItems.opt("clock", "format") || "")) BarItems.setOpt("clock", "format", text.trim())
                    }
                }
                OptRow {
                    visible: parent.custom
                    label: "Preview"
                    Label { text: Qt.formatDateTime(new Date(), String(BarItems.opt("clock", "format") || "")) }
                }
                OptRow {
                    label: "Show your calendar from Almanac"
                    note: "Click the clock to see today's and tomorrow's events from Almanac, with dots under busy days. Click an event to open it in Almanac."
                    Toggle { checked: !!pane.mb.showCalendar; onToggled: c => pane.setMb("showCalendar", c) }
                }
                OptRow {
                    label: "Show the next event"
                    note: "An hour before your next event, its name and how soon it starts appear next to the clock (\"Standup in 10 min\")."
                    Toggle { checked: !!pane.mb.showNextEvent; onToggled: c => pane.setMb("showNextEvent", c) }
                }
            }
        }
    }
    component OptRow: SettingsRow {}
}
