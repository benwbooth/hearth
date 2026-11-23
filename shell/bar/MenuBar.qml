import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../widgets"
import "../services"
import ".."

// The macOS-style menu bar (layout "mac"): system menu, the focused app's
// name and menus on the left; tray, indicators and clock on the right.
// macOS 26 look (README "Look"): 24 pt tall, 13 pt text, the app name bold,
// titles 10 pt apart, a translucent capsule behind the open item.
// Transparent (Tahoe's default: items float on the wallpaper over a faint
// shade, lifted by a soft shadow), liquid glass or solid (Settings > Menu
// Bar > Style); the compositor blurs behind it (namespace hearth-menubar,
// layer rule hearth-glass in hypr/hyprland.lua, arbor/hearth-layer-rules.kdl).
//
// Menus behave like macOS's: they open on press, press-drag-release
// chooses an item, hovering another title while one is open switches to
// it, Left/Right move between them (pressTitle/dragTitle/releaseTitle/
// hoverTitle/switchMenu, used by BarButton and GlobalMenu's titles).
// With "automatically hide the menu bar" it slides up and comes back when
// the pointer touches the top edge.
PanelWindow {
    id: bar
    required property ShellScreen modelData
    screen: modelData

    // Read by BarButton / BarPopup / Tooltip in this window.
    readonly property string edge: "top"
    readonly property int barHeight: Theme.menuBarHeight
    readonly property int barIconSize: Theme.menuBarIconSize
    readonly property real barFontSize: Theme.menuBarFontSize
    // Popups clear the bar themselves when it reserves no space (auto-hide).
    readonly property int popupGap: autohide ? barHeight : 0

    readonly property bool autohide: Settings.menubar.autohide
    readonly property bool popupOpen: !!ShellState.activePopup && ShellState.activePopup.barWindow === bar
    readonly property bool revealed: !autohide || hover.hovered || popupOpen

    anchors { left: true; right: true; top: true }
    // Room below the bar for the glass style's soft shadow (transparent;
    // windows still only make room for barHeight, and only the bar itself
    // takes the pointer: see mask). Fixed, so the surface never resizes.
    readonly property int shadowRoom: 10
    implicitHeight: barHeight + shadowRoom
    exclusiveZone: autohide ? 0 : barHeight
    color: "transparent"
    WlrLayershell.namespace: "hearth-menubar"
    WlrLayershell.layer: WlrLayer.Top
    // While one of its menus is open the bar takes the keyboard when the
    // pointer is on it (Hyprland focuses on-demand layers under the
    // pointer), and hands the keys to the menu: arrows, Return, Escape and
    // type-ahead work right after clicking a title, before the pointer
    // ever enters the menu.
    // Handing the keyboard back waits until the menu has faded out: changing
    // it reconfigures the bar's layer surface, and doing that in the same
    // frame the menu unmapped made the bar flicker for a frame on arbor.
    property bool keyboardHeld: false
    onPopupOpenChanged: { if (popupOpen) { keyboardRelease.stop(); keyboardHeld = true; } else keyboardRelease.restart(); }
    Timer { id: keyboardRelease; interval: Theme.menuOutMs + 60; onTriggered: bar.keyboardHeld = false }
    WlrLayershell.keyboardFocus: popupOpen || keyboardHeld ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    Item {
        focus: true
        Keys.onPressed: event => {
            const a = ShellState.activePopup;
            if (a && a.open && a.barWindow === bar) a.handleKey(event);
        }
    }
    // Hidden: only a 2 px strip along the top edge takes the pointer.
    mask: Region { item: bar.revealed ? content : strip }

    Item {
        id: strip
        width: parent.width
        height: 2
    }
    HoverHandler { id: hover }

    // How bright the wallpaper is under the bar, so the transparent bar's
    // items can be white or black like macOS 26's: the top 4% of the
    // picture *as shown on this screen*: the file this screen's wallpaper
    // view shows, covering the screen's shape around its centre like Qt
    // draws it. Sampling the original's own top edge read
    // a bright sky that the ultrawide crop cuts off, and turned the items
    // black over dark rooftops.
    Image {
        id: wallSample
        visible: false
        // The exact file this screen's wallpaper shows (services/Wallpaper.qml
        // views: the smart-cropped copy when there is one).
        readonly property var view: bar.screen ? (Wallpaper.views[bar.screen.name] || null) : null
        readonly property string shown: view && view.file ? view.file : (Wallpaper.file || "")
        readonly property string url: shown ? (shown.startsWith("/") ? "file://" + shown : shown) : ""
        source: url
        sourceSize.width: 192
        asynchronous: true
        onStatusChanged: if (status === Image.Ready) sampler.loadImage(url)
    }
    Canvas {
        id: sampler
        // The screen's shape, 96 px wide.
        width: 96
        height: Math.max(8, Math.round(96 * (bar.screen ? bar.screen.height / Math.max(1, bar.screen.width) : 9 / 16)))
        visible: false
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onImageLoaded: requestPaint()
        onPaint: {
            const url = wallSample.url;
            if (!url || !isImageLoaded(url)) return;
            const ctx = getContext("2d");
            ctx.reset();
            // Cover the canvas like the wallpaper covers the screen.
            const iw = Math.max(1, wallSample.implicitWidth), ih = Math.max(1, wallSample.implicitHeight);
            const k = Math.max(width / iw, height / ih);
            ctx.drawImage(url, (width - iw * k) / 2, (height - ih * k) / 2, iw * k, ih * k);
            const rows = Math.max(1, Math.round(height * 0.04));
            const d = ctx.getImageData(0, 0, width, rows).data;
            // Black items only where black reads everywhere: the strip has to
            // be light nearly all the way across. As soon as a real part of
            // it is dark (houses at one end, a dark sky band), the items go
            // white, which the bar's shade keeps readable over light parts.
            let dark = 0, n = 0;
            for (let i = 0; i < d.length; i += 4) {
                const l = (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255;
                if (l < 0.6) dark++;
                n++;
            }
            if (n) Theme.wallpaperLight = dark / n < 0.12;
            unloadImage(url);
        }
    }

    // --- menu behaviour ---
    property var menus: []          // menu bar menus (BarPopup.menuBarMenu), for Left/Right
    function registerMenu(p) { if (menus.indexOf(p) < 0) menus = menus.concat([p]); }
    function unregisterMenu(p) { menus = menus.filter(m => m !== p); }
    function xOf(p) { return p.anchorItem.mapToItem(null, 0, 0).x; }
    function switchMenu(from, dir) {
        const l = menus.filter(m => m.anchorItem && m.anchorItem.visible && m.anchorItem.enabled !== false)
                       .sort((a, b) => xOf(a) - xOf(b));
        const i = l.indexOf(from);
        if (i < 0 || l.length < 2) return;
        const next = l[(i + dir + l.length) % l.length];
        next.open = true;
        Qt.callLater(() => next.move(1));
    }
    // Hovering an item while another of this bar's menus is open.
    function hoverTitle(popup) {
        const a = ShellState.activePopup;
        if (a && a.open && a !== popup && a.barWindow === bar) popup.open = true;
    }
    // Press on an item: open its menu at once. While the button is held
    // the bar keeps the pointer (the menu's focus grab waits for the
    // release: BarPopup.pressHeld), so the bar feeds the pointer to the
    // menu (BarPopup.dragAt selects the row under it) or opens the title
    // under it. Releasing on a row chooses it, on a title keeps that menu
    // open, anywhere else closes it; a plain click on the open menu's title
    // closes it. Like macOS.
    property bool dragging: false
    property bool dragSeen: false
    property bool pressWasOpen: false
    property point pressAt
    property var heldPopup: null
    function hold(popup) {
        if (heldPopup && heldPopup !== popup) heldPopup.pressHeld = false;
        heldPopup = popup;
        if (popup) popup.pressHeld = true;
    }
    function pressTitle(item, popup, mouse) {
        pressWasOpen = popup.open;
        dragging = true;
        dragSeen = false;
        pressAt = item.mapToItem(null, mouse.x, mouse.y);
        hold(popup);
        if (!popup.open) popup.open = true;
    }
    function dragTitle(item, popup, mouse) {
        const g = item.mapToItem(null, mouse.x, mouse.y);
        if (Math.hypot(g.x - pressAt.x, g.y - pressAt.y) > 3) dragSeen = true;
        if (g.y >= 0 && g.y < bar.barHeight) {
            const other = menuUnder(g.x);
            if (other && !other.open) { hold(other); other.open = true; }
        }
        const a = ShellState.activePopup;
        if (a && a.open && a.dragAt) a.dragAt(g.x, g.y);
    }
    function releaseTitle(item, popup, mouse) {
        dragging = false;
        hold(null);
        const a = ShellState.activePopup;
        if (!a || !a.open) return;
        if (!dragSeen) {
            if (pressWasOpen && a === popup) popup.close();
            return;
        }
        const g = item.mapToItem(null, mouse.x, mouse.y);
        if (a.releaseAt(g.x, g.y)) return;
        if (a.containsScreenPoint(g.x, g.y)) return;
        if (g.y >= 0 && g.y < bar.barHeight && menuUnder(g.x)) return;
        a.close();
    }
    // The popup whose title (any bar button with a menu) is at x.
    property var titleItems: []
    function registerTitle(item) { if (titleItems.indexOf(item) < 0) titleItems = titleItems.concat([item]); }
    function unregisterTitle(item) { titleItems = titleItems.filter(t => t !== item); }
    function menuUnder(x) {
        for (const t of titleItems) {
            if (!t.visible || !t.menuPopup || t.enabled === false) continue;
            const p = t.mapToItem(null, 0, 0);
            if (x >= p.x && x < p.x + t.width) return t.menuPopup;
        }
        return null;
    }

    // --- fitting the status items (right side) on narrow screens ---
    // The app's menus come first (like macOS): the status items get the
    // room left after every title. What doesn't fit moves into the tray's
    // chevron dropdown, in this order: app tray icons (from the left), the
    // wide widgets, then the less important indicators. The clock, Control
    // Center, Spotlight, notifications, battery, network and sound stay,
    // unless Settings > Menu Bar lets them go (menubar.overflow: key ->
    // true "may move" / false "always stays").
    readonly property var overflowOrder: ["sysmonitor", "workspaces", "weather", "devapps", "ai", "media", "clipboard",
        "zones", "rdp", "printers", "drives", "keyboard", "brightness", "bluetooth", "help", "camera", "recording"]
    readonly property var overflowPinned: ["volume", "network", "battery", "notifications", "spotlight", "controlcenter", "clock"]
    // Pinned ones Settings can let go (the others have no dropdown form).
    readonly property var overflowReleasable: ["volume", "network", "battery"]
    function mayOverflow(key) {
        const o = (Settings.menubar.overflow || {})[key];
        return o !== undefined ? !!o : overflowPinned.indexOf(key) < 0;
    }
    readonly property real statusRoom: {
        const leftEnd = left.x + globalMenu.x + globalMenu.naturalWidth + Math.round(12 * Theme.pt);
        return items.width - right.anchors.rightMargin - leftEnd;
    }
    readonly property var statusEntries: [
        { key: "workspaces", w: workspaces.implicitWidth + workspaces.Layout.rightMargin, on: workspaces.present },
        { key: "sysmonitor", w: sysMonitor.implicitWidth, on: !!Settings.menubar.showSysMonitor },
        { key: "devapps", w: devApps.implicitWidth, on: devApps.present },
        { key: "help", w: help.implicitWidth, on: true },
        { key: "spotlight", w: spotlight.implicitWidth, on: spotlight.visible },
        { key: "controlcenter", w: controlCenter.implicitWidth, on: controlCenter.visible },
        { key: "ai", w: assistant.implicitWidth, on: assistant.present },
        { key: "clock", w: clock.implicitWidth, on: clock.visible }
    ].concat(tray.entries)
    readonly property var overflow: {
        const room = statusRoom;
        const entries = statusEntries;
        const sniN = tray.shownItems.length, sniW = Theme.menuBarItemWidth;
        let total = sniN * sniW;
        for (const e of entries) if (e.on) total += e.w;
        if (total + (tray.hiddenItems.length > 0 ? tray.chevronWidth : 0) <= room) return { keys: [], sni: 0 };
        total += tray.chevronWidth;
        const keys = [];
        let sni = 0;
        if (mayOverflow("trayicons")) while (sni < sniN && total > room) { sni++; total -= sniW; }
        // Unlisted items next, the normally pinned ones last (only when
        // Settings lets them go).
        const known = overflowOrder.concat(overflowPinned);
        const order = overflowOrder.concat(entries.map(e => e.key).filter(k => known.indexOf(k) < 0), overflowReleasable);
        for (const k of order) {
            if (total <= room) break;
            const e = entries.find(x => x.key === k);
            if (!e || !e.on || !mayOverflow(k)) continue;
            keys.push(k);
            total -= e.w;
        }
        // Taking out a wide item can leave room for things that went
        // before it: back they come, the most important first.
        for (let i = keys.length - 1; i >= 0; i--) {
            const e = entries.find(x => x.key === keys[i]);
            if (total + e.w <= room) { total += e.w; keys.splice(i, 1); }
        }
        while (sni > 0 && total + sniW <= room) { sni--; total += sniW; }
        // Nothing left in the dropdown: the chevron goes too.
        if (sni === 0 && keys.length === 0 && tray.hiddenItems.length === 0) return { keys: [], sni: 0 };
        return { keys: keys, sni: sni };
    }

    Item {
        id: content
        width: parent.width
        height: bar.barHeight
        y: bar.revealed ? 0 : -height
        // macOS slides the auto-hidden menu bar in and out in ~0.25 s.
        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

        // The bar's surface, by Settings > Menu Bar > Style:
        //  transparent: macOS 26's default. A faint shade from the top edge
        //    (too faint to be blurred), the items lifted off the wallpaper
        //    by a soft shadow.
        //  glass: liquid glass strip (GlassFrame, no corners or shadow).
        //  solid: an opaque strip.
        readonly property string style: Theme.menuBarStyle
        Rectangle {
            anchors.fill: parent
            visible: content.style === "solid"
            color: Theme.bg
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.border
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: content.style === "transparent"
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.barDark ? Qt.rgba(0, 0, 0, 0.16) : Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
            }
        }
        GlassFrame {
            anchors.fill: parent
            anchors.topMargin: -2
            visible: content.style === "glass"
            radius: 0
            shadow: false
            // The shader's rim is made for rounded panes; along a full-width
            // square bar it drew a flat white line. The edge is drawn below.
            rimVisible: false
            tint: Theme.menuBarTint
        }
        // The glass bar's bottom edge, macOS 26 style: light caught inside the
        // glass, a dark hairline where it ends, and a soft shadow falling onto
        // the windows below, so the bar reads as a raised pane.
        Item {
            visible: content.style === "glass"
            anchors.fill: parent
            Rectangle {
                y: parent.height - 2
                width: parent.width
                height: 1
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
            }
            Rectangle {
                y: parent.height - 1
                width: parent.width
                height: 1
                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.16)
            }
            Rectangle {
                y: parent.height
                width: parent.width
                height: bar.shadowRoom
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.28 : 0.12) }
                    GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.08 : 0.04) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                }
            }
        }

        // Soft shadow under every item on the transparent bar (macOS lifts
        // its menu bar text and symbols off the wallpaper the same way).
        MultiEffect {
            visible: content.style === "transparent"
            source: itemsSrc
            anchors.fill: items
            shadowEnabled: true
            shadowColor: Theme.barDark ? "#000000" : "#ffffff"
            shadowOpacity: Theme.barDark ? 0.55 : 0.6
            shadowBlur: 0.45
            shadowVerticalOffset: 0.5
            shadowHorizontalOffset: 0
            blurMax: 12
            // Only the shadow: the items themselves are drawn above, as is.
            opacity: 1
            paddingRect: Qt.rect(12, 12, 24, 24)
        }
        ShaderEffectSource {
            id: itemsSrc
            sourceItem: items
            hideSource: false
            live: true
            visible: false
            recursive: false
        }

        Item {
            id: items
            anchors.fill: parent

            RowLayout {
                id: left
                height: parent.height
                x: Math.round(6 * Theme.pt)
                spacing: 0
                transform: Translate { x: 0.001; y: 0.001 }
                SystemMenu {}
                // Menus that would run into the status items are left out
                // (macOS drops them too); the space ends 12 pt before them.
                GlobalMenu { id: globalMenu; maxWidth: right.x - left.x - x - Math.round(12 * Theme.pt) }
            }

            RowLayout {
                id: right
                anchors.right: parent.right
                anchors.rightMargin: Math.round(6 * Theme.pt)
                height: parent.height
                spacing: 0
                transform: Translate { x: 0.001; y: 0.001 }
                // Items that don't fit go into the tray's chevron dropdown
                // (BarButton.overflowed reads these).
                readonly property var overflowKeys: bar.overflow.keys
                readonly property Item overflowAnchor: tray.overflowAnchor

                // A map of the workspaces: click one to go there.
                Workspaces {
                    id: workspaces
                    readonly property bool present: Settings.menubar.showWorkspaces !== false
                    visible: present && bar.overflow.keys.indexOf("workspaces") < 0
                    screen: bar.screen
                    menuBarItem: true
                    Layout.rightMargin: Math.round(8 * Theme.pt)
                }
                SysMonitor {
                    id: sysMonitor
                    visible: !!Settings.menubar.showSysMonitor && bar.overflow.keys.indexOf("sysmonitor") < 0
                }
                DevApps { id: devApps; ipcName: "devapps"; iconSize: Theme.menuBarIconSize; implicitWidth: Theme.menuBarItemWidth }
                Tray {
                    id: tray
                    overflowKeys: bar.overflow.keys
                    sniOverflow: bar.overflow.sni
                    outsideItems: [{ key: "workspaces", item: workspaces }, { key: "sysmonitor", item: sysMonitor },
                                   { key: "devapps", item: devApps }]
                        .filter(e => bar.overflow.keys.indexOf(e.key) >= 0)
                        .concat([{ key: "help", item: help }, { key: "ai", item: assistant }]
                            .filter(e => e.item.overflowed))
                }
                HelpMenu { id: help }
                SpotlightButton { id: spotlight }
                ControlCenter { id: controlCenter }
                AssistantMenu { id: assistant }
                Clock { id: clock }
            }
        }
    }
}
