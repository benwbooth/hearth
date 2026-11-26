import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// The assistant asking before it runs a command or starts using the
// computer (Ai.approval): what it wants to do, Allow and Deny.
Rectangle {
    id: card
    readonly property var req: Ai.approval
    visible: !!req
    implicitHeight: visible ? col.implicitHeight + 2 * pad : 0
    readonly property int pad: Math.round(10 * Theme.pt)
    radius: Math.round(8 * Theme.pt)
    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
    border.width: 1
    border.color: Theme.warn

    ColumnLayout {
        id: col
        x: card.pad
        y: card.pad
        width: card.width - 2 * card.pad
        spacing: Math.round(6 * Theme.pt)
        RowLayout {
            spacing: 6
            Icon {
                implicitSize: 16
                name: card.req && card.req.kind === "command" ? "utilities-terminal-symbolic" : "input-mouse-symbolic"
                fallback: "dialog-question"
            }
            Label {
                Layout.fillWidth: true
                text: card.req ? card.req.title : ""
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                elide: Text.ElideNone
            }
        }
        Label {
            Layout.fillWidth: true
            visible: !!card.req
            text: card.req ? card.req.detail : ""
            font.family: card.req && card.req.kind === "command" ? "monospace" : Theme.fontFamily
            color: card.req && card.req.kind === "command" ? Theme.fg : Theme.fgSecondary
            wrapMode: Text.WrapAnywhere
            elide: Text.ElideNone
            maximumLineCount: 8
            textFormat: Text.PlainText
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 8
            PushButton { text: "Deny"; onClicked: Ai.answerApproval(false) }
            PushButton {
                text: card.req && card.req.kind === "command" ? "Run" : "Allow"
                primary: true
                tooltip: card.req && card.req.kind === "command" ? "Run this command once" : "Let it click and type until this request is done"
                onClicked: Ai.answerApproval(true)
            }
        }
    }
}
