import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../widgets"
import "../services"
import ".."

// The sheets apps open through the desktop portal (services/Portal.qml,
// helpers/hearth-portal), in the same style as the polkit and keyring
// sheets:
//   access      "Allow <app> to use the camera?" (also location, running in
//               the background, screen sharing permission...)
//   account     share your name and picture with an app
//   appchooser  Open With: pick the app for a file or link
//   launcher    add a web app / app shortcut to Launchpad
//   print       printer, copies, pages, two-sided
// Esc or Cancel answers "no"; nothing is shared until you press the blue
// button.
Scope {
    id: root
    readonly property var req: Portal.request
    readonly property string kind: req ? req.type : ""
    readonly property string appName: req && req.app ? req.app : "An app"

    // Per-request state, reset when a new request shows.
    property var picks: ({})          // access: choice id -> value
    property string chosen: ""        // appchooser
    property bool shareImage: true    // account
    property string printer: ""
    property int copies: 1
    property string pageMode: "all"
    property string duplex: "none"
    property string orientation: "portrait"

    function reset() {
        if (!req) return;
        const p = {};
        for (const c of (req.choices || [])) if (c.initial !== undefined) p[c.id] = c.initial;
        picks = kind === "access" ? p : {};
        chosen = "";
        if (kind === "appchooser") {
            const ids = (req.choices || []).map(c => c.id);
            chosen = ids.indexOf(req.lastChoice) >= 0 ? req.lastChoice : (ids[0] || "");
        }
        shareImage = true;
        printer = req.printer || "";
        copies = Math.max(1, req.copies || 1);
        pageMode = "all";
        duplex = "none";
        orientation = "portrait";
        nameBox.text = req.name || "";
        pagesBox.text = "";
    }

    function headline() {
        switch (kind) {
        case "access": return req.title || ("Allow " + appName + "?");
        case "account": return "Share your name with " + appName + "?";
        case "appchooser": return req.target ? "Open “" + req.target + "” With…" : "Choose an App";
        case "launcher": return req.webapp ? "Add Web App?" : "Add App Shortcut?";
        case "print": return req.title ? "Print “" + req.title + "”" : "Print";
        }
        return "";
    }
    function body() {
        switch (kind) {
        case "access": return [req.subtitle, req.body].filter(s => !!s).join("\n\n");
        case "account": return (req.reason ? req.reason + "\n\n" : "")
            + appName + " is asking for the name and picture of your account on this computer. Nothing else is shared.";
        case "appchooser": return (req.typeName ? "Pick the app for this " + req.typeName.toLowerCase() + "." : "Pick the app to open it with.")
            + (req.app ? " " + req.app + " asked." : "");
        case "launcher": return appName + " wants to add " + (req.webapp ? "this website as an app" : "a shortcut")
            + ". It shows up in Launchpad and Spotlight, and you can pin it to the Dock.";
        case "print": return req.preparing ? appName + " will print with these settings." : "";
        }
        return "";
    }
    function iconName() {
        if (!req) return "";
        if (kind === "access") return req.icon || req.appIcon || "dialog-question";
        if (kind === "launcher") return req.icon || "applications-internet";
        if (kind === "print") return "document-print";
        if (kind === "appchooser") return "document-open";
        return req.appIcon || "user-identity";
    }
    function canAccept() {
        if (kind === "appchooser") return chosen !== "";
        if (kind === "launcher") return !req.editableName || nameBox.text.trim() !== "";
        if (kind === "print") return printer !== "" && (pageMode === "all" || /^\s*\d+(\s*-\s*\d+)?(\s*,\s*\d+(\s*-\s*\d+)?)*\s*$/.test(pagesBox.text));
        return true;
    }
    function accept() {
        if (!req || !canAccept()) return;
        const a = { response: 0 };
        if (kind === "access") a.choices = picks;
        else if (kind === "account") a.shareImage = shareImage;
        else if (kind === "appchooser") a.choice = chosen;
        else if (kind === "launcher") a.name = nameBox.text.trim();
        else if (kind === "print") {
            a.printer = printer;
            a.copies = copies;
            a.pages = pageMode === "range" ? pagesBox.text : "";
            a.duplex = duplex;
            a.orientation = orientation;
        }
        Portal.reply(a);
    }
    function cancel() { Portal.reply(null); }
    function acceptLabel() {
        switch (kind) {
        case "access": return req.grantLabel || "Allow";
        case "account": return "Share";
        case "appchooser": return "Open";
        case "launcher": return "Add";
        case "print": return req.acceptLabel || "Print";
        }
        return "OK";
    }
    function fileUrl(p) { return p.startsWith("/") ? "file://" + p : p; }

    PanelWindow {
        id: win
        visible: root.req !== null
        screen: Compositor.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hearth-portal"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: Qt.rgba(0, 0, 0, 0.25)

        onVisibleChanged: if (visible) { root.reset(); card.forceActiveFocus(); }
        Connections {
            target: Portal
            function onRequestChanged() {
                // An AppChooser update keeps the sheet (and the pick).
                if (win.visible && root.req && root.req.id !== shownId.value) { root.reset(); card.forceActiveFocus(); }
                shownId.value = root.req ? root.req.id : 0;
            }
        }
        QtObject { id: shownId; property var value: 0 }

        MouseArea { anchors.fill: parent; onClicked: {} } // modal

        GlassFrame {
            id: card
            width: root.kind === "appchooser" || root.kind === "print" ? 480 : 440
            height: col.implicitHeight + 48
            x: Math.round((win.width - width) / 2)
            y: Math.round(win.height * 0.24)
            radius: 22
            focus: true
            transform: Translate { x: 0.001; y: 0.001 }
            tint: Theme.glassColor(Theme.dark ? Qt.rgba(0.13, 0.135, 0.15, 1) : Qt.rgba(0.97, 0.97, 0.975, 1), 0.85)
            Keys.onEscapePressed: root.cancel()
            Keys.onReturnPressed: root.accept()
            Keys.onEnterPressed: root.accept()

            ColumnLayout {
                id: col
                x: 24
                y: 24
                width: parent.width - 48
                spacing: 10

                // Picture: the account's own for "account", else an icon.
                ClippingRectangle {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.kind === "account" && !!root.req.image
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: 32
                    color: Theme.bgRaised
                    Image {
                        anchors.fill: parent
                        source: root.req && root.req.image ? root.fileUrl(root.req.image) : ""
                        sourceSize: Qt.size(128, 128)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: root.shareImage ? 1 : 0.3
                    }
                }
                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !(root.kind === "account" && !!root.req.image)
                    implicitSize: 56
                    name: root.iconName()
                    fallback: "dialog-question"
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.req ? root.headline() : ""
                    font.weight: Font.Bold
                    font.pointSize: Theme.fontSize + 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: root.req ? root.body() : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    color: Theme.fgDim
                }

                // ---- account: what gets shared
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.kind === "account"
                    spacing: 8
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.req && root.kind === "account" ? (root.req.name && root.req.name !== root.req.user ? root.req.name + "  (" + root.req.user + ")" : root.req.user) : ""
                        font.weight: Font.Medium
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.kind === "account" && !!root.req.image
                        spacing: 10
                        Toggle { checked: root.shareImage; onToggled: c => root.shareImage = c }
                        Label { text: "Include my picture" }
                    }
                }

                // ---- access: the app's extra choices (e.g. "Remember")
                Repeater {
                    model: root.kind === "access" ? (root.req.choices || []) : []
                    RowLayout {
                        id: choiceRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Toggle {
                            visible: choiceRow.modelData.options.length === 0
                            checked: root.picks[choiceRow.modelData.id] === "true"
                            onToggled: c => { const p = Object.assign({}, root.picks); p[choiceRow.modelData.id] = c ? "true" : "false"; root.picks = p; }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: choiceRow.modelData.label
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                        }
                        Dropdown {
                            visible: choiceRow.modelData.options.length > 0
                            Layout.preferredWidth: 180
                            options: choiceRow.modelData.options
                            value: root.picks[choiceRow.modelData.id]
                            onPicked: v => { const p = Object.assign({}, root.picks); p[choiceRow.modelData.id] = v; root.picks = p; }
                        }
                    }
                }

                // ---- appchooser: the apps that can open it
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.kind === "appchooser"
                    implicitHeight: Math.min(280, Math.max(48, apps.contentHeight + 8))
                    radius: 10
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
                    Label {
                        anchors.centerIn: parent
                        visible: apps.count === 0
                        text: "No installed app can open this."
                        color: Theme.fgDim
                    }
                    ListView {
                        id: apps
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        model: root.kind === "appchooser" ? (root.req.choices || []) : []
                        delegate: MouseArea {
                            id: appRow
                            required property var modelData
                            readonly property bool on: root.chosen === modelData.id
                            width: ListView.view.width
                            height: 44
                            hoverEnabled: true
                            onClicked: root.chosen = modelData.id
                            onDoubleClicked: { root.chosen = modelData.id; root.accept(); }
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: appRow.on ? Theme.accent : appRow.containsMouse ? Theme.hover : "transparent"
                            }
                            Icon {
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 28
                                name: appRow.modelData.icon
                            }
                            Column {
                                x: 46
                                width: parent.width - 54
                                anchors.verticalCenter: parent.verticalCenter
                                Label {
                                    width: parent.width
                                    text: appRow.modelData.name
                                    color: appRow.on ? Theme.accentText : Theme.fg
                                }
                                Label {
                                    width: parent.width
                                    visible: text !== ""
                                    text: appRow.modelData.comment || ""
                                    font.pointSize: Theme.smallFontSize
                                    color: appRow.on ? Theme.accentText : Theme.fgDim
                                }
                            }
                        }
                    }
                }

                // ---- launcher: the name it gets
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.kind === "launcher"
                    spacing: 6
                    TextBox {
                        id: nameBox
                        Layout.fillWidth: true
                        enabled: !!root.req && root.req.editableName !== false
                        placeholder: "Name in Launchpad"
                        onAccepted: root.accept()
                        Keys.onEscapePressed: root.cancel()
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: root.kind === "launcher" && !!root.req.target
                        text: root.req && root.req.target ? root.req.target : ""
                        color: Theme.fgDim
                        font.pointSize: Theme.smallFontSize
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // ---- print
                GridLayout {
                    Layout.fillWidth: true
                    visible: root.kind === "print"
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 8
                    Label { text: "Printer"; color: Theme.fgDim }
                    Dropdown {
                        Layout.fillWidth: true
                        options: root.kind === "print" ? (root.req.printers || []).map(p => ({
                            value: p.value, label: p.label + (p.state === "stopped" ? " (paused)" : ""), icon: "printer" })) : []
                        value: root.printer
                        placeholder: "No printers: add one in Settings › Printers"
                        onPicked: v => root.printer = v
                    }
                    Label { text: "Copies"; color: Theme.fgDim }
                    RowLayout {
                        spacing: 6
                        PushButton { text: "−"; tooltip: "One copy fewer"; enabled: root.copies > 1; onClicked: root.copies-- }
                        Label { text: root.copies; Layout.minimumWidth: 24; horizontalAlignment: Text.AlignHCenter }
                        PushButton { text: "+"; tooltip: "One copy more"; onClicked: root.copies++ }
                    }
                    Label { text: "Pages"; color: Theme.fgDim; visible: !!(root.req && root.req.preparing) }
                    RowLayout {
                        visible: !!(root.req && root.req.preparing)
                        spacing: 8
                        Segmented {
                            options: [{ value: "all", label: "All" }, { value: "range", label: "Some" }]
                            value: root.pageMode
                            onPicked: v => { root.pageMode = v; if (v === "range") pagesBox.input.forceActiveFocus(); }
                        }
                        TextBox {
                            id: pagesBox
                            Layout.fillWidth: true
                            visible: root.pageMode === "range"
                            placeholder: "e.g. 1-3, 5"
                            onAccepted: root.accept()
                            Keys.onEscapePressed: root.cancel()
                        }
                    }
                    Label { text: "Two-sided"; color: Theme.fgDim }
                    Segmented {
                        options: [{ value: "none", label: "Off" }, { value: "long", label: "Book" }, { value: "short", label: "Flip up" }]
                        value: root.duplex
                        onPicked: v => root.duplex = v
                    }
                    Label { text: "Layout"; color: Theme.fgDim; visible: !!(root.req && root.req.preparing) }
                    Segmented {
                        visible: !!(root.req && root.req.preparing)
                        options: [{ value: "portrait", label: "Portrait" }, { value: "landscape", label: "Landscape" }]
                        value: root.orientation
                        onPicked: v => root.orientation = v
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8
                    PushButton {
                        text: "What's this?"
                        tooltip: "Help › App requests: why apps ask the desktop for these things"
                        onClicked: Help.guideRequested("requests", "")
                    }
                    Item { Layout.fillWidth: true }
                    PushButton {
                        text: root.kind === "access" && root.req.denyLabel ? root.req.denyLabel
                            : root.kind === "access" ? "Don't Allow"
                            : root.kind === "account" ? "Don't Share" : "Cancel"
                        tooltip: "Say no: the app gets nothing (Esc)"
                        onClicked: root.cancel()
                    }
                    PushButton {
                        text: root.req ? root.acceptLabel() : ""
                        primary: true
                        enabled: root.req ? root.canAccept() : false
                        tooltip: root.kind === "print" ? "Send it to the printer (Return)"
                            : root.kind === "appchooser" ? "Open it in the selected app (Return)"
                            : "Yes, go ahead (Return)"
                        onClicked: root.accept()
                    }
                }
            }
        }
    }
}
