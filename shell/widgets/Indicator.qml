import QtQuick
import ".."

// A tray indicator: a BarButton that opens `popupContent` on left click.
// Right/middle clicks and the wheel are passed on via signals.
BarButton {
    id: root
    property Component popupContent: null
    property alias popup: pop
    property bool shown: true
    signal rightClicked()
    signal middleClicked()
    signal scrolled(int delta)

    visible: shown
    active: pop.open

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton && root.popupContent) pop.toggle();
        else if (mouse.button === Qt.RightButton) root.rightClicked();
        else if (mouse.button === Qt.MiddleButton) root.middleClicked();
    }
    onWheel: w => root.scrolled(w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x)

    BarPopup {
        id: pop
        anchorItem: root
        Loader {
            active: pop.open
            sourceComponent: root.popupContent
        }
    }
}
