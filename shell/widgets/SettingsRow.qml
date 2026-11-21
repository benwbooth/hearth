import QtQuick
import ".."

// A Settings row: a label, a one-line plain-language note under it, and a
// control on the right. Hovering the label shows `tip` (extra detail the
// note doesn't fit) as a tooltip.
Item {
    id: r
    property string label
    property string note: ""
    property string tip: ""
    default property alias control: holder.data
    width: parent ? parent.width : 400
    implicitHeight: Math.max(44, texts.implicitHeight + 16)
    opacity: enabled ? 1 : 0.5

    HoverHandler { id: hov }
    Tooltip {
        anchorItem: texts
        text: r.tip
        hovered: hov.hovered
    }

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
