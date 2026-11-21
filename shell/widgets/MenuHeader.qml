import QtQuick
import ".."

// A section title inside a menu (macOS: small, bold, secondary colour),
// e.g. "Position on Screen" in the Dock menu.
Label {
    width: parent ? parent.width : implicitWidth
    leftPadding: Theme.menuTextInset
    rightPadding: Theme.menuTextInset
    height: Math.round(22 * Theme.pt)
    color: Theme.fgSecondary
    font.pointSize: Theme.menuSmallFontSize
    font.weight: Font.Bold
}
