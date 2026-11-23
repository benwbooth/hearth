import QtQuick
import QtQuick.Layouts
import "../../widgets"
import "../.."

// One of rclone's questions as a friendly form row: the question in plain
// words (rclone's full help on hover), the guide's hint under it, and the
// control that fits: a switch for yes/no, a list of choices (a pop-up when
// there are many), a hidden field for passwords, a text field with
// rclone's suggestions otherwise.
//   opt: rclone's option (Name, Help, Type, Examples, Exclusive, Required,
//        IsPassword, DefaultStr, Provider); value: the current answer
//   providerValue: S3/Koofr's chosen provider (its examples only)
ColumnLayout {
    id: row
    property var opt: ({})
    property string hint: ""
    property string value: ""
    property string providerValue: ""
    property bool compact: false
    signal edited(string value)
    onValueChanged: if (field.text !== value) field.text = value
    signal submitted()
    spacing: 4

    function forProvider(p) {
        if (!p || !row.providerValue) return true;
        const neg = p.startsWith("!");
        const has = (neg ? p.slice(1) : p).split(",").indexOf(row.providerValue) >= 0;
        return neg ? !has : has;
    }
    readonly property var examples: (opt.Examples || []).filter(e => forProvider(e.Provider))
    readonly property bool isBool: opt.Type === "bool"
    readonly property bool choiceOnly: examples.length > 0 && !!opt.Exclusive && !isBool
    readonly property var helpLines: String(opt.Help || "").split("\n")
    function pretty(n) {
        n = String(n || "").replace(/^config_/, "").replace(/_/g, " ");
        return n.charAt(0).toUpperCase() + n.slice(1);
    }
    readonly property string question: {
        const h = (helpLines[0] || "").trim().replace(/[.:]$/, "");
        return h.length > 2 && h.length < 90 ? h : pretty(opt.Name);
    }
    readonly property string detail: hint !== "" ? hint
        : helpLines.slice(1).join(" ").replace(/\s+/g, " ").trim().slice(0, 240)
    function focusField() { if (field.visible) field.input.forceActiveFocus(); }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Label {
            id: qLabel
            Layout.fillWidth: true
            text: row.question
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            HoverHandler { id: qHov }
            Tooltip { anchorItem: qLabel; hovered: qHov.hovered; text: "rclone: " + (row.opt.Name || "") + "\n" + String(row.opt.Help || "").trim() }
        }
        Label {
            visible: !row.isBool
            text: row.opt.Required ? "Required" : "Optional"
            color: row.opt.Required ? Theme.accent : Theme.fgDim
            font.pointSize: Theme.smallFontSize
        }
        Toggle {
            visible: row.isBool
            checked: row.value === "true"
            onToggled: c => row.edited(c ? "true" : "false")
        }
    }
    Label {
        Layout.fillWidth: true
        visible: row.detail !== ""
        text: row.detail
        color: Theme.fgDim
        font.pointSize: Theme.smallFontSize
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }

    // A few choices: all shown.
    Repeater {
        model: row.choiceOnly && row.examples.length <= 6 ? row.examples : []
        MouseArea {
            id: ch
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: Math.max(28, chText.implicitHeight + 10)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            readonly property bool on: row.value === modelData.Value
            onClicked: row.edited(modelData.Value)
            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: ch.on ? Theme.accentDim : ch.containsMouse ? Theme.hover : "transparent"
                border.color: ch.on ? Theme.accent : Theme.border
            }
            Rectangle {
                id: dot
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                color: "transparent"
                border.width: 2
                border.color: ch.on ? Theme.accent : Theme.fgDim
                Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: Theme.accent; visible: ch.on }
            }
            Label {
                id: chText
                x: 34
                width: parent.width - 44
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                text: {
                    const h = String(ch.modelData.Help || "").split("\n")[0];
                    return h && h !== ch.modelData.Value ? h + "  (" + ch.modelData.Value + ")" : ch.modelData.Value;
                }
            }
        }
    }
    // Many choices: a pop-up with search.
    Dropdown {
        visible: row.choiceOnly && row.examples.length > 6
        Layout.fillWidth: true
        Layout.maximumWidth: 420
        options: row.examples.map(e => ({ value: e.Value, label: String(e.Help || e.Value).split("\n")[0], note: e.Help && e.Help.split("\n")[0] !== e.Value ? e.Value : "" }))
        value: row.value
        onPicked: v => row.edited(v)
    }
    // Typed answers, with rclone's suggestions next to them.
    RowLayout {
        visible: !row.isBool && !row.choiceOnly
        Layout.fillWidth: true
        spacing: 8
        TextBox {
            id: field
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            input.echoMode: row.opt.IsPassword ? TextInput.Password : TextInput.Normal
            placeholder: row.opt.IsPassword ? "hidden; stored scrambled in rclone's config"
                       : row.opt.DefaultStr ? "default: " + row.opt.DefaultStr
                       : row.opt.Required ? "" : "leave empty if not needed"
            Component.onCompleted: text = row.value
            onTextChanged: if (text !== row.value) row.edited(text)
            onAccepted: row.submitted()
        }
        Dropdown {
            visible: row.examples.length > 0
            implicitWidth: 150
            placeholder: "Suggestions"
            listWidth: 380
            options: row.examples.map(e => ({ value: e.Value, label: e.Value, note: String(e.Help || "").split("\n")[0] }))
            onPicked: v => { field.text = v; }
        }
    }
}
