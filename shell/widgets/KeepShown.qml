import QtQuick

// Keeps a waiting dialog on screen (keyring, polkit, Bluetooth pairing).
// A monitor that drops out for a moment (unplugged, power-saving, a mode
// change) takes the window's surface with it, and nothing makes it again:
// the dialog would go on waiting with no window, and everything queued
// behind it (every later keyring prompt, say) with it. Once there's a
// real screen again the window is made again.
//
//   KeepShown { window: win; want: root.req !== null }
//
// It also owns the window's visibility: leave `visible` unset on the
// window.
Timer {
    id: keeper
    property var window
    property bool want: false

    interval: 1000
    repeat: true
    running: want

    Component.onCompleted: if (window) window.visible = Qt.binding(() => keeper.want)
    onWindowChanged: if (window) window.visible = Qt.binding(() => keeper.want)
    onTriggered: {
        const w = keeper.window;
        if (!w || !keeper.want || w.backingWindowVisible) return;
        const s = w.screen;
        if (!s || !s.name) return; // still only Qt's placeholder screen
        w.visible = false;
        Qt.callLater(() => { w.visible = Qt.binding(() => keeper.want); });
    }
}
