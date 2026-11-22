import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../services"
import ".."

// A panel popup that opens next to `anchorItem`: below it when its window is
// a top bar (`edge: "top"` on the bar window), above it otherwise (bottom
// panel, dock), and closes when you click anywhere else.
//
// Put a single layout inside it; the popup sizes itself to that child's
// implicit size. MenuItems inside it form a menu: one selection shared by
// pointer and keyboard (arrows, Return/Space, Escape, type-ahead letters;
// Left/Right open/close submenus and move between menu bar menus), and
// the menu bar's press-drag-release (dragAt / releaseAt).
//
// Look and motion (README "Look"): liquid glass (GlassFrame) with a soft
// drop shadow, which needs room around the pane, so the surface is
// `shadowPad` larger on each side (only the pane takes input). It fades
// and scales in from its anchor (Theme.menuInMs), fades out
// (Theme.menuOutMs); switching between open menu bar menus is instant.
PanelWindow {
    id: popup
    required property Item anchorItem
    default property alias content: body.data
    property int padding: 12
    // No frame of its own: the content draws its own glass (cascading menus).
    property bool bare: false
    // "center": centred on the anchor; "start": left edge at the anchor's
    // (menu bar menus, which grow to the right as submenus open).
    property string align: "center"
    property bool open: false
    // A menu of the menu bar (app/system/global menus): hovering another
    // such title while it is open switches to it, Left/Right move between
    // them.
    property bool menuBarMenu: false
    // Child popups (cascading submenus) that clicks may land in.
    property var extraWindows: []
    // OnDemand: the popup takes the keyboard when clicked into (search
    // fields, passwords). Exclusive sends all typing straight to it.
    // Not Exclusive: Hyprland ends the focus grab when an exclusive layer
    // takes the keyboard, which closed menus the moment they opened.
    property int keyboardFocus: WlrKeyboardFocus.OnDemand

    // A layer-shell panel rather than an xdg popup: popups only get the
    // keyboard through an input grab, which a key bind or `hearth-ipc` can't
    // start. Anchored to the bottom edge it sits just above the bar (the
    // bar's exclusive zone pushes it up), horizontally under its button.
    readonly property var barWindow: anchorItem.QsWindow.window
    readonly property string edge: barWindow && barWindow.edge ? barWindow.edge : "bottom"
    readonly property bool fromTop: edge === "top"
    readonly property bool sideways: edge === "left" || edge === "right"
    // Extra gap from the screen edge, for bars that don't reserve space
    // (the auto-hiding dock / menu bar).
    readonly property int edgeGap: barWindow && barWindow.popupGap !== undefined ? barWindow.popupGap : 0
    // Gap between the bar and the pane.
    readonly property int gap: fromTop ? 3 : 6

    // Room for the shadow around the pane; towards a top bar only the gap
    // (the shadow falls downwards and has faded out by then).
    readonly property real shadowPad: frame.shadowPad
    // Towards a bottom/side bar the pane keeps its small gap and the
    // shadow ends where the bar's reserved space begins.
    readonly property real padL: edge === "left" ? Math.min(shadowPad, gap + edgeGap) : shadowPad
    readonly property real padR: edge === "right" ? Math.min(shadowPad, gap + edgeGap) : shadowPad
    readonly property real padT: fromTop ? gap : shadowPad
    readonly property real padB: edge === "bottom" ? Math.min(shadowPad, gap + edgeGap) : shadowPad

    screen: barWindow ? barWindow.screen : null
    anchors.top: edge !== "bottom"
    anchors.bottom: edge === "bottom"
    anchors.left: edge !== "right"
    anchors.right: edge === "right"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    margins.top: {
        if (!sideways) return edgeGap;
        void popup.open;
        if (!barWindow || !screen) return 0;
        const p = anchorItem.mapToItem(null, 0, anchorItem.height / 2);
        const h = popup.implicitHeight;
        return Math.max(0, Math.min(screen.height - h, Math.round(p.y - frame.height / 2 - padT)));
    }
    margins.bottom: Math.max(0, gap + edgeGap - padB)
    margins.right: Math.max(0, gap + edgeGap - padR)
    // Where the pane should go along the bar, kept on screen.
    readonly property real paneX: {
        void popup.open;
        if (!barWindow || !screen || sideways) return 0;
        let fx;
        if (popup.align === "start") fx = anchorItem.mapToItem(null, 0, 0).x - Math.round(5 * Theme.pt);
        else fx = anchorItem.mapToItem(null, anchorItem.width / 2, 0).x - frame.width / 2;
        return Math.round(Math.max(4, Math.min(screen.width - frame.width - 4, fx)));
    }
    margins.left: {
        if (edge === "left") return Math.max(0, gap + edgeGap - padL);
        if (!barWindow || !screen) return 0;
        return Math.max(0, Math.min(screen.width - popup.implicitWidth, paneX - padL));
    }
    // Where the surface sits on the screen (top bar popups): the bar's
    // press-drag-release maps the pointer into it.
    readonly property point screenPos: Qt.point(margins.left,
        (fromTop && barWindow && !barWindow.autohide ? barWindow.exclusiveZone : 0) + margins.top)

    // Above the click catcher below (non-Hyprland).
    WlrLayershell.layer: Compositor.isHyprland ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.namespace: "hearth-popup"
    // Mapped without keyboard interactivity, which is turned on a moment
    // later: Hyprland gives a keyboard-interactive layer the pointer as it
    // maps (an enter at the cursor's position, outside the popup), after
    // which Qt never shows hover in it until the pointer leaves again.
    WlrLayershell.keyboardFocus: open && keyboardReady ? popup.keyboardFocus : WlrKeyboardFocus.None
    property bool keyboardReady: false
    onVisibleChanged: { keyboardReady = false; if (visible) keyboardTimer.restart(); }
    Timer {
        id: keyboardTimer
        interval: 120
        onTriggered: popup.keyboardReady = popup.visible
    }
    // Stays mapped while it fades out.
    visible: open || frame.opacity > 0.001
    color: "transparent"
    implicitWidth: Math.max(8, Math.ceil(frame.implicitWidth + padL + padR))
    implicitHeight: Math.max(8, Math.ceil(frame.implicitHeight + padT + padB))
    // Only the pane takes the pointer; clicks on its shadow fall through
    // (and close it, like any click outside).
    mask: Region { item: frame }

    // Shown without the open animation: switched to from another open menu
    // bar menu (macOS swaps those instantly).
    property bool instant: false
    // Cleared again on close: the dock stays out while its menu is the
    // active popup, so a stale one kept it from ever hiding.
    onOpenChanged: {
        if (open) {
            const prev = ShellState.activePopup;
            instant = !!prev && prev !== popup && prev.open && prev.menuBarMenu && popup.menuBarMenu;
            if (instant) prev.instant = true;
            current = null;
            ShellState.activePopup = popup;
        } else {
            if (ShellState.activePopup === popup) ShellState.activePopup = null;
            current = null;
            typed = "";
        }
        // The instant swap is for this one change only: cleared right after,
        // or every later open and close of these menus skipped its fade
        // (the flag used to stick after the first menu-to-menu switch).
        if (instant) Qt.callLater(() => { popup.instant = false; });
    }
    // One popup at a time.
    Connections {
        target: ShellState
        function onActivePopupChanged() {
            if (ShellState.activePopup !== popup) popup.open = false;
        }
    }

    // Close on clicks anywhere else. The bar is part of the grab so its
    // buttons can toggle the popup closed.
    // Not while the menu bar's button is still held (press-drag-release):
    // starting the grab then takes the pointer away from the bar, which
    // has to keep tracking it until the release.
    property bool pressHeld: false
    HyprlandFocusGrab {
        active: Compositor.isHyprland && popup.visible && !popup.pressHeld
        windows: (popup.barWindow ? [popup, popup.barWindow] : [popup]).concat(popup.extraWindows)
        onCleared: popup.close()
    }

    // Elsewhere (arbor have no focus grab): a transparent surface over
    // everything but the bars, under the popup, closes it on a click.
    PanelWindow {
        visible: popup.visible && !Compositor.isHyprland
        screen: popup.screen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "hearth-popup-catcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: popup.close()
        }
    }

    // Register with the menu bar (Left/Right between its menus).
    property var registeredIn: null
    function syncMenu() {
        const want = menuBarMenu && barWindow && barWindow.registerMenu ? barWindow : null;
        if (registeredIn === want) return;
        if (registeredIn) registeredIn.unregisterMenu(popup);
        registeredIn = want;
        if (want) want.registerMenu(popup);
    }
    onBarWindowChanged: syncMenu()
    onMenuBarMenuChanged: syncMenu()
    Component.onCompleted: syncMenu()
    Component.onDestruction: if (registeredIn) registeredIn.unregisterMenu(popup)

    function toggle() { open = !open; }
    function close() { open = false; }

    // --- the menu: one selection, keyboard, type-ahead ---
    // The selected MenuItem (pointer or keyboard).
    property Item current: null
    property string typed: ""
    Timer { id: typeReset; interval: 900; onTriggered: popup.typed = "" }

    // MenuItems of one menu level, in order (not those of nested levels:
    // DBusMenuList's cascading submenus).
    function levelItems(level) {
        const out = [];
        const walk = n => {
            for (let i = 0; i < n.children.length; i++) {
                const c = n.children[i];
                if (!c.visible) continue;
                if (c.isMenuItem) { if (c.enabled) out.push(c); continue; }
                if (c.menuLevel === true) continue;
                walk(c);
            }
        };
        if (level) walk(level);
        return out;
    }
    function firstLevel(n) {
        if (levelItems(n).length) return n;
        for (let i = 0; i < n.children.length; i++) {
            const c = n.children[i];
            if (!c.visible) continue;
            const l = c.menuLevel === true ? firstLevel(c) : firstLevel(c);
            if (l) return l;
        }
        return null;
    }
    function activeLevel() { return current && current.level ? current.level : firstLevel(body); }
    function select(item) { current = item; }
    function move(delta) {
        const items = levelItems(activeLevel());
        if (!items.length) return;
        const i = items.indexOf(current);
        if (i < 0) select(delta > 0 ? items[0] : items[items.length - 1]);
        else select(items[(i + delta + items.length) % items.length]);
    }
    function enterSubmenu(item) {
        item.openSubmenu();
        enterTries = 0;
        entering = item;
        enterTimer.restart();
    }
    property Item entering: null
    property int enterTries: 0
    // The submenu's items may arrive a moment later (dbusmenu).
    Timer {
        id: enterTimer
        interval: 40
        repeat: true
        onTriggered: {
            const it = popup.entering;
            const lvl = it ? it.submenuLevel : null;
            const items = lvl ? popup.levelItems(lvl) : [];
            if (items.length) { popup.select(items[0]); stop(); }
            else if (++popup.enterTries > 15) stop();
        }
    }
    function leaveSubmenu() {
        const lvl = current ? current.level : null;
        const owner = lvl && lvl.ownerItem ? lvl.ownerItem : null;
        if (!owner) return false;
        owner.closeSubmenu();
        select(owner);
        return true;
    }
    function switchMenu(dir) {
        if (menuBarMenu && barWindow && barWindow.switchMenu) barWindow.switchMenu(popup, dir);
    }
    function activate() {
        if (!current) return;
        if (current.hasSubmenu) enterSubmenu(current);
        else current.activate();
    }
    function typeAhead(ch) {
        typed += ch.toLowerCase();
        typeReset.restart();
        const items = levelItems(activeLevel());
        const start = Math.max(0, items.indexOf(current));
        for (let k = 0; k < items.length; k++) {
            const it = items[(start + (typed.length === 1 ? k + 1 : k)) % items.length];
            if ((it.text || "").toLowerCase().replace(/^[^a-z0-9]+/, "").startsWith(typed)) { select(it); return; }
        }
    }
    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Escape:
            if (!leaveSubmenu()) close();
            break;
        case Qt.Key_Down: move(1); break;
        case Qt.Key_Up: move(-1); break;
        case Qt.Key_Home: { const l = levelItems(activeLevel()); if (l.length) select(l[0]); break; }
        case Qt.Key_End: { const l = levelItems(activeLevel()); if (l.length) select(l[l.length - 1]); break; }
        case Qt.Key_Right:
            if (current && current.hasSubmenu) enterSubmenu(current);
            else switchMenu(1);
            break;
        case Qt.Key_Left:
            if (!leaveSubmenu()) switchMenu(-1);
            break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
            activate();
            break;
        default:
            if (event.text && event.text.length === 1 && /\S/.test(event.text)) typeAhead(event.text);
            else return;
        }
        event.accepted = true;
    }

    // --- press-drag-release from the menu bar ---
    readonly property bool pointerInside: paneHover.hovered
    function containsScreenPoint(gx, gy) {
        const p = frame.mapFromItem(null, gx - screenPos.x, gy - screenPos.y);
        return p.x >= 0 && p.y >= 0 && p.x < frame.width && p.y < frame.height;
    }
    // The bar keeps the pointer while its button is held, so it feeds the
    // pointer (screen coordinates) here: the item under it is selected, and
    // releasing on one chooses it.
    function itemAt(gx, gy) {
        const all = [];
        const walk = n => {
            for (let i = 0; i < n.children.length; i++) {
                const c = n.children[i];
                if (!c.visible) continue;
                if (c.isMenuItem) { if (c.enabled) all.push(c); continue; }
                walk(c);
            }
        };
        walk(body);
        const x = gx - screenPos.x, y = gy - screenPos.y;
        for (const it of all) {
            const p = it.mapFromItem(null, x, y);
            if (p.x >= 0 && p.y >= 0 && p.x < it.width && p.y < it.height) return it;
        }
        return null;
    }
    function dragAt(gx, gy) {
        const it = itemAt(gx, gy);
        if (it) it.hoverSelect();
        else if (current && !current.hasSubmenu) current = null;
    }
    function releaseAt(gx, gy) {
        const it = itemAt(gx, gy);
        if (!it) return false;
        if (it.hasSubmenu) { it.hoverSelect(); return true; }
        select(it);
        it.activate();
        return true;
    }

    // Keys: a focused handler inside the popup (Shortcut needs an "active"
    // window, which a layer surface never is). The popup has the keyboard
    // once it is keyboard-interactive (OnDemand, see keyboardReady).
    Item {
        id: keys
        focus: popup.open
        Keys.onPressed: event => popup.handleKey(event)
    }

    Item {
        id: frame
        // Beside a screen edge the pane moves into the shadow's room.
        x: popup.sideways ? popup.padL : Math.max(0, Math.min(popup.implicitWidth - width, popup.paneX - popup.margins.left))
        y: popup.padT
        implicitWidth: body.implicitWidth + popup.padding * 2
        implicitHeight: body.implicitHeight + popup.padding * 2
        width: implicitWidth
        height: implicitHeight
        readonly property real shadowPad: popup.bare ? (Theme.glassShadows ? Math.ceil(Theme.menuShadowBlur + Theme.menuShadowY) : 2) : glassPane.shadowPad
        // Fade in and grow from the anchor; fade out on close.
        opacity: popup.open ? 1 : 0
        Behavior on opacity {
            enabled: !popup.instant
            NumberAnimation { duration: popup.open ? Theme.menuInMs : Theme.menuOutMs; easing.type: popup.open ? Easing.OutCubic : Easing.InOutQuad }
        }
        property real grow: popup.open ? 1 : 0
        Behavior on grow {
            enabled: !popup.instant && popup.open
            NumberAnimation { duration: Theme.menuInMs + 60; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        }
        transform: Scale {
            readonly property real s: 0.94 + 0.06 * frame.grow
            xScale: s
            yScale: s
            origin.x: {
                void popup.open;
                const p = popup.anchorItem.mapToItem(null, popup.anchorItem.width / 2, 0);
                return popup.sideways ? (popup.edge === "left" ? 0 : frame.width)
                                      : Math.max(0, Math.min(frame.width, p.x - popup.margins.left - frame.x));
            }
            origin.y: popup.fromTop ? 0 : popup.sideways ? frame.height / 2 : frame.height
        }

        HoverHandler { id: paneHover }

        GlassFrame {
            id: glassPane
            anchors.fill: parent
            visible: !popup.bare
            shadow: !popup.bare && Theme.glassShadows
            tint: Theme.glassMenu
        }

        Item {
            id: body
            // The menu's top level (keyboard navigation).
            readonly property bool menuLevel: true
            readonly property var ownerItem: null
            anchors.fill: parent
            anchors.margins: popup.padding
            // GlassFrame nudges its own surface; the content needs it too.
            transform: Translate { x: 0.001; y: 0.001 }
            implicitWidth: { let w = 0; for (const c of children) if (c.visible) w = Math.max(w, c.implicitWidth); return w; }
            implicitHeight: { let h = 0; for (const c of children) if (c.visible) h = Math.max(h, c.implicitHeight); return h; }
        }
    }
}
