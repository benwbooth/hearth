import QtQuick
import QtQuick.Shapes
import Quickshell
import ".."

// One row in a hearth menu, macOS 26 style: 24 pt rows, 13 pt text, the
// selection an accent-filled rounded rectangle (8 pt corners) inset from the
// menu's edge, a checkmark/icon column, right-aligned shortcut glyphs
// (⌃⌥⇧⌘), a chevron for submenus, disabled rows greyed out.
//
// Inside a BarPopup the selection is the popup's (`current`): shared by
// pointer and keyboard. Choosing a row blinks it once before `triggered`
// fires, like macOS.
MouseArea {
    id: root
    readonly property bool isMenuItem: true
    property string text: ""
    property string icon: ""
    property bool checked: false
    property bool checkable: false
    // A radio item (dbusmenu "radio"): a dot instead of a checkmark.
    property bool radio: false
    property string shortcut: ""
    property bool highlighted: false
    // Leave room for the checkmark/icon column (set on every row of a menu
    // where any row has one, so the text lines up). Defaults to the
    // parent's `menuGutter` when it has one.
    property bool gutter: parent && parent.menuGutter !== undefined ? parent.menuGutter : (icon !== "" || checkable)
    // Submenus (DBusMenuList): the popup opens/closes them by keyboard.
    property bool hasSubmenu: false
    property Item submenuLevel: null
    // Hovering opens the submenu at once (DBusMenuList delays it itself).
    property bool hoverOpensSubmenu: true
    signal openSubmenu()
    signal closeSubmenu()
    signal triggered()

    // The popup that hosts this row (selection, keyboard) and the menu
    // level (container) the row belongs to.
    readonly property var host: { const w = root.QsWindow.window; return w && w.current !== undefined ? w : null; }
    property Item level: null
    Component.onCompleted: {
        let p = root.parent;
        while (p && p.menuLevel !== true) p = p.parent;
        level = p;
    }
    readonly property bool isCurrent: host ? host.current === root : containsMouse
    // A sibling row of this level is selected (then an open submenu's row
    // no longer shows as selected).
    readonly property bool siblingCurrent: host && host.current && host.current !== root && host.current.level === root.level
    property bool blinkOff: false
    readonly property bool lit: enabled && !blinkOff
        && (pressed || isCurrent || (highlighted && !siblingCurrent))

    function hoverSelect() {
        if (host) host.current = root;
        if (hasSubmenu) openSubmenu();
    }
    // Choose this row: blink the selection once, then fire.
    function activate() {
        if (!enabled || blink.running) return;
        if (hasSubmenu) { hoverSelect(); return; }
        blink.restart();
    }
    SequentialAnimation {
        id: blink
        PropertyAction { target: root; property: "blinkOff"; value: true }
        PauseAnimation { duration: 55 }
        PropertyAction { target: root; property: "blinkOff"; value: false }
        PauseAnimation { duration: 55 }
        ScriptAction { script: root.triggered() }
    }

    // macOS shortcut glyphs: "Ctrl+Shift+S" -> "⌃⇧S", in macOS's
    // modifier order (Super is ⌘).
    function macShortcut(s) {
        if (!s) return "";
        const parts = s.split("+").map(x => x.trim()).filter(x => x !== "");
        if (s.endsWith("++")) parts.push("+");
        const mods = { ctrl: "⌃", control: "⌃", alt: "⌥", option: "⌥", shift: "⇧", super: "⌘", meta: "⌘", cmd: "⌘", win: "⌘", logo: "⌘" };
        const order = "⌃⌥⇧⌘";
        const keys = { return: "↩", enter: "↩", backspace: "⌫", delete: "⌦", del: "⌦", escape: "⎋", esc: "⎋", tab: "⇥",
                       left: "←", right: "→", up: "↑", down: "↓", pgup: "⇞", pageup: "⇞", pgdown: "⇟", pagedown: "⇟",
                       home: "↖", end: "↘", space: "Space", print: "PrtSc" };
        let m = [], k = [];
        for (const p of parts) {
            const l = p.toLowerCase();
            if (mods[l]) m.push(mods[l]);
            else k.push(keys[l] || (p.length === 1 ? p.toUpperCase() : p));
        }
        m = [...new Set(m)].sort((a, b) => order.indexOf(a) - order.indexOf(b));
        return m.join("") + k.join(" ");
    }
    readonly property string shortcutText: hasSubmenu ? "" : macShortcut(shortcut)

    width: parent ? parent.width : implicitWidth
    implicitWidth: (gutter ? Theme.menuGutter : Theme.menuTextInset) + label.implicitWidth
                   + (shortcutText !== "" ? shortcutLabel.implicitWidth + Math.round(28 * Theme.pt) : 0)
                   + (hasSubmenu ? Math.round(26 * Theme.pt) : 0) + Theme.menuTextInset
    implicitHeight: visible ? Theme.menuRowHeight : 0
    hoverEnabled: true
    onClicked: root.activate()
    onContainsMouseChanged: {
        if (containsMouse) { if (host) host.current = root; if (hasSubmenu && hoverOpensSubmenu) openSubmenu(); }
        else if (host && host.current === root && !hasSubmenu) host.current = null;
    }

    // Selection: accent fill, appears at once, fades out quickly.
    Rectangle {
        anchors.fill: parent
        radius: Theme.menuSelectionRadius
        color: Theme.accent
        opacity: root.lit ? 1 : 0
        Behavior on opacity { enabled: !root.lit && !root.blinkOff; NumberAnimation { duration: 70 } }
    }

    readonly property color textColor: !root.enabled ? Theme.fgDisabled : root.lit ? Theme.accentText : Theme.fg

    // Checkmark / icon column.
    Item {
        x: Math.round(5 * Theme.pt)
        width: Theme.menuGutter - x
        height: parent.height
        Label {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -2
            visible: root.checkable && root.checked
            text: root.radio ? "●" : "✓"
            color: root.textColor
            font.pointSize: root.radio ? Theme.macPt(7) : Theme.menuFontSize
            font.weight: Font.DemiBold
        }
        Icon {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -2
            implicitSize: 16
            name: root.icon
            visible: root.icon !== "" && !(root.checkable && root.checked)
            opacity: root.enabled ? 1 : 0.35
        }
    }

    Label {
        id: label
        x: root.gutter ? Theme.menuGutter : Theme.menuTextInset
        width: Math.min(implicitWidth, root.width - x - Theme.menuTextInset
                        - (shortcutLabel.visible ? shortcutLabel.implicitWidth + 16 : 0) - (root.hasSubmenu ? 20 : 0))
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: root.textColor
        font.pointSize: Theme.menuFontSize
        font.letterSpacing: Theme.menuTracking
    }
    Label {
        id: shortcutLabel
        anchors.right: parent.right
        anchors.rightMargin: Theme.menuTextInset
        anchors.verticalCenter: parent.verticalCenter
        visible: root.shortcutText !== ""
        text: root.shortcutText
        color: !root.enabled ? Theme.fgDisabled : root.lit ? Theme.accentText : Theme.fgSecondary
        font.pointSize: Theme.menuFontSize
        font.letterSpacing: 0.6
    }
    // Submenu chevron (SF Symbol chevron.right, ~9 pt).
    Shape {
        visible: root.hasSubmenu
        anchors.right: parent.right
        anchors.rightMargin: Theme.menuTextInset
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 11
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.textColor
            strokeWidth: 1.6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 0.8; startY: 0.8
            PathLine { x: 5.2; y: 5.5 }
            PathLine { x: 0.8; y: 10.2 }
        }
    }
}
