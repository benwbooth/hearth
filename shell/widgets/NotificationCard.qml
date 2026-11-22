import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../services"
import ".."

// One notification, macOS 26 style: a liquid-glass card with the app icon
// (or the sender's picture, with the app icon as a small badge) on the
// left, the title in bold with the time right-aligned in small grey text,
// the body below it, and the app's actions as glass pills. A ✕ appears at
// the top-left corner on hover. Used by the banners and Notification
// Center.
//
// `contentShown: false` leaves just the glass (a card peeking out from
// under the top one of a collapsed stack).
Item {
    id: card
    property var n: null
    property bool inBanner: false
    property bool contentShown: true
    // ✕ on hover (the stack's own ✕ replaces it on collapsed stacks).
    property bool closable: true
    property string closeTip: "Clear this notification"
    readonly property bool hovered: hov.hovered
    readonly property real pad: Math.round(12 * Theme.pt)
    readonly property real fullHeight: content.implicitHeight + 2 * pad
    readonly property bool urgent: !!n && n.urgency === NotificationUrgency.Critical
    property bool replying: false
    signal clicked()
    signal closeClicked()

    implicitWidth: Theme.notificationWidth
    implicitHeight: fullHeight

    onReplyingChanged: Notifications.replying += replying ? 1 : -1
    Component.onDestruction: if (replying) Notifications.replying -= 1

    HoverHandler { id: hov }

    // A card peeking out from under another hides what is above `clipTop`
    // (its own top edge would show through the translucent card on top).
    property real clipTop: 0
    Item {
        readonly property real room: 64
        x: -room
        y: Math.max(-room, card.clipTop)
        width: card.width + 2 * room
        height: card.height + room - y
        clip: card.clipTop > 0
        GlassFrame {
            id: glass
            x: parent.room
            y: -parent.y
            width: card.width
            height: card.height
            radius: Theme.notificationRadius
            tint: Theme.glassNotification
            realGlassTint: Theme.notificationRealTint
        }
    }
    // Urgent: a red hairline around the card.
    Rectangle {
        anchors.fill: parent
        visible: card.urgent && card.contentShown
        radius: Theme.notificationRadius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, 0.75)
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: card.clicked()
    }

    Item {
        id: content
        x: card.pad
        y: card.pad
        width: card.width - 2 * card.pad
        implicitHeight: col.implicitHeight
        opacity: card.contentShown ? 1 : 0
        visible: opacity > 0.01
        enabled: card.contentShown
        Behavior on opacity { NumberAnimation { duration: 160 } }
        transform: Translate { x: 0.001; y: 0.001 }

        ColumnLayout {
            id: col
            width: parent.width
            spacing: Math.round(8 * Theme.pt)

            RowLayout {
                Layout.fillWidth: true
                spacing: Math.round(10 * Theme.pt)

                // App icon, or the notification's picture with the app icon
                // as a badge (a message's sender, a screenshot).
                Item {
                    id: iconBox
                    readonly property real size: Math.round(32 * Theme.pt)
                    readonly property string picture: {
                        const im = card.n ? card.n.image || "" : "";
                        return im.startsWith("/") ? "file://" + im : im;
                    }
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: size
                    Layout.preferredHeight: size
                    Icon {
                        anchors.fill: parent
                        visible: iconBox.picture === ""
                        name: card.n ? card.n.appIcon : ""
                        fallback: "preferences-desktop-notification"
                        implicitSize: iconBox.size
                    }
                    ClippingRectangle {
                        anchors.fill: parent
                        visible: iconBox.picture !== ""
                        radius: width * 0.225
                        color: "transparent"
                        Image {
                            anchors.fill: parent
                            source: iconBox.picture
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(iconBox.size * 2, iconBox.size * 2)
                        }
                    }
                    Icon {
                        visible: iconBox.picture !== "" && !!card.n && !!card.n.appIcon
                        name: card.n ? card.n.appIcon : ""
                        implicitSize: Math.round(15 * Theme.pt)
                        x: parent.width - width + 3
                        y: parent.height - height + 3
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Math.round(1 * Theme.pt)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Math.round(6 * Theme.pt)
                        Label {
                            Layout.fillWidth: true
                            text: card.n ? (card.n.summary || Notifications.appLabel(card.n)) : ""
                            textFormat: Text.PlainText
                            font.pointSize: Theme.macPt(13)
                            font.weight: Font.DemiBold
                            font.letterSpacing: Theme.menuTracking
                        }
                        Rectangle {
                            visible: card.urgent
                            width: 6; height: 6; radius: 3
                            color: Theme.bad
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Label {
                            text: card.n ? Notifications.ago(card.n) : ""
                            color: Theme.fgSecondary
                            font.pointSize: Theme.macPt(11)
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.n ? card.n.body : ""
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        maximumLineCount: card.inBanner ? 4 : 6
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignTop
                        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.86) : Qt.rgba(0, 0, 0, 0.82)
                        linkColor: Theme.accent
                        font.pointSize: Theme.macPt(13)
                        font.letterSpacing: Theme.menuTracking
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }

            // Actions: glass pills, up to three to a row.
            GridLayout {
                id: actionGrid
                readonly property var acts: card.n ? card.n.actions.filter(a => a.identifier !== "default" && a.text) : []
                readonly property int total: acts.length + (card.n && card.n.hasInlineReply ? 1 : 0)
                visible: total > 0 && !card.replying
                Layout.fillWidth: true
                columns: Math.max(1, Math.min(3, total))
                columnSpacing: Math.round(6 * Theme.pt)
                rowSpacing: Math.round(6 * Theme.pt)
                GlassPill {
                    visible: !!card.n && card.n.hasInlineReply
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: "Reply"
                    tooltip: "Type a reply without opening the app"
                    onClicked: { card.replying = true; replyInput.forceActiveFocus(); }
                }
                Repeater {
                    model: actionGrid.acts
                    GlassPill {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: modelData.text
                        maxTextWidth: width - 2 * pad
                        onClicked: Notifications.invokeAction(card.n, modelData)
                    }
                }
            }

            // Inline reply.
            RowLayout {
                visible: card.replying
                Layout.fillWidth: true
                spacing: Math.round(6 * Theme.pt)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.round(26 * Theme.pt)
                    radius: height / 2
                    color: Theme.glassPill
                    border.width: 1
                    border.color: replyInput.activeFocus ? Theme.accent : Theme.glassPillRim
                    TextInput {
                        id: replyInput
                        x: Math.round(10 * Theme.pt)
                        width: parent.width - 2 * x
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.macPt(13)
                        renderType: Text.NativeRendering
                        clip: true
                        selectByMouse: true
                        onAccepted: send()
                        Keys.onEscapePressed: { text = ""; card.replying = false; }
                        function send() {
                            if (!text) return;
                            Notifications.reply(card.n, text);
                            text = "";
                            card.replying = false;
                        }
                        Label {
                            visible: replyInput.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            text: card.n && card.n.inlineReplyPlaceholder ? card.n.inlineReplyPlaceholder : "Reply"
                            color: Theme.fgSecondary
                            font.pointSize: Theme.macPt(13)
                        }
                    }
                }
                GlassPill {
                    text: "Send"
                    checked: replyInput.text !== ""
                    tooltip: "Send the reply (Return)"
                    onClicked: replyInput.send()
                }
            }
        }
    }

    CloseBadge {
        id: closeBadge
        x: -Math.round(width * 0.3)
        y: -Math.round(height * 0.3)
        z: 5
        shown: card.closable && card.contentShown && (card.hovered || closeBadge.containsMouse)
        tooltip: card.closeTip
        onClicked: card.closeClicked()
    }
}
