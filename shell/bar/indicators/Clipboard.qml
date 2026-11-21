import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../widgets"
import "../../services"
import "../.."

// Clipboard history (like KDE's Klipper), a popover from the menu bar:
// search, the recent items (text and picture thumbnails, pinned ones
// first), click or Return to copy one again. Each item can be pinned
// (never expires), edited before copying, opened (links and file paths) or
// deleted; the history can be cleared. services/Clipboard.qml keeps it.
//
// Keys: type to search, ↑/↓ choose, Return copies, Delete removes,
// Ctrl+P pins, Ctrl+E edits, Ctrl+O opens a link, Esc closes.
// Super+V or `hearth-ipc call clipboard toggle` opens it.
Indicator {
    id: root
    icon: "klipper-symbolic"
    iconFallback: "edit-paste"
    tooltip: "Clipboard history"
    tooltipSub: "What you copied lately: click an item to copy it again (Super+V)"
    shown: Clipboard.enabled

    Connections {
        target: Clipboard
        function onToggleRequested() { if (root.ipcHere) root.popup.toggle(); }
        function onOpenRequested() { if (root.ipcHere) root.popup.open = true; }
        function onCloseRequested() { root.popup.close(); }
    }
    // Opened from the keyboard (Super+V) it has to take the keyboard at
    // once to be typed into. Not on Hyprland: an exclusive layer ends its
    // focus grab there (BarPopup), and it hands OnDemand layers the focus.
    Binding {
        target: root.popup
        property: "keyboardFocus"
        value: Compositor.isHyprland ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
    }
    Connections {
        target: root.popup
        function onOpenChanged() { if (root.popup.open) Clipboard.refresh(); }
    }

    popupContent: FocusScope {
        id: view
        implicitWidth: 400
        implicitHeight: col.implicitHeight

        // "list" | "edit" | "confirm"
        property string mode: "list"
        property string query: ""
        property int sel: 0
        property var editing: null
        property bool editLoading: false

        readonly property var shown: {
            const q = view.query.trim().toLowerCase();
            if (!q) return Clipboard.items;
            const words = q.split(/\s+/);
            return Clipboard.items.filter(it => {
                const s = (it.text + (it.pinned ? " pinned" : "")).toLowerCase();
                return words.every(w => s.includes(w));
            });
        }
        readonly property var current: sel >= 0 && sel < shown.length ? shown[sel] : null
        readonly property bool hasHistory: Clipboard.items.some(it => !it.pinned)
        onQueryChanged: sel = 0
        onShownChanged: if (sel >= shown.length) sel = Math.max(0, shown.length - 1)

        Component.onCompleted: focusSoon.start()
        Timer { id: focusSoon; interval: 160; onTriggered: search.forceActiveFocus() }

        function close() { root.popup.close(); }
        function copy(it) {
            if (!it) return;
            Clipboard.copy(it);
            close();
        }
        function remove(it) { if (it) Clipboard.remove(it); }
        function pin(it) { if (it) Clipboard.pin(it); }
        function open(it) { if (it && (it.url || it.path)) { Clipboard.open(it); close(); } }
        function edit(it) {
            if (!it || it.image) return;
            view.editing = it;
            view.editLoading = true;
            editor.text = "";
            view.mode = "edit";
            Clipboard.fullText(it, t => {
                view.editLoading = false;
                editor.text = t !== null ? t : it.text;
                editor.cursorPosition = editor.length;
                editor.forceActiveFocus();
            });
        }
        function finishEdit(copyIt) {
            if (copyIt) { Clipboard.copyText(editor.text); close(); }
            view.mode = "list";
            view.editing = null;
            search.forceActiveFocus();
        }
        function askClear() { view.mode = "confirm"; confirmKeys.forceActiveFocus(); }
        function finishClear(yes) {
            if (yes) Clipboard.clear();
            view.mode = "list";
            search.forceActiveFocus();
        }
        function move(d) {
            if (!shown.length) return;
            sel = Math.max(0, Math.min(shown.length - 1, sel + d));
            list.positionViewAtIndex(sel, ListView.Contain);
        }

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 8

            // Title and Clear.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Label {
                    Layout.fillWidth: true
                    text: "Clipboard"
                    font.weight: Font.DemiBold
                }
                SmallButton {
                    icon: "edit-clear-history"
                    tip: "Clear history… (pinned items stay)"
                    visible: view.mode === "list" && view.hasHistory
                    onClicked: view.askClear()
                }
                SmallButton {
                    icon: "configure"
                    tip: "Clipboard settings: history size, pictures, passwords, apps to ignore"
                    onClicked: { view.close(); Settings.openRequested("clipboard"); }
                }
            }

            // Search.
            Rectangle {
                Layout.fillWidth: true
                visible: view.mode === "list"
                implicitHeight: 32
                radius: Theme.radius
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
                border.color: search.activeFocus ? Theme.accent : "transparent"
                Icon { x: 9; anchors.verticalCenter: parent.verticalCenter; implicitSize: 16; name: "search" }
                TextInput {
                    id: search
                    x: 32
                    width: parent.width - 40
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.fontSize
                    renderType: Text.NativeRendering
                    selectByMouse: true
                    clip: true
                    focus: true
                    onTextChanged: view.query = text
                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Down) view.move(1);
                        else if (event.key === Qt.Key_Up) view.move(-1);
                        else if (event.key === Qt.Key_PageDown) view.move(6);
                        else if (event.key === Qt.Key_PageUp) view.move(-6);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) view.copy(view.current);
                        else if (event.key === Qt.Key_Escape) view.close();
                        // Delete removes the item unless it would edit the search.
                        else if (event.key === Qt.Key_Delete && search.cursorPosition === search.length && !search.selectedText) view.remove(view.current);
                        else if (ctrl && event.key === Qt.Key_P) view.pin(view.current);
                        else if (ctrl && event.key === Qt.Key_E) view.edit(view.current);
                        else if (ctrl && event.key === Qt.Key_O) view.open(view.current);
                        else return;
                        event.accepted = true;
                    }
                    Label {
                        visible: search.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search what you copied"
                        color: Theme.fgDim
                    }
                }
            }

            // The items.
            ListView {
                id: list
                Layout.fillWidth: true
                visible: view.mode === "list" && view.shown.length > 0
                implicitHeight: Math.min(contentHeight, 440)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: view.shown
                spacing: 1
                // "Pinned" / "Recent" headers once something is pinned.
                section.property: Clipboard.items.some(it => it.pinned) ? "pinned" : ""
                section.criteria: ViewSection.FullString
                section.delegate: MenuHeader {
                    required property string section
                    width: ListView.view.width
                    text: section === "true" ? "Pinned" : "Recent"
                    leftPadding: 8
                }
                readonly property var host: view
                delegate: ClipRow { view: list.host }
            }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.topMargin: 6
                Layout.bottomMargin: 6
                visible: view.mode === "list" && view.shown.length === 0
                text: !Clipboard.enabled ? "Clipboard history is turned off (Settings > Clipboard)."
                    : view.query.trim() !== "" ? "Nothing you copied matches “" + view.query.trim() + "”."
                    : !Clipboard.loaded ? "Loading…"
                    : "Nothing copied yet. Text and pictures you copy show up here."
                color: Theme.fgDim
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: Clipboard.error !== ""
                text: "Not recording: " + Clipboard.error
                color: Theme.bad
                font.pointSize: Theme.smallFontSize
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }

            // Edit before copying.
            ColumnLayout {
                Layout.fillWidth: true
                visible: view.mode === "edit"
                spacing: 8
                Label {
                    Layout.leftMargin: 4
                    text: view.editLoading ? "Loading…" : "Edit, then copy the changed text (Ctrl+Return)"
                    color: Theme.fgDim
                    font.pointSize: Theme.smallFontSize
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 220
                    radius: Theme.radius
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
                    border.color: editor.activeFocus ? Theme.accent : Theme.border
                    Flickable {
                        id: editFlick
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        contentWidth: width
                        contentHeight: editor.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        function ensureVisible(r) {
                            if (contentY >= r.y) contentY = r.y;
                            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
                        }
                        TextEdit {
                            id: editor
                            width: editFlick.width
                            wrapMode: TextEdit.Wrap
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pointSize: Theme.fontSize
                            renderType: Text.NativeRendering
                            selectByMouse: true
                            onCursorRectangleChanged: editFlick.ensureVisible(cursorRectangle)
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) view.finishEdit(false);
                                else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) view.finishEdit(true);
                                else return;
                                event.accepted = true;
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PushButton { text: "Cancel"; tooltip: "Keep the clipboard as it is (Esc)"; onClicked: view.finishEdit(false) }
                    PushButton { text: "Copy"; primary: true; tooltip: "Copy the edited text (Ctrl+Return)"; enabled: !view.editLoading; onClicked: view.finishEdit(true) }
                }
            }

            // Confirm clearing.
            ColumnLayout {
                Layout.fillWidth: true
                visible: view.mode === "confirm"
                spacing: 10
                Item {
                    id: confirmKeys
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) view.finishClear(false);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) view.finishClear(true);
                        else return;
                        event.accepted = true;
                    }
                }
                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: "Clear the clipboard history? Everything you copied is forgotten; pinned items stay."
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    PushButton { text: "Cancel"; tooltip: "Keep the history (Esc)"; onClicked: view.finishClear(false) }
                    PushButton { text: "Clear History"; destructive: true; tooltip: "Forget everything but the pinned items (Return)"; onClicked: view.finishClear(true) }
                }
            }

            // Key hints.
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                visible: view.mode === "list" && view.shown.length > 0
                text: "Enter copies   ⌦ Delete   ⌃P Pin   ⌃E Edit" + (view.current && (view.current.url || view.current.path) ? "   ⌃O Open" : "")
                color: Theme.fgSecondary
                font.pointSize: Theme.menuSmallFontSize
            }
        }
    }

    // One history item.
    component ClipRow: MouseArea {
        id: row
        property var view
        required property var modelData
        required property int index
        readonly property bool lit: row.view.sel === index
        width: ListView.view.width
        implicitHeight: modelData.image ? 64 : Math.max(Theme.menuRowHeight + 4, rowText.implicitHeight + 10)
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onContainsMouseChanged: if (containsMouse) row.view.sel = index
        onClicked: mouse => { if (mouse.button === Qt.MiddleButton) row.view.remove(modelData); else row.view.copy(modelData); }
        HoverHandler { id: rowHover }
        Tooltip {
            anchorItem: row
            text: row.modelData.image ? "" : (row.modelData.text.length > 120 ? row.modelData.text.slice(0, 400) : "")
            hovered: rowHover.hovered && !row.pressed
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.menuSelectionRadius
            color: Theme.accent
            visible: row.lit
        }
        Icon {
            id: pinMark
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 14
            name: "pin"
            visible: row.modelData.pinned
        }
        Rectangle {
            id: thumbBox
            x: row.modelData.pinned ? 28 : 8
            anchors.verticalCenter: parent.verticalCenter
            visible: row.modelData.image
            width: visible ? Math.round(Math.max(24, Math.min(120, 52 * row.modelData.w / Math.max(1, row.modelData.h)))) : 0
            height: 52
            color: "transparent"
            border.color: Theme.border
            Image {
                id: thumb
                anchors.fill: parent
                anchors.margins: 1
                source: row.modelData.thumb ? "file://" + row.modelData.thumb : ""
                sourceSize.height: 104
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
            }
        }
        Label {
            id: rowText
            x: thumbBox.visible ? thumbBox.x + thumbBox.width + 10 : (row.modelData.pinned ? 28 : 10)
            width: parent.width - x - (actions.visible ? actions.width + 6 : 8)
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.text
            textFormat: Text.PlainText
            color: row.lit ? Theme.accentText : row.modelData.image ? Theme.fgSecondary : Theme.fg
            font.pointSize: Theme.menuFontSize
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        ClipActions {
            id: actions
            view: row.view
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            visible: row.lit
            item: row.modelData
        }
    }

    component ClipActions: RowLayout {
        id: acts
        property var item
        property var view
        spacing: 0
        SmallButton {
            visible: !!(acts.item && (acts.item.url || acts.item.path))
            icon: acts.item && acts.item.url ? "globe" : "document-open-folder"
            tip: acts.item && acts.item.url ? "Open the link (Ctrl+O)" : "Open the file or folder (Ctrl+O)"
            onClicked: acts.view.open(acts.item)
        }
        SmallButton {
            visible: !!(acts.item && !acts.item.image)
            icon: "document-edit"
            tip: "Edit before copying (Ctrl+E)"
            onClicked: acts.view.edit(acts.item)
        }
        SmallButton {
            icon: acts.item && acts.item.pinned ? "window-unpin" : "pin"
            tip: acts.item && acts.item.pinned ? "Unpin: back into the history (Ctrl+P)" : "Pin: keep it, it never expires (Ctrl+P)"
            onClicked: acts.view.pin(acts.item)
        }
        SmallButton {
            icon: "edit-delete"
            tip: "Delete from the history (Delete)"
            onClicked: acts.view.remove(acts.item)
        }
    }

    component SmallButton: MouseArea {
        id: sb
        property string icon
        property string tip
        implicitWidth: 26
        implicitHeight: 26
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: sb.pressed ? Theme.pressed : sb.containsMouse ? Theme.hover : "transparent"
        }
        Icon { anchors.centerIn: parent; implicitSize: 16; name: sb.icon }
        Tooltip { anchorItem: sb; text: sb.tip; hovered: sb.containsMouse && !sb.pressed }
    }
}
