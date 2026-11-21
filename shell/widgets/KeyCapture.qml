import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"
import ".."

// "Press the new keys" field for the shortcut editor. Click it, press the
// key combination, and it emits captured("Mod+Shift+T"). Esc cancels.
// While it listens, the compositor's own shortcuts are paused for this
// window (keyboard-shortcuts-inhibit), so combinations like Super+Q reach
// it instead of closing the window.
MouseArea {
    id: root
    property string keys: ""            // arbor syntax, shown pretty
    property string emptyText: "Not set"
    property bool listening: false
    signal captured(string combo)
    implicitWidth: Math.max(150, lbl.implicitWidth + 24)
    implicitHeight: 28
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    opacity: enabled ? 1 : 0.4
    onClicked: start()
    function start() { listening = true; catcher.forceActiveFocus(); }
    function stop() { listening = false; }

    ShortcutInhibitor {
        window: root.QsWindow.window
        enabled: root.listening
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.listening ? Theme.accentDim : root.containsMouse ? Theme.hover : Theme.bgRaised
        border.color: root.listening ? Theme.accent : Theme.border
    }
    Label {
        id: lbl
        anchors.centerIn: parent
        text: root.listening ? "Press the new keys…" : root.keys ? Binds.pretty(root.keys) : root.emptyText
        color: root.listening || root.keys ? Theme.fg : Theme.fgDim
        font.weight: root.keys && !root.listening ? Font.DemiBold : Font.Normal
    }
    Tooltip {
        anchorItem: root
        text: root.listening ? "Press a key together with Super, Ctrl, Alt or Shift. Esc cancels." : "Click, then press the keys you want for this."
        hovered: root.containsMouse
    }
    Item {
        id: catcher
        focus: root.listening
        onActiveFocusChanged: if (!activeFocus) root.stop()
        Keys.onPressed: ev => {
            if (!root.listening) return;
            ev.accepted = true;
            if (ev.key === Qt.Key_Escape && !(ev.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))) {
                root.stop();
                return;
            }
            const c = Binds.comboFromEvent(ev);
            if (!c) return;          // only modifiers so far
            root.stop();
            root.captured(c);
        }
    }
}
