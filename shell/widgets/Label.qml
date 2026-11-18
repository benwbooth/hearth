import QtQuick
import ".."

// Every piece of text in the shell goes through this so it renders with
// native (FreeType) text instead of Qt Quick's distance-field glyphs.
Text {
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pointSize: Theme.fontSize
    renderType: Text.NativeRendering
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
